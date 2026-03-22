import AppKit
import Quartz

@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  var items: [URL] = []
  private var panelController: QuickLookPanelController?

  var isVisible: Bool {
    QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
  }

  func toggle(url: URL, allItems: [URL]) {
    items = allItems

    let panel = QLPreviewPanel.shared()!
    if panel.isVisible {
      panel.orderOut(nil)
      return
    }

    ensurePanelController()
    panel.dataSource = self
    panel.delegate = self
    if let index = items.firstIndex(of: url) {
      panel.currentPreviewItemIndex = index
    }
    panel.makeKeyAndOrderFront(nil)
  }

  func updatePreview(for url: URL) {
    guard isVisible else { return }
    let panel = QLPreviewPanel.shared()!
    if let index = items.firstIndex(of: url) {
      panel.currentPreviewItemIndex = index
    } else {
      items.append(url)
      panel.reloadData()
      panel.currentPreviewItemIndex = items.count - 1
    }
  }

  private func ensurePanelController() {
    if panelController == nil {
      panelController = QuickLookPanelController(coordinator: self)
    }
    panelController?.installInKeyWindow()
  }

  // MARK: - QLPreviewPanelDataSource

  nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    MainActor.assumeIsolated { items.count }
  }

  nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (
    any QLPreviewItem
  )! {
    MainActor.assumeIsolated { items[index] as NSURL }
  }
}

@MainActor
final class QuickLookPanelController: NSResponder {
  let coordinator: QuickLookCoordinator

  init(coordinator: QuickLookCoordinator) {
    self.coordinator = coordinator
    super.init()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func installInKeyWindow() {
    guard let window = NSApp.keyWindow else { return }
    if window.nextResponder === self { return }
    let current = window.nextResponder
    window.nextResponder = self
    self.nextResponder = current
  }

  nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    true
  }

  nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated {
      panel.dataSource = coordinator
      panel.delegate = coordinator
    }
  }

  nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
  }
}
