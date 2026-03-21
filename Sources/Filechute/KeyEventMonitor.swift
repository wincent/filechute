import AppKit

@MainActor
final class KeyEventMonitor {
    private var monitor: Any?
    var isEditing: Bool = false
    var onStartRename: (() -> Void)?
    var onCancelRename: (() -> Void)?
    var isQuickLookVisible: (() -> Bool)?
    var onQuickLookNavigate: ((_ direction: Int) -> Void)?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let keyCode = event.keyCode
            let shouldConsume = MainActor.assumeIsolated {
                self.shouldConsume(keyCode: keyCode)
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

    private func shouldConsume(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36: // Return
            if isEditing { return false }
            if isTextFieldFocused() { return false }
            if let onStartRename {
                onStartRename()
                return true
            }
            return false

        case 53: // Escape
            if isEditing {
                onCancelRename?()
                return true
            }
            return false

        case 125: // Down arrow
            if isQuickLookVisible?() == true {
                onQuickLookNavigate?(1)
                return true
            }
            return false

        case 126: // Up arrow
            if isQuickLookVisible?() == true {
                onQuickLookNavigate?(-1)
                return true
            }
            return false

        default:
            return false
        }
    }

    private func isTextFieldFocused() -> Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        return firstResponder is NSTextView
    }
}
