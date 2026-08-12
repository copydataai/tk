import AppKit
import ApplicationServices

enum MacAccessibility {
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
