import AppKit
import FilechuteCore

@MainActor
final class KeyEventMonitor {
    private var monitor: Any?
    var context: () -> InteractionContext = { InteractionContext() }
    var perform: (InteractionEffect) -> Void = { _ in }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.charactersIgnoringModifiers == "f"
                && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            {
                MainActor.assumeIsolated {
                    SearchField.focus()
                }
                return nil
            }

            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            let shouldConsume = MainActor.assumeIsolated {
                self.handleKey(keyCode: keyCode, modifiers: modifiers)
            }
            return shouldConsume ? nil : event
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let input: KeyInput? = switch keyCode {
        case 36: .returnKey
        case 53: .escape
        case 125:
            modifiers.contains(.command) ? .commandDown : .downArrow
        case 126: .upArrow
        default: nil
        }

        guard let input else { return false }

        var ctx = context()
        if keyCode == 36 || keyCode == 53 {
            ctx.isTextFieldFocused = isTextFieldFocused()
        }

        let effect = TableInteraction.reduce(key: input, context: ctx)
        if effect == .passthrough { return false }

        perform(effect)
        return true
    }

    private func isTextFieldFocused() -> Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        return firstResponder is NSTextView
    }

}
