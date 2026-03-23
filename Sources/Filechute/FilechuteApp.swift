import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let filechuteObjectIDs = UTType(
    exportedAs: "dev.wincent.filechute.object-ids"
  )
  static let filechuteFolderID = UTType(
    exportedAs: "dev.wincent.filechute.folder-id"
  )
}

struct DraggedObjectIDs: Codable, Transferable {
  let ids: [Int64]

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .filechuteObjectIDs)
  }
}

struct DraggedFolderID: Codable, Transferable {
  let id: Int64

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .filechuteFolderID)
  }
}

@main
struct FilechuteApp: App {
  @NSApplicationDelegateAdaptor(FilechuteAppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup(for: URL.self) { $url in
      RootView(requestedURL: url)
    }
    .commands {
      CommandGroup(replacing: .textEditing) {}
      FileMenuCommands()
      FilechuteCommands()
    }

    Window("Log", id: "log") {
      LogWindowView()
    }
  }
}

extension Notification.Name {
  static let openFilechuteStore = Notification.Name("openFilechuteStore")
}

final class FilechuteAppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.pathExtension == "filechute" {
      StoreCoordinator.shared.addRecentStore(url)
      NotificationCenter.default.post(
        name: .openFilechuteStore, object: nil, userInfo: ["url": url]
      )
    }
  }
}

struct FocusedStoreURLKey: FocusedValueKey {
  typealias Value = URL
}

struct FocusedNewStoreSheetKey: FocusedValueKey {
  typealias Value = Binding<Bool>
}

extension FocusedValues {
  var storeURL: URL? {
    get { self[FocusedStoreURLKey.self] }
    set { self[FocusedStoreURLKey.self] = newValue }
  }

  var showNewStoreSheet: Binding<Bool>? {
    get { self[FocusedNewStoreSheetKey.self] }
    set { self[FocusedNewStoreSheetKey.self] = newValue }
  }
}

struct FileMenuCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  @FocusedValue(\.storeURL) var currentStoreURL
  @FocusedValue(\.showNewStoreSheet) var showNewStoreSheet

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("New Window") {
        openWindow(value: currentStoreURL ?? StoreCoordinator.shared.defaultStoreURL)
      }
      .keyboardShortcut("n", modifiers: .command)

      Button("New Store...") {
        showNewStoreSheet?.wrappedValue = true
      }
      .keyboardShortcut("n", modifiers: [.command, .shift])

      Divider()

      Button("Open Store...") {
        openStorePanel()
      }
      .keyboardShortcut("o", modifiers: .command)

      Menu("Open Recent") {
        let coordinator = StoreCoordinator.shared
        ForEach(coordinator.recentStores, id: \.self) { url in
          Button(url.deletingPathExtension().lastPathComponent) {
            coordinator.addRecentStore(url)
            openWindow(value: url)
          }
        }
        if !coordinator.recentStores.isEmpty {
          Divider()
          Button("Clear Menu") {
            coordinator.clearRecentStores()
          }
        }
      }
    }
  }

  private func openStorePanel() {
    let panel = NSOpenPanel()
    panel.directoryURL = StoreCoordinator.shared.storesDirectory
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.treatsFilePackagesAsDirectories = false
    panel.message = "Choose a Filechute store to open"

    if let storeType = UTType("dev.wincent.filechute.store") {
      panel.allowedContentTypes = [storeType]
    }

    guard panel.runModal() == .OK, let url = panel.url else { return }
    StoreCoordinator.shared.addRecentStore(url)
    openWindow(value: url)
  }
}

struct FilechuteCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Debug") {
      Button("Show Log") {
        openWindow(id: "log")
      }
      .keyboardShortcut("L", modifiers: [.command, .option])
    }
  }
}

struct RootView: View {
  let requestedURL: URL?
  @Environment(\.openWindow) private var openWindow
  @State private var storeManager: StoreManager?
  @State private var currentStoreURL: URL?
  @State private var loadError: String?
  @State private var showNewStoreSheet = false

  private var storeURL: URL {
    currentStoreURL ?? requestedURL ?? StoreCoordinator.shared.lastActiveStoreURL
  }

  var body: some View {
    Group {
      if let storeManager {
        ContentView(storeManager: storeManager, onRenameStore: renameStore)
      } else if let loadError {
        ContentUnavailableView(
          "Failed to Load",
          systemImage: "exclamationmark.triangle",
          description: Text(loadError)
        )
      } else {
        ProgressView("Initializing...")
      }
    }
    .frame(minWidth: 600, minHeight: 400)
    .focusedSceneValue(\.storeURL, storeURL)
    .focusedSceneValue(\.showNewStoreSheet, $showNewStoreSheet)
    .sheet(isPresented: $showNewStoreSheet) {
      NewStoreSheet()
    }
    .onReceive(NotificationCenter.default.publisher(for: .openFilechuteStore)) { note in
      if let url = note.userInfo?["url"] as? URL {
        openWindow(value: url)
      }
    }
    .task(id: storeURL) {
      guard storeManager == nil || storeManager?.storeRoot != storeURL else { return }
      do {
        let manager = try StoreManager(storeRoot: storeURL)
        try await manager.refresh()
        self.storeManager = manager
        StoreCoordinator.shared.addRecentStore(storeURL)
        StoreCoordinator.shared.setLastActiveStore(storeURL)
        Task.detached(priority: .background) {
          await manager.backfillThumbnails()
        }
      } catch {
        self.loadError = error.localizedDescription
      }
    }
  }

  private func renameStore(_ newName: String) {
    guard let storeManager else { return }
    do {
      let newURL = try StoreCoordinator.shared.renameStore(
        from: storeManager.storeRoot, to: newName
      )
      self.storeManager = nil
      self.currentStoreURL = newURL
    } catch {
      self.loadError = error.localizedDescription
    }
  }
}
