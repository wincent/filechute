import AppKit

@MainActor
public final class KeyEventMonitor {
  private var monitor: Any?
  public var context: () -> InteractionContext = { InteractionContext() }
  public var perform: (InteractionEffect) -> Void = { _ in }
  public var onBulkTagDismiss: () -> Void = {}
  public var isBulkTagEditorVisible: () -> Bool = { false }
  public var onDeleteFolder: () -> Void = {}
  public var isFolderSelected: () -> Bool = { false }
  public var onSearchFocus: () -> Void = {}

  public init() {}

  public func install() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }

      let bulkTagVisible = MainActor.assumeIsolated { self.isBulkTagEditorVisible() }
      if bulkTagVisible {
        if event.keyCode == 53 {
          MainActor.assumeIsolated {
            self.onBulkTagDismiss()
          }
          return nil
        }
        return event
      }

      if event.charactersIgnoringModifiers == "f"
        && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
      {
        MainActor.assumeIsolated {
          self.onSearchFocus()
        }
        return nil
      }

      if event.keyCode == 51 && event.modifierFlags.contains(.command) {
        let handled = MainActor.assumeIsolated {
          if self.isFolderSelected() {
            self.onDeleteFolder()
            return true
          }
          return false
        }
        if handled { return nil }
      }

      let keyCode = event.keyCode
      let modifiers = event.modifierFlags
      let shouldConsume = MainActor.assumeIsolated {
        self.handleKey(keyCode: keyCode, modifiers: modifiers)
      }
      return shouldConsume ? nil : event
    }
  }

  public func uninstall() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
  }

  private func handleKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
    let input: KeyInput? =
      switch keyCode {
      case 36: .returnKey
      case 53: .escape
      case 123: .leftArrow
      case 124: .rightArrow
      case 51:
        modifiers.contains(.command) ? .commandBackspace : nil
      case 125:
        modifiers.contains(.command) ? .commandDown : .downArrow
      case 126: .upArrow
      default: nil
      }

    guard let input else { return false }

    var ctx = context()
    if keyCode == 36 || keyCode == 53 || keyCode == 125 || keyCode == 126 {
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
