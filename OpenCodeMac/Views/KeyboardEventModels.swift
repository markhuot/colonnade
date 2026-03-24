import AppKit

struct SessionListEscapeKeyEvent {
    static func shouldRequestStop(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isListFocused: Bool) -> Bool {
        guard isListFocused else { return false }

        let activeModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard activeModifiers.intersection(disallowedModifiers).isEmpty else { return false }

        return keyCode == 53
    }
}

enum SessionTimelineScrollDirection: Equatable {
    case top
    case bottom
}

struct FocusedSessionTimelineKeyEvent {
    static func scrollDirection(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isTextInputActive: Bool
    ) -> SessionTimelineScrollDirection? {
        guard !isTextInputActive else { return nil }

        let activeModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard activeModifiers.intersection(disallowedModifiers).isEmpty else { return nil }

        switch keyCode {
        case 115:
            return .top
        case 119:
            return .bottom
        default:
            return nil
        }
    }
}
