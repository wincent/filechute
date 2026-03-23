import FilechuteCore
import SwiftUI

enum NavigationSection: Hashable {
  case store
  case allItems
  case trash

  var icon: String {
    switch self {
    case .store: "archivebox"
    case .allItems: "tray.full"
    case .trash: "trash"
    }
  }
}

struct SidebarView: View {
  var storeManager: StoreManager
  @Binding var selection: NavigationSection?
  var onRename: (String) -> Void = { _ in }

  @State private var isRenaming = false
  @State private var renameText = ""
  @State private var renameError: String?
  @FocusState private var isRenameFocused: Bool

  var body: some View {
    List(selection: $selection) {
      storeRow
      Label("All Items", systemImage: NavigationSection.allItems.icon)
        .tag(NavigationSection.allItems)
      Label("Trash", systemImage: NavigationSection.trash.icon)
        .badge(storeManager.deletedObjects.count)
        .tag(NavigationSection.trash)
    }
    .alert(
      "Rename Failed",
      isPresented: .init(
        get: { renameError != nil },
        set: { if !$0 { renameError = nil } }
      )
    ) {
      Button("OK") { renameError = nil }
    } message: {
      if let renameError {
        Text(renameError)
      }
    }
  }

  @ViewBuilder
  private var storeRow: some View {
    if isRenaming {
      TextField("Store Name", text: $renameText)
        .focused($isRenameFocused)
        .onSubmit { commitRename() }
        .onExitCommand { cancelRename() }
        .tag(NavigationSection.store)
    } else {
      Label(storeManager.storeName, systemImage: NavigationSection.store.icon)
        .tag(NavigationSection.store)
        .contextMenu {
          Button("Rename") {
            startRename()
          }
        }
    }
  }

  private func startRename() {
    renameText = storeManager.storeName
    isRenaming = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      isRenameFocused = true
    }
  }

  private func commitRename() {
    let name = renameText.trimmingCharacters(in: .whitespaces)
    isRenaming = false

    guard !name.isEmpty else { return }

    if name.contains("/") || name.contains(":") {
      renameError = "Store name cannot contain \"/\" or \":\"."
      return
    }

    if name.hasPrefix(".") {
      renameError = "Store name cannot start with \".\"."
      return
    }

    if name == storeManager.storeName {
      return
    }

    let newURL = storeManager.storeRoot.deletingLastPathComponent()
      .appendingPathComponent("\(name).filechute")
    if FileManager.default.fileExists(atPath: newURL.path) {
      renameError = "A store named \"\(name)\" already exists."
      return
    }

    onRename(name)
  }

  private func cancelRename() {
    isRenaming = false
  }
}
