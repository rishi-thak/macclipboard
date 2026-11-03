import AppKit
import ClipOptCore

/// Runs one Cmd+Opt+V press end to end: read field → decide locally → maybe ask Jev → paste or panel.
@MainActor
final class SmartPasteCoordinator {
    private var history: ClipboardHistory
    private let fieldReader = FieldReader()
    private let paster: Paster
    private let panel = HistoryPanelController()
    private let jev: JevClient?

    /// Jev's answer to "is this a job application?", per page.
    private var savedJobAnswers: [String: Bool] = [:]
    /// Lets a quick second press swap the guess for the panel.
    private var lastSmartPaste: (time: ContinuousClock.Instant, field: AXUIElement)?
    /// Only the newest press may act on a Jev answer.
    private var requestToken = 0
    private var pending: (token: Int, field: FocusedField, input: SmartPasteInput, plan: JevPlan, started: ContinuousClock.Instant)?

    static let doublePressWindow: Duration = .milliseconds(1500)

    var hasJev: Bool { jev != nil }

    init(history: ClipboardHistory, paster: Paster, jev: JevClient?) {
        self.history = history
        self.paster = paster
        self.jev = jev
    }

    // MARK: - History

    func record(_ text: String) {
        guard history.record(text) != nil else { return }
        do {
            try history.save(to: AppPaths.history)
        } catch {
            Log.watcher.error("saving history failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// From the menu bar: show history and paste the pick wherever focus is.
    func showHistory() {
        let input = SmartPasteInput(field: FieldInfo(), fieldKind: .unknown, context: .unknown,
                                    profile: Profile.load(from: AppPaths.profile), history: history.items)
        showPanel(candidates: SmartPasteEngine.allCandidates(input), highlight: nil, note: nil, anchor: nil, learn: nil)
    }

    // MARK: - Hotkey

    func handleHotKey() {
        let start = ContinuousClock.now
        if panel.isVisible {
            panel.close()
            return
        }

        guard let field = fieldReader.focusedTextField() else {
            KeyPoster.passThrough()
            return
        }

        let profile = Profile.load(from: AppPaths.profile)
        let input = SmartPasteInput(
            field: field.info,
            fieldKind: FieldClassifier.classify(field.info),
            context: JobSiteDetector.context(pageURL: field.info.pageURL, savedAnswers: savedJobAnswers),
            profile: profile,
            history: history.items
        )

        // Second press right after a smart paste: undo it and let you pick.
        if let last = lastSmartPaste, ContinuousClock.now - last.time < Self.doublePressWindow, CFEqual(last.field, field.element) {
            lastSmartPaste = nil
            KeyPoster.undo()
            DecisionLog.write("kind=\(input.fieldKind.rawValue) double_press → undo + panel")
            showPanel(candidates: SmartPasteEngine.panelCandidates(input), highlight: nil, note: "Pick the right one",
                      anchor: field.frame, learn: SmartPasteEngine.learnableKind(input))
            return
        }

        let decision = SmartPasteEngine.decideLocally(input)
        DecisionLog.write("kind=\(input.fieldKind.rawValue) context=\(input.context) history=\(input.history.count) profile=\(input.profile.entries.count) local_ms=\((ContinuousClock.now - start).milliseconds) → \(Self.summary(decision))")
        Log.paste.info("kind=\(input.fieldKind.rawValue, privacy: .public) context=\(String(describing: input.context), privacy: .public) local_ms=\((ContinuousClock.now - start).milliseconds, privacy: .public)")
        apply(decision, field: field, input: input, started: start)
    }

    private func apply(_ decision: PasteDecision, field: FocusedField, input: SmartPasteInput, started: ContinuousClock.Instant) {
        switch decision {
        case .paste(let candidate):
            paster.paste(candidate.text)
            lastSmartPaste = (ContinuousClock.now, field.element)
            Log.paste.info("pasted source=\(Self.describe(candidate.source), privacy: .public) total_ms=\((ContinuousClock.now - started).milliseconds, privacy: .public)")

        case .showPanel(let highlight, let candidates, let note):
            showPanel(candidates: candidates, highlight: highlight, note: note, anchor: field.frame,
                      learn: SmartPasteEngine.learnableKind(input))

        case .askJev(let plan):
            guard let jev else {
                showPanel(candidates: SmartPasteEngine.panelCandidates(input), highlight: nil,
                          note: "Add JEV_API_KEY to turn on smart matching", anchor: field.frame,
                          learn: SmartPasteEngine.learnableKind(input))
                return
            }
            let body: Data
            do {
                body = try JevRequestBuilder.body(field: input.field, plan: plan)
            } catch {
                apply(SmartPasteEngine.decideAfterFailure(input: input, message: "Couldn't build the Jev request"),
                      field: field, input: input, started: started)
                return
            }
            AppPaths.writePrivate(body, to: AppPaths.lastJevRequest)

            requestToken += 1
            let token = requestToken
            pending = (token, field, input, plan, started)
            Task { @MainActor [weak self] in
                let result: Result<JevResponse, Error>
                do { result = .success(try await jev.ask(body)) } catch { result = .failure(error) }
                self?.finishJev(token: token, result: result)
            }
        }
    }

    private func finishJev(token: Int, result: Result<JevResponse, Error>) {
        guard let pending, pending.token == token else { return }
        self.pending = nil
        let jevMs = (ContinuousClock.now - pending.started).milliseconds

        let decision: PasteDecision
        switch result {
        case .success(let response):
            let answers = JevAnswers(response)
            Log.jev.info("model=\(response.model, privacy: .public) round_trip_ms=\(jevMs, privacy: .public) input_tokens=\(response.usage?.input_tokens ?? -1, privacy: .public)")
            saveJobAnswer(answers, pageURL: pending.input.field.pageURL)
            decision = SmartPasteEngine.decide(afterJev: answers, plan: pending.plan, input: pending.input)
            let scores = pending.plan.candidates.indices.map { answers.noul(JevQuestions.ID.fits($0)).map { String(format: "%.2f", $0) } ?? "-" }
            let anything = answers.noul(JevQuestions.ID.anythingFits).map { String(format: "%.2f", $0) } ?? "-"
            let job = answers.noul(JevQuestions.ID.isJobApplication).map { String(format: "%.2f", $0) } ?? "-"
            DecisionLog.write("  jev \(response.model) \(jevMs)ms fits=[\(scores.joined(separator: ","))] anything=\(anything) job=\(job) → \(Self.summary(decision))")
        case .failure(let error):
            let message = (error as? JevError)?.description ?? "Couldn't reach Jev"
            Log.jev.error("failed after \(jevMs, privacy: .public) ms: \(message, privacy: .public)")
            DecisionLog.write("  jev failed after \(jevMs)ms: \(message)")
            decision = SmartPasteEngine.decideAfterFailure(input: pending.input, message: message)
        }

        // You moved on while Jev was answering: don't paste into the wrong place.
        guard fieldReader.isStillFocused(pending.field) else {
            Log.paste.info("focus changed during Jev request; dropped")
            return
        }
        apply(decision, field: pending.field, input: pending.input, started: pending.started)
    }

    private func saveJobAnswer(_ answers: JevAnswers, pageURL: String) {
        guard let job = answers.noul(JevQuestions.ID.isJobApplication),
              let key = JobSiteDetector.pageKey(for: pageURL) else { return }
        if job >= JevQuestions.yesThreshold { savedJobAnswers[key] = true }
        if job <= JevQuestions.noThreshold { savedJobAnswers[key] = false }
    }

    // MARK: - Panel

    /// - Parameter learn: when set, your pick is saved to the profile as this kind,
    ///   so the next field like this one fills without the panel.
    private func showPanel(candidates: [Candidate], highlight: Candidate?, note: String?, anchor: CGRect?, learn: FieldKind?) {
        var ordered = candidates
        if let highlight, let index = ordered.firstIndex(of: highlight) {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        // Profile values for other fields would only be noise here.
        if let learn {
            ordered = ordered.filter { candidate in
                if case .profile(let kind) = candidate.source { return kind == learn }
                return true
            }
        }
        var header = note
        if let learn {
            let hint = "Your pick is saved as your \(learn.displayName)"
            header = note.map { "\($0) · \(hint)" } ?? hint
        }
        let entries = ordered.map { HistoryPanelController.Entry(text: $0.text, detail: Self.detail(for: $0)) }
        panel.show(entries: entries, selected: 0, note: header, anchor: anchor) { [weak self] entry in
            Task { @MainActor [weak self] in
                // Let Safari's field take focus back before pasting.
                try? await Task.sleep(for: .milliseconds(60))
                self?.paster.paste(entry.text)
                if let learn { self?.learn(entry.text, as: learn) }
            }
        }
    }

    private func learn(_ text: String, as kind: FieldKind) {
        guard SmartPasteEngine.pickFits(text, kind: kind) else {
            DecisionLog.write("  pick not saved: doesn't look like a \(kind.displayName)")
            return
        }
        var profile = Profile.load(from: AppPaths.profile)
        guard profile.value(for: kind) == nil else { return }
        profile.set(text.trimmingCharacters(in: .whitespacesAndNewlines), for: kind)
        do {
            try profile.save(to: AppPaths.profile)
            DecisionLog.write("  saved pick to profile.\(kind.rawValue)")
        } catch {
            Log.app.error("saving profile failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func summary(_ decision: PasteDecision) -> String {
        switch decision {
        case .paste(let candidate): return "paste \(describe(candidate.source))"
        case .askJev(let plan): return "ask jev (\(plan.candidates.count) candidates, job_q=\(plan.askJobQuestion))"
        case .showPanel(let highlight, let candidates, let note):
            return "panel (\(candidates.count) items, highlight=\(highlight != nil), note=\(note ?? "-"))"
        }
    }

    private static func detail(for candidate: Candidate) -> String {
        switch candidate.source {
        case .profile(let kind):
            return "Profile · \(kind.rawValue)"
        case .history:
            guard let date = candidate.copiedAt else { return "Copied" }
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Copied " + formatter.localizedString(for: date, relativeTo: Date())
        }
    }

    private static func describe(_ source: Candidate.Source) -> String {
        switch source {
        case .profile(let kind): return "profile.\(kind.rawValue)"
        case .history: return "history"
        }
    }
}
