import Foundation
import Testing

@testable import FilechuteCore

@Suite("KeyEventMonitor")
@MainActor
struct KeyEventMonitorTests {
  @Test("Init creates monitor with default callbacks")
  func initDefaults() {
    let monitor = KeyEventMonitor()
    #expect(!monitor.isBulkTagEditorVisible())
    #expect(!monitor.isFolderSelected())

    let ctx = monitor.context()
    #expect(!ctx.isEditing)
    #expect(!ctx.hasSelection)
  }

  @Test("Closure properties can be set")
  func setClosures() {
    let monitor = KeyEventMonitor()

    var searchFocused = false
    monitor.onSearchFocus = { searchFocused = true }
    monitor.onSearchFocus()
    #expect(searchFocused)

    var dismissed = false
    monitor.onBulkTagDismiss = { dismissed = true }
    monitor.onBulkTagDismiss()
    #expect(dismissed)

    var folderDeleted = false
    monitor.onDeleteFolder = { folderDeleted = true }
    monitor.onDeleteFolder()
    #expect(folderDeleted)

    monitor.isBulkTagEditorVisible = { true }
    #expect(monitor.isBulkTagEditorVisible())

    monitor.isFolderSelected = { true }
    #expect(monitor.isFolderSelected())
  }

  @Test("Context closure provides custom context")
  func customContext() {
    let monitor = KeyEventMonitor()

    monitor.context = {
      InteractionContext(
        isEditing: true,
        hasSelection: true,
        isQuickLookVisible: true,
        isGridMode: true,
        gridColumnCount: 4
      )
    }

    let ctx = monitor.context()
    #expect(ctx.isEditing)
    #expect(ctx.hasSelection)
    #expect(ctx.isQuickLookVisible)
    #expect(ctx.isGridMode)
    #expect(ctx.gridColumnCount == 4)
  }

  @Test("Perform closure receives effects")
  func performReceivesEffect() {
    let monitor = KeyEventMonitor()

    var receivedEffect: InteractionEffect?
    monitor.perform = { effect in
      receivedEffect = effect
    }
    monitor.perform(.startRename)
    #expect(receivedEffect == .startRename)

    monitor.perform(.moveToTrash)
    #expect(receivedEffect == .moveToTrash)
  }

  @Test("Install and uninstall lifecycle")
  func installUninstall() {
    let monitor = KeyEventMonitor()

    // Should not crash
    monitor.install()
    // Installing twice should be safe (guard in install)
    monitor.install()

    monitor.uninstall()
    // Uninstalling twice should be safe
    monitor.uninstall()
  }
}
