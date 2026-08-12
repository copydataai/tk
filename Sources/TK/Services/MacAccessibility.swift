import AppKit
import ApplicationServices

enum MacAccessibility {
    struct InsertionTarget {
        let element: AXUIElement
        let fingerprint: InsertionTargetFingerprint
        let supportsSelectedTextWrite: Bool
    }

    static func element(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static var focusedElement: AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success else { return nil }
        return element(from: value)
    }

    static func insertionTarget(from element: AXUIElement?) -> InsertionTarget? {
        guard let element, let fingerprint = fingerprint(of: element) else { return nil }
        var settable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        return InsertionTarget(
            element: element,
            fingerprint: fingerprint,
            supportsSelectedTextWrite: settableResult == .success && settable.boolValue
        )
    }

    static func fingerprint(of element: AXUIElement) -> InsertionTargetFingerprint? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success else { return nil }
        let role = stringAttribute(kAXRoleAttribute, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        let bundleIdentifier = NSRunningApplication(processIdentifier: processIdentifier)?
            .bundleIdentifier
        let windowDigest = windowDigest(for: element)
        let readableStateDigest = safeReadableStateDigest(
            of: element,
            role: role,
            subrole: subrole
        )
        return InsertionTargetFingerprint(
            processIdentifier: processIdentifier,
            bundleIdentifier: bundleIdentifier,
            role: role,
            subrole: subrole,
            windowDigest: windowDigest,
            elementIdentity: UInt(CFHash(element)),
            readableStateDigest: readableStateDigest
        )
    }

    static func selectedText(of element: AXUIElement) -> String? {
        stringAttribute(kAXSelectedTextAttribute, of: element)
    }

    static func value(of element: AXUIElement) -> String? {
        stringAttribute(kAXValueAttribute, of: element)
    }

    static func selectedTextRange(of element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard
              AXValueGetType(axValue) == .cfRange else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func setSelectedTextRange(_ range: NSRange, of element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
    }

    private static func safeReadableStateDigest(
        of element: AXUIElement,
        role: String?,
        subrole: String?
    ) -> String? {
        guard subrole != "AXSecureTextField",
              role == kAXTextFieldRole as String || role == kAXTextAreaRole as String else {
            return nil
        }
        let state = selectedText(of: element) ?? value(of: element)
        return state.map(InsertionTargetFingerprint.digest)
    }

    private static func windowDigest(for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXWindowAttribute as CFString,
            &value
        ) == .success,
              let window = self.element(from: value) else {
            return nil
        }
        let identifier = stringAttribute(kAXIdentifierAttribute, of: window)
        let title = stringAttribute(kAXTitleAttribute, of: window)
        return (identifier ?? title).map(InsertionTargetFingerprint.digest)
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func restoreFocus(to target: AXUIElement) async throws {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(target, &processIdentifier) == .success else { return }

        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            target,
            kAXWindowAttribute as CFString,
            &windowValue
        ) == .success,
           let window = element(from: windowValue) {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }

        NSRunningApplication(processIdentifier: processIdentifier)?.activate()
        AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)

        for _ in 0..<20 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier {
                try await Task.sleep(for: .milliseconds(50))
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
