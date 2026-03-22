import AppKit
import SwiftUI

struct SearchField: NSViewRepresentable {
  @Binding var text: String

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = "Search"
    field.sendsSearchStringImmediately = true
    field.usesSingleLineMode = true
    (field.cell as? NSSearchFieldCell)?.isScrollable = true
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ nsView: NSSearchField, context: Context) {
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func controlTextDidChange(_ obj: Notification) {
      if let field = obj.object as? NSSearchField {
        text.wrappedValue = field.stringValue
      }
    }
  }

  static func focus() {
    guard let window = NSApp.keyWindow else { return }

    if let toolbar = window.toolbar {
      for item in toolbar.items {
        if let view = item.view,
          let field = findSearchField(in: view)
        {
          field.selectText(nil)
          return
        }
      }
    }

    if let rootView = window.contentView?.superview,
      let field = findSearchField(in: rootView)
    {
      field.selectText(nil)
      return
    }

    if let contentView = window.contentView,
      let field = findSearchField(in: contentView)
    {
      field.selectText(nil)
    }
  }

  private static func findSearchField(in view: NSView) -> NSSearchField? {
    if let field = view as? NSSearchField { return field }
    for subview in view.subviews {
      if let found = findSearchField(in: subview) { return found }
    }
    return nil
  }
}
