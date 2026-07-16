import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox

enum MacTextError: LocalizedError {
    case accessibilityRequired
    case noFocusedControl
    case noSelectedText
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            "Enable tk in System Settings → Privacy & Security → Accessibility"
        case .noFocusedControl:
            "No editable text field is focused"
        case .noSelectedText:
            "Select some text first"
        case .eventCreationFailed:
            "macOS could not send the keyboard event"
        }
    }
}

@MainActor
final class MacTextService {
    private let speechSynthesizer = AVSpeechSynthesizer()

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func insert(_ text: String) async throws {
        guard hasAccessibilityPermission else { throw MacTextError.accessibilityRequired }
        guard !text.isEmpty else { return }

        if let focusedElement,
           AXUIElementSetAttributeValue(
               focusedElement,
               kAXSelectedTextAttribute as CFString,
               text as CFTypeRef
           ) == .success {
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        try postCommandKey(UInt16(kVK_ANSI_V))
        // ponytail: fixed delay keeps the clipboard intact; add per-app confirmation if slow apps miss pastes.
        try await Task.sleep(for: .milliseconds(150))
        snapshot.restore(to: pasteboard)
    }

    func selectedText() async throws -> String {
        guard hasAccessibilityPermission else { throw MacTextError.accessibilityRequired }

        if let focusedElement {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                focusedElement,
                kAXSelectedTextAttribute as CFString,
                &value
            ) == .success,
               let text = value as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let changeCount = pasteboard.changeCount
        try postCommandKey(UInt16(kVK_ANSI_C))
        try await Task.sleep(for: .milliseconds(150))
        defer { snapshot.restore(to: pasteboard) }

        guard pasteboard.changeCount != changeCount,
              let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MacTextError.noSelectedText
        }
        return text
    }

    func speak(_ text: String) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechSynthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stopSpeaking() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    private var focusedElement: AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func postCommandKey(_ keyCode: CGKeyCode) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw MacTextError.eventCreationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
