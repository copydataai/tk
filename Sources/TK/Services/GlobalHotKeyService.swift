import Carbon.HIToolbox
import Foundation

enum HotKeyOption: String, Identifiable {
    case controlOptionSpace
    case controlOptionD
    case commandShiftD
    case controlOptionR
    case controlOptionS
    case commandShiftR

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlOptionSpace: "⌃⌥Space"
        case .controlOptionD: "⌃⌥D"
        case .commandShiftD: "⇧⌘D"
        case .controlOptionR: "⌃⌥R"
        case .controlOptionS: "⌃⌥S"
        case .commandShiftR: "⇧⌘R"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .controlOptionSpace: UInt32(kVK_Space)
        case .controlOptionD, .commandShiftD: UInt32(kVK_ANSI_D)
        case .controlOptionR, .commandShiftR: UInt32(kVK_ANSI_R)
        case .controlOptionS: UInt32(kVK_ANSI_S)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .commandShiftD, .commandShiftR: UInt32(cmdKey | shiftKey)
        default: UInt32(controlKey | optionKey)
        }
    }

    static let dictationChoices: [HotKeyOption] = [
        .controlOptionSpace, .controlOptionD, .commandShiftD
    ]
    static let readingChoices: [HotKeyOption] = [
        .controlOptionR, .controlOptionS, .commandShiftR
    ]
}

private let hotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        service.perform(id: hotKeyID.id)
    }
    return noErr
}

final class GlobalHotKeyService {
    var onDictation: (() -> Void)?
    var onReadSelection: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var dictationRef: EventHotKeyRef?
    private var readingRef: EventHotKeyRef?

    func start() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    func configure(dictation: HotKeyOption, reading: HotKeyOption) -> Bool {
        unregisterHotKeys()
        let dictationStatus = register(dictation, id: 1, reference: &dictationRef)
        let readingStatus = register(reading, id: 2, reference: &readingRef)
        return dictationStatus == noErr && readingStatus == noErr
    }

    func perform(id: UInt32) {
        switch id {
        case 1: onDictation?()
        case 2: onReadSelection?()
        default: break
        }
    }

    private func register(
        _ shortcut: HotKeyOption,
        id: UInt32,
        reference: inout EventHotKeyRef?
    ) -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: OSType(0x746B6879), id: id)
        return RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
    }

    private func unregisterHotKeys() {
        if let dictationRef { UnregisterEventHotKey(dictationRef) }
        if let readingRef { UnregisterEventHotKey(readingRef) }
        dictationRef = nil
        readingRef = nil
    }

    deinit {
        unregisterHotKeys()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
