import AppKit
import ClipOptCore

/// Double tap of Cmd+Opt+V: fills every empty field on the page it's sure about
/// (profile, saved answers, one clear Jev pick) and leaves the rest for you.
@MainActor
final class FormFillRunner {
    private let fieldReader: FieldReader
    private let paster: Paster
    private let jev: JevClient?
    private let toast = Toast()
    /// A newer press or run cancels this one between fields.
    private var runToken = 0

    /// Time for the page to move focus before pasting, and for Safari to read the
    /// clipboard before the next value replaces it.
    static let focusDelay: Duration = .milliseconds(70)
    static let pasteDelay: Duration = .milliseconds(150)

    init(fieldReader: FieldReader, paster: Paster, jev: JevClient?) {
        self.fieldReader = fieldReader
        self.paster = paster
        // One request covers many fields, so it gets more time than a single paste.
        self.jev = jev.map { JevClient(apiKey: $0.apiKey, timeout: 6) }
    }

    func cancel() { runToken += 1 }

    /// - Parameter skip: a field the first tap already pasted into.
    func run(from origin: FocusedField, history: [ClipItem], skip: AXUIElement?) {
        runToken += 1
        let token = runToken
        let start = ContinuousClock.now

        var fields = fieldReader.emptyFormFields(around: origin)
        if let skip { fields.removeAll { CFEqual($0.element, skip) } }
        let scanMs = (ContinuousClock.now - start).milliseconds
        guard !fields.isEmpty else {
            DecisionLog.write("form_fill fields=0 scan_ms=\(scanMs)")
            toast.show("No empty fields to fill")
            return
        }

        let infos = fields.map(\.info)
        let memory = FieldMemory.load(from: AppPaths.answers)
        var plan = FormFiller.planLocally(fields: infos, profile: Profile.load(from: AppPaths.profile), memory: memory)
        let jevPlan = jev == nil ? nil : FormFiller.jevPlan(plan, memory: memory, history: history)
        if jevPlan == nil, plan.fills.isEmpty {
            DecisionLog.write("form_fill fields=\(fields.count) nothing_sure scan_ms=\(scanMs)")
            toast.show("Nothing I'm sure about here. Fill these yourself")
            return
        }

        Task { @MainActor [weak self] in
            var jevNote = "jev=-"
            if let self, let jev = self.jev, let jevPlan {
                let jevStart = ContinuousClock.now
                do {
                    let body = try JevRequestBuilder.formBody(fields: infos, plan: jevPlan)
                    AppPaths.writePrivate(body, to: AppPaths.lastJevRequest)
                    let answers = JevAnswers(try await jev.ask(body))
                    let extra = FormFiller.fills(afterJev: answers, plan: jevPlan)
                    for (index, fill) in extra where plan.fills[index] == nil { plan.fills[index] = fill }
                    jevNote = "jev=\(extra.count)/\(jevPlan.fields.count) jev_ms=\((ContinuousClock.now - jevStart).milliseconds) questions=\(jevPlan.fields.count * jevPlan.candidates.count)"
                } catch {
                    let message = (error as? JevError)?.description ?? "Couldn't reach Jev"
                    jevNote = "jev_failed=\(message)"
                }
            }
            guard let self, token == self.runToken else { return }
            await self.fill(fields, plan: plan, origin: origin, token: token, start: start,
                            logPrefix: "form_fill fields=\(fields.count) scan_ms=\(scanMs) \(jevNote)")
        }
    }

    private func fill(_ fields: [FocusedField], plan: FormFillPlan, origin: FocusedField, token: Int,
                      start: ContinuousClock.Instant, logPrefix: String) async {
        let app = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var filled: [FillSource] = []
        var stopped = false

        for index in plan.fills.keys.sorted() {
            // Stop if you pressed again or switched apps; never paste somewhere unexpected.
            guard token == runToken, NSWorkspace.shared.frontmostApplication?.processIdentifier == app else {
                stopped = true
                break
            }
            let target = fields[index]
            guard fieldReader.isEmpty(target.element), let fill = plan.fills[index] else { continue }
            fieldReader.focus(target.element)
            try? await Task.sleep(for: Self.focusDelay)
            guard fieldReader.isStillFocused(target) else { continue }
            paster.paste(fill.text)
            filled.append(fill.source)
            try? await Task.sleep(for: Self.pasteDelay)
        }
        if !stopped { fieldReader.focus(origin.element) }

        let left = fields.count - filled.count
        let profileCount = filled.filter { if case .profile = $0 { return true } else { return false } }.count
        let rememberedCount = filled.filter { $0 == .remembered }.count
        let jevCount = filled.filter { $0 == .jev }.count
        DecisionLog.write("\(logPrefix) filled=\(filled.count) profile=\(profileCount) remembered=\(rememberedCount) jev=\(jevCount) left=\(left) stopped=\(stopped) total_ms=\((ContinuousClock.now - start).milliseconds)")

        if stopped {
            toast.show("Stopped after \(Self.fields(filled.count))")
        } else if filled.isEmpty {
            toast.show("Nothing I'm sure about here. Fill these yourself")
        } else {
            toast.show(left > 0 ? "Filled \(Self.fields(filled.count)) · \(left) left for you" : "Filled \(Self.fields(filled.count))")
        }
    }

    private static func fields(_ count: Int) -> String { count == 1 ? "1 field" : "\(count) fields" }
}
