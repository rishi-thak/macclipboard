import AppKit
import ApplicationServices
import ClipOptCore

struct FocusedField {
    let element: AXUIElement
    let info: FieldInfo
    /// Field frame in Accessibility coordinates (top-left origin of the main screen).
    let frame: CGRect?
}

/// Reads the focused text field and, in Safari, the page it's on.
@MainActor
final class FieldReader {
    private let systemWide = AXUIElementCreateSystemWide()
    private let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
    }

    /// nil when no editable text field is focused, or the field is a password field.
    func focusedTextField() -> FocusedField? {
        guard let element = elementAttribute(systemWide, "AXFocusedUIElement") else { return nil }
        let role = string(element, "AXRole")
        let subrole = string(element, "AXSubrole")
        guard textRoles.contains(role), subrole != "AXSecureTextField" else { return nil }
        let (pageURL, pageTitle) = page(containing: element)
        return FocusedField(element: element, info: info(for: element, pageURL: pageURL, pageTitle: pageTitle),
                            frame: frame(element))
    }

    private func info(for element: AXUIElement, pageURL: String, pageTitle: String) -> FieldInfo {
        var label = [string(element, "AXTitle"), string(element, "AXDescription")]
        if let titleElement = elementAttribute(element, "AXTitleUIElement") {
            label.append(string(titleElement, "AXValue"))
            label.append(string(titleElement, "AXTitle"))
        }
        return FieldInfo(
            label: unique(label).joined(separator: " · "),
            placeholder: string(element, "AXPlaceholderValue"),
            help: string(element, "AXHelp"),
            identifier: string(element, "AXDOMIdentifier"),
            nearbyText: nearbyText(element),
            pageURL: pageURL,
            pageTitle: pageTitle,
            appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        )
    }

    // MARK: - Whole form

    /// Every empty, visible, non-password text field on the web page around `field`,
    /// in page order. Empty when the field isn't on a web page.
    func emptyFormFields(around field: FocusedField) -> [FocusedField] {
        guard let webArea = ancestor(of: field.element, role: "AXWebArea") else { return [] }
        let pageURL = urlString(webArea, "AXURL")
        let title = [string(webArea, "AXTitle"), string(webArea, "AXDescription")].first { !$0.isEmpty } ?? windowTitle(of: webArea)

        var found: [AXUIElement] = []
        var visited = 0
        // Depth-first in child order, so fields come out top to bottom.
        var stack: [(AXUIElement, Int)] = [(webArea, 0)]
        while let (node, depth) = stack.popLast(), visited < Self.maxNodes, found.count < Self.maxFields {
            visited += 1
            let role = string(node, "AXRole")
            if textRoles.contains(role) {
                if string(node, "AXSubrole") != "AXSecureTextField",
                   string(node, "AXValue").isEmpty,
                   bool(node, "AXEnabled") != false,
                   let rect = frame(node), rect.width > 1, rect.height > 1 {
                    found.append(node)
                }
                continue
            }
            guard depth < 60 else { continue }
            for child in elementArray(node, "AXChildren").reversed() {
                stack.append((child, depth + 1))
            }
        }
        return found.map { FocusedField(element: $0, info: info(for: $0, pageURL: pageURL, pageTitle: title), frame: frame($0)) }
    }

    static let maxNodes = 4000
    static let maxFields = 60

    /// Asks the page to move keyboard focus to `element`. Check with `isStillFocused` before typing.
    func focus(_ element: AXUIElement) {
        AXUIElementSetAttributeValue(element, "AXFocused" as CFString, kCFBooleanTrue)
    }

    func isEmpty(_ element: AXUIElement) -> Bool {
        string(element, "AXValue").isEmpty
    }

    private func ancestor(of element: AXUIElement, role: String) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let node = current else { return nil }
            if string(node, "AXRole") == role { return node }
            current = elementAttribute(node, "AXParent")
        }
        return nil
    }

    func isStillFocused(_ field: FocusedField) -> Bool {
        guard let current = elementAttribute(systemWide, "AXFocusedUIElement") else { return false }
        return CFEqual(current, field.element)
    }

    // MARK: - Page

    private func page(containing element: AXUIElement) -> (url: String, title: String) {
        var current: AXUIElement? = element
        for _ in 0..<40 {
            guard let node = current else { break }
            if string(node, "AXRole") == "AXWebArea" {
                let url = urlString(node, "AXURL")
                let title = [string(node, "AXTitle"), string(node, "AXDescription")].first { !$0.isEmpty } ?? ""
                return (url, title.isEmpty ? windowTitle(of: node) : title)
            }
            current = elementAttribute(node, "AXParent")
        }
        return ("", "")
    }

    private func windowTitle(of element: AXUIElement) -> String {
        guard let window = elementAttribute(element, "AXWindow") else { return "" }
        return string(window, "AXTitle")
    }

    // MARK: - Nearby label text

    /// The closest text just before the field, at the parent and then grandparent level.
    /// Catches forms that show a label without linking it to the input. Only the closest
    /// piece is used: anything further up is usually the previous field's hint or error.
    private func nearbyText(_ element: AXUIElement) -> String {
        var child = element
        for _ in 0..<2 {
            guard let parent = elementAttribute(child, "AXParent") else { break }
            let siblings = elementArray(parent, "AXChildren")
            if let index = siblings.firstIndex(where: { CFEqual($0, child) }) {
                for sibling in siblings[..<index].suffix(3).reversed() {
                    let text = staticText(in: sibling)
                    // Skip a lone "*" or "✱": it marks the field as required, it isn't the label.
                    if text.contains(where: \.isLetter) { return String(text.prefix(200)) }
                }
            }
            child = parent
        }
        return ""
    }

    private func staticText(in element: AXUIElement) -> String {
        if string(element, "AXRole") == "AXStaticText" { return string(element, "AXValue") }
        let texts = elementArray(element, "AXChildren").prefix(4)
            .filter { string($0, "AXRole") == "AXStaticText" }
            .map { string($0, "AXValue") }
        return texts.joined(separator: " ")
    }

    // MARK: - AX helpers

    private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        guard let value = copy(element, attribute) else { return "" }
        if CFGetTypeID(value) == CFStringGetTypeID() {
            return (value as! String).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func urlString(_ element: AXUIElement, _ attribute: String) -> String {
        guard let value = copy(element, attribute) else { return "" }
        if CFGetTypeID(value) == CFURLGetTypeID() { return (value as! URL).absoluteString }
        if CFGetTypeID(value) == CFStringGetTypeID() { return value as! String }
        return ""
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func elementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let value = copy(element, attribute), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AnyObject] ?? []).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = copy(element, "AXPosition"), let sizeValue = copy(element, "AXSize"),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func unique<S: Sequence>(_ values: S) -> [String] where S.Element == String {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
