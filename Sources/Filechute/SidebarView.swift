import FilechuteCore
import SwiftUI
import UniformTypeIdentifiers

private struct FolderInsertionPoint: Equatable {
  let parentId: Int64?
  let afterFolderId: Int64?
}

private enum FolderDropZone {
  case insertBefore
  case nestInside
  case insertAfter
}

private class OptionClickState {
  var stabilizing = false
}

enum NavigationSection: Hashable {
  case store
  case allItems
  case folder(Int64)
  case trash

  var icon: String {
    switch self {
    case .store: "archivebox"
    case .allItems: "tray.full"
    case .folder: "folder"
    case .trash: "trash"
    }
  }

  var folderId: Int64? {
    if case .folder(let id) = self { return id }
    return nil
  }
}

struct SidebarView: View {
  var storeManager: StoreManager
  @Binding var selection: NavigationSection?
  @Binding var expandedFolderIds: String
  var onRename: (String) -> Void = { _ in }
  @Environment(\.undoManager) private var undoManager

  @State private var isRenaming = false
  @State private var renameText = ""
  @State private var renameError: String?
  @FocusState private var isRenameFocused: Bool

  @State private var renamingFolderId: Int64?
  @State private var folderRenameText = ""
  @FocusState private var isFolderRenameFocused: Bool

  @State private var dropTargetFolderId: Int64?
  @State private var dropInsertionPoint: FolderInsertionPoint?
  @State private var hoverExpandTimer: Timer?
  @State private var folderRowHeight: CGFloat = 28
  @State private var hoveredFolderId: Int64?
  @State private var optionState = OptionClickState()

  private var expandedFolderIdSet: Set<Int64> {
    Set(
      expandedFolderIds
        .split(separator: ",")
        .compactMap { Int64($0) }
    )
  }

  private func setFolderExpanded(_ folderId: Int64, expanded: Bool) {
    var ids = expandedFolderIdSet
    if expanded {
      ids.insert(folderId)
    } else {
      ids.remove(folderId)
    }
    expandedFolderIds = ids.map(String.init).joined(separator: ",")
  }

  private var rootFolders: [Folder] {
    storeManager.folders.filter { $0.parentId == nil }.sorted { $0.position < $1.position }
  }

  private func childFolders(of parentId: Int64) -> [Folder] {
    storeManager.folders.filter { $0.parentId == parentId }.sorted { $0.position < $1.position }
  }

  var body: some View {
    List(selection: $selection) {
      storeRow
      Label("All Items", systemImage: NavigationSection.allItems.icon)
        .tag(NavigationSection.allItems)
        .accessibilityIdentifier("sidebar-all-items")

      Section {
        ForEach(Array(rootFolders.enumerated()), id: \.element.id) { index, folder in
          let prev = index > 0 ? rootFolders[index - 1].id : nil
          folderRow(folder, previousFolderId: prev)
        }
      } header: {
        HStack {
          Text("Folders")
          Spacer()
          Button {
            createRootFolder()
          } label: {
            Image(systemName: "plus.circle")
              .foregroundStyle(.secondary)
              .font(.system(size: 11))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("create-folder-button")
          .accessibilityLabel("Create folder")
        }
        .padding(.trailing, 14)
        .onDrop(of: [.filechuteFolderID], isTargeted: nil) { providers in
          handleFolderDropToRoot(providers)
        }
      }

      Label("Trash", systemImage: NavigationSection.trash.icon)
        .badge(storeManager.deletedObjects.count)
        .tag(NavigationSection.trash)
        .accessibilityIdentifier("sidebar-trash")
    }
    .animation(nil, value: storeManager.folders.map(\.id))
    .animation(nil, value: expandedFolderIds)
    .onChange(of: storeManager.folders) {
      dropInsertionPoint = nil
      dropTargetFolderId = nil
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

  private func folderRow(_ folder: Folder, previousFolderId: Int64? = nil) -> AnyView {
    let children = childFolders(of: folder.id)
    if children.isEmpty {
      return AnyView(folderLabel(folder, previousFolderId: previousFolderId))
    } else {
      let isExpanded = Binding(
        get: { expandedFolderIdSet.contains(folder.id) },
        set: { newValue in
          // NSOutlineView (backing SwiftUI List) intercepts option-clicks on
          // disclosure triangles and fires its own recursive expand/collapse,
          // which re-invokes this setter for each descendant. Those calls
          // conflict with our single-shot toggleRecursive update and undo it.
          // Block them briefly so our state change sticks.
          if optionState.stabilizing { return }
          if NSEvent.modifierFlags.contains(.option) {
            toggleRecursive(folder.id, expanded: newValue)
            optionState.stabilizing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
              optionState.stabilizing = false
            }
          } else {
            setFolderExpanded(folder.id, expanded: newValue)
          }
        }
      )
      return AnyView(
        DisclosureGroup(isExpanded: isExpanded) {
          ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
            let prev = index > 0 ? children[index - 1].id : nil
            folderRow(child, previousFolderId: prev)
          }
        } label: {
          folderLabel(folder, previousFolderId: previousFolderId)
        }
      )
    }
  }

  private func toggleRecursive(_ folderId: Int64, expanded: Bool) {
    var ids = expandedFolderIdSet
    let expandable = Folder.expandableFolderIds(under: folderId, in: storeManager.folders)
    if expanded {
      ids.formUnion(expandable)
    } else {
      ids.subtract(expandable)
    }
    expandedFolderIds = ids.map(String.init).joined(separator: ",")
  }

  @ViewBuilder
  private func folderLabel(_ folder: Folder, previousFolderId: Int64? = nil) -> some View {
    if renamingFolderId == folder.id {
      Label {
        TextField("Folder Name", text: $folderRenameText)
          .focused($isFolderRenameFocused)
          .onSubmit { commitFolderRename(folder.id) }
          .onExitCommand { cancelFolderRename() }
          .accessibilityIdentifier("folder-rename-field")
      } icon: {
        Image(systemName: "folder")
      }
      .tag(NavigationSection.folder(folder.id))
      .accessibilityIdentifier("folder-\(folder.id)")
    } else {
      let afterPoint = FolderInsertionPoint(
        parentId: folder.parentId, afterFolderId: folder.id
      )
      let beforePoint = FolderInsertionPoint(
        parentId: folder.parentId, afterFolderId: previousFolderId
      )
      let showAfterLine = dropInsertionPoint == afterPoint
      let isFirstSibling = previousFolderId == nil
      let showBeforeLine = isFirstSibling && dropInsertionPoint == beforePoint
      HStack(spacing: 4) {
        Label(folder.name, systemImage: NavigationSection.folder(folder.id).icon)
        Spacer()
        Button {
          createNestedFolder(in: folder.id)
        } label: {
          Image(systemName: "plus.circle")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .opacity(hoveredFolderId == folder.id ? 1 : 0)
        .accessibilityIdentifier("create-subfolder-\(folder.id)")
        .accessibilityLabel("Create subfolder")
      }
      .onHover { hovering in
        hoveredFolderId = hovering ? folder.id : nil
      }
      .tag(NavigationSection.folder(folder.id))
      .accessibilityIdentifier("folder-\(folder.id)")
      .background {
        GeometryReader { geo in
          Color.clear.onAppear { folderRowHeight = geo.size.height }
        }
      }
      .draggable(DraggedFolderID(id: folder.id))
      .overlay(alignment: .top) {
        if showBeforeLine {
          insertionLine
        }
      }
      .overlay(alignment: .bottom) {
        if showAfterLine {
          insertionLine
        }
      }
      .onDrop(
        of: [.fileURL, .filechuteObjectIDs, .filechuteFolderID, .data],
        delegate: FolderDropDelegate(
          folder: folder,
          previousFolderId: previousFolderId,
          storeManager: storeManager,
          dropTargetFolderId: $dropTargetFolderId,
          dropInsertionPoint: $dropInsertionPoint,
          hoverExpandTimer: $hoverExpandTimer,
          expandedFolderIdSet: expandedFolderIdSet,
          setFolderExpanded: setFolderExpanded,
          isDescendant: isDescendant,
          childFolders: childFolders,
          rootFolders: rootFolders,
          onItemsDrop: { ids, folderId in
            Task {
              for objectId in ids {
                try? await storeManager.addItemToFolder(
                  objectId: objectId, folderId: folderId
                )
              }
            }
          },
          onFileDrop: { url, folderId in
            Task { @MainActor in
              do {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(
                  atPath: url.path, isDirectory: &isDir
                )
                if exists && isDir.boolValue {
                  if url.pathExtension.lowercased() == "filechute" { return }
                  try await storeManager.ingestDirectory(at: url, intoFolder: folderId)
                } else {
                  let object = try await storeManager.ingestionService.ingest(fileAt: url)
                  try await storeManager.addItemToFolder(
                    objectId: object.id, folderId: folderId
                  )
                }
              } catch {
                Log.error(
                  "Failed to handle folder drop: \(error.localizedDescription)",
                  category: .folders
                )
              }
            }
          },
          rowHeight: folderRowHeight
        )
      )
      .listItemTint(dropTargetFolderId == folder.id ? .accentColor : nil)
      .contextMenu {
        Button("New Folder") {
          createNestedFolder(in: folder.id)
        }
        Button("Rename") {
          startFolderRename(folder)
        }
        if !childFolders(of: folder.id).isEmpty {
          Divider()
          Button("Expand All") {
            toggleRecursive(folder.id, expanded: true)
          }
          Button("Collapse All") {
            toggleRecursive(folder.id, expanded: false)
          }
        }
        Divider()
        Button("Delete Folder", role: .destructive) {
          deleteFolderWithUndo(folder.id)
        }
      }
    }
  }

  private var insertionLine: some View {
    HStack(spacing: 0) {
      Circle()
        .fill(Color.accentColor)
        .frame(width: 7, height: 7)
      Color.accentColor
        .frame(height: 2)
    }
    .padding(.leading, 2)
    .allowsHitTesting(false)
  }

  // MARK: - Drop to root

  private func handleFolderDropToRoot(_ providers: [NSItemProvider]) -> Bool {
    var didHandle = false
    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.filechuteFolderID.identifier) {
        didHandle = true
        _ = provider.loadTransferable(type: DraggedFolderID.self) { result in
          guard let dragged = try? result.get() else { return }
          Task { @MainActor in
            let maxPos = try await storeManager.database.maxFolderPosition(parentId: nil)
            try? await storeManager.moveFolder(
              dragged.id, parentId: nil, position: maxPos + 1.0
            )
          }
        }
      }
    }
    return didHandle
  }

  // MARK: - NSItemProvider helpers

  private func loadFolderID(
    from provider: NSItemProvider,
    then action: @escaping @MainActor (Int64) -> Void
  ) {
    provider.loadItem(forTypeIdentifier: UTType.filechuteFolderID.identifier, options: nil) {
      item, _ in
      guard let data = item as? Data,
        let dragged = try? JSONDecoder().decode(DraggedFolderID.self, from: data)
      else { return }
      Task { @MainActor in action(dragged.id) }
    }
  }

  private func isDescendant(_ candidateChild: Int64, of ancestorId: Int64) -> Bool {
    var visited: Set<Int64> = []
    var queue: [Int64] = [ancestorId]
    while !queue.isEmpty {
      let current = queue.removeFirst()
      guard !visited.contains(current) else { continue }
      visited.insert(current)
      for folder in storeManager.folders where folder.parentId == current {
        if folder.id == candidateChild { return true }
        queue.append(folder.id)
      }
    }
    return false
  }

  // MARK: - Folder operations

  private func createRootFolder() {
    Task {
      let folder = try await storeManager.createFolder(name: "New Folder")
      selection = .folder(folder.id)
      startFolderRename(folder)
    }
  }

  private func createNestedFolder(in parentId: Int64) {
    setFolderExpanded(parentId, expanded: true)
    Task {
      let folder = try await storeManager.createFolder(name: "New Folder", parentId: parentId)
      selection = .folder(folder.id)
      startFolderRename(folder)
    }
  }

  private func startFolderRename(_ folder: Folder) {
    folderRenameText = folder.name
    renamingFolderId = folder.id
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      isFolderRenameFocused = true
    }
  }

  private func commitFolderRename(_ folderId: Int64) {
    let name = folderRenameText.trimmingCharacters(in: .whitespaces)
    renamingFolderId = nil
    guard !name.isEmpty else { return }
    Task {
      try? await storeManager.renameFolder(folderId, to: name)
    }
  }

  private func cancelFolderRename() {
    renamingFolderId = nil
  }

  private func deleteFolderWithUndo(_ folderId: Int64) {
    Task {
      try? await storeManager.softDeleteFolder(folderId)
    }
    if case .folder(let selectedId) = selection, selectedId == folderId {
      selection = .allItems
    }
    guard let undoManager else { return }
    Self.registerFolderDeleteUndo(
      folderId: folderId,
      storeManager: storeManager,
      undoManager: undoManager
    )
  }

  private static func registerFolderDeleteUndo(
    folderId: Int64,
    storeManager: StoreManager,
    undoManager: UndoManager
  ) {
    undoManager.registerUndo(withTarget: storeManager) { [weak undoManager] manager in
      Task { @MainActor in
        try? await manager.restoreFolder(folderId)
        if let undoManager {
          registerFolderDeleteRedo(
            folderId: folderId, storeManager: manager, undoManager: undoManager
          )
        }
      }
    }
    undoManager.setActionName("Delete Folder")
  }

  private static func registerFolderDeleteRedo(
    folderId: Int64,
    storeManager: StoreManager,
    undoManager: UndoManager
  ) {
    undoManager.registerUndo(withTarget: storeManager) { [weak undoManager] manager in
      Task { @MainActor in
        try? await manager.softDeleteFolder(folderId)
        if let undoManager {
          registerFolderDeleteUndo(
            folderId: folderId, storeManager: manager, undoManager: undoManager
          )
        }
      }
    }
    undoManager.setActionName("Delete Folder")
  }

  // MARK: - Store rename

  @ViewBuilder
  private var storeRow: some View {
    if isRenaming {
      TextField("Store Name", text: $renameText)
        .focused($isRenameFocused)
        .onSubmit { commitRename() }
        .onExitCommand { cancelRename() }
        .tag(NavigationSection.store)
        .accessibilityIdentifier("store-rename-field")
    } else {
      Label(storeManager.storeName, systemImage: NavigationSection.store.icon)
        .tag(NavigationSection.store)
        .accessibilityIdentifier("sidebar-store")
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

// MARK: - FolderDropDelegate

private struct FolderDropDelegate: DropDelegate {
  let folder: Folder
  let previousFolderId: Int64?
  let storeManager: StoreManager
  @Binding var dropTargetFolderId: Int64?
  @Binding var dropInsertionPoint: FolderInsertionPoint?
  @Binding var hoverExpandTimer: Timer?
  let expandedFolderIdSet: Set<Int64>
  let setFolderExpanded: (Int64, Bool) -> Void
  let isDescendant: (Int64, Int64) -> Bool
  let childFolders: (Int64) -> [Folder]
  let rootFolders: [Folder]
  let onItemsDrop: ([Int64], Int64) -> Void
  let onFileDrop: (URL, Int64) -> Void
  let rowHeight: CGFloat

  private func zone(for location: CGPoint) -> FolderDropZone {
    let y = location.y
    let third = rowHeight / 3
    if y < third { return .insertBefore }
    if y > rowHeight - third { return .insertAfter }
    return .nestInside
  }

  func dropEntered(info: DropInfo) {
    dropTargetFolderId = folder.id
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    let isFolderDrag = info.hasItemsConforming(to: [.filechuteFolderID])
    let z = isFolderDrag ? zone(for: info.location) : .nestInside

    switch z {
    case .insertBefore:
      dropTargetFolderId = nil
      dropInsertionPoint = FolderInsertionPoint(
        parentId: folder.parentId, afterFolderId: previousFolderId
      )
      cancelHoverExpand()
    case .insertAfter:
      dropTargetFolderId = nil
      dropInsertionPoint = FolderInsertionPoint(
        parentId: folder.parentId, afterFolderId: folder.id
      )
      cancelHoverExpand()
    case .nestInside:
      dropTargetFolderId = folder.id
      dropInsertionPoint = nil
      startHoverExpandIfNeeded()
    }

    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    dropTargetFolderId = nil
    dropInsertionPoint = nil
    hoverExpandTimer?.invalidate()
    hoverExpandTimer = nil
  }

  func performDrop(info: DropInfo) -> Bool {
    let isFolderDrag = info.hasItemsConforming(to: [.filechuteFolderID])
    let z = isFolderDrag ? zone(for: info.location) : .nestInside
    dropTargetFolderId = nil
    dropInsertionPoint = nil
    hoverExpandTimer?.invalidate()
    hoverExpandTimer = nil

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      self.dropInsertionPoint = nil
      self.dropTargetFolderId = nil
    }

    let allProviders = info.itemProviders(for: [
      .filechuteFolderID, .filechuteObjectIDs, .fileURL, .data,
    ])
    switch z {
    case .insertBefore:
      let point = FolderInsertionPoint(parentId: folder.parentId, afterFolderId: previousFolderId)
      if handleInsertionDrop(allProviders, at: point) { return true }
      return handleNestDrop(allProviders)
    case .insertAfter:
      let point = FolderInsertionPoint(parentId: folder.parentId, afterFolderId: folder.id)
      if handleInsertionDrop(allProviders, at: point) { return true }
      return handleNestDrop(allProviders)
    case .nestInside:
      return handleNestDrop(allProviders)
    }
  }

  private func startHoverExpandIfNeeded() {
    guard !expandedFolderIdSet.contains(folder.id) else { return }
    let hasChildren = storeManager.folders.contains { $0.parentId == folder.id }
    guard hasChildren else { return }
    guard hoverExpandTimer == nil else { return }
    let folderId = folder.id
    hoverExpandTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { _ in
      Task { @MainActor in
        setFolderExpanded(folderId, true)
      }
    }
  }

  private func cancelHoverExpand() {
    hoverExpandTimer?.invalidate()
    hoverExpandTimer = nil
  }

  private func handleNestDrop(_ providers: [NSItemProvider]) -> Bool {
    let folderId = folder.id
    var handled = false

    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.filechuteObjectIDs.identifier) {
        handled = true
        _ = provider.loadTransferable(type: DraggedObjectIDs.self) { result in
          guard let dragged = try? result.get() else { return }
          Task { @MainActor in
            self.onItemsDrop(dragged.ids, folderId)
          }
        }
      } else if provider.hasItemConformingToTypeIdentifier(UTType.filechuteFolderID.identifier) {
        handled = true
        _ = provider.loadTransferable(type: DraggedFolderID.self) { result in
          guard let dragged = try? result.get() else { return }
          Task { @MainActor in
            guard dragged.id != folderId, !self.isDescendant(folderId, dragged.id) else { return }
            let maxPos = try await self.storeManager.database.maxFolderPosition(parentId: folderId)
            try? await self.storeManager.moveFolder(
              dragged.id, parentId: folderId, position: maxPos + 1.0
            )
          }
        }
      } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        handled = true
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
          guard let data = item as? Data,
            let url = URL(dataRepresentation: data, relativeTo: nil)
          else { return }
          Task { @MainActor in
            self.onFileDrop(url, folderId)
          }
        }
      }
    }

    return handled
  }

  private func handleInsertionDrop(
    _ providers: [NSItemProvider], at point: FolderInsertionPoint
  ) -> Bool {
    var handled = false
    for provider in providers {
      guard provider.hasItemConformingToTypeIdentifier(UTType.filechuteFolderID.identifier) else {
        continue
      }
      handled = true
      _ = provider.loadTransferable(type: DraggedFolderID.self) { result in
        guard let dragged = try? result.get() else { return }
        Task { @MainActor in
          guard dragged.id != point.afterFolderId else { return }
          if let parentId = point.parentId {
            guard dragged.id != parentId, !self.isDescendant(parentId, dragged.id) else { return }
          }
          let siblings: [Folder]
          if let parentId = point.parentId {
            siblings = self.childFolders(parentId)
          } else {
            siblings = self.rootFolders
          }
          let newPosition: Double
          if let afterId = point.afterFolderId,
            let afterIndex = siblings.firstIndex(where: { $0.id == afterId })
          {
            let afterPos = siblings[afterIndex].position
            let nextPos =
              afterIndex + 1 < siblings.count
              ? siblings[afterIndex + 1].position : afterPos + 2.0
            newPosition = (afterPos + nextPos) / 2.0
          } else {
            let firstPos = siblings.first?.position ?? 1.0
            newPosition = firstPos - 1.0
          }
          try? await self.storeManager.moveFolder(
            dragged.id, parentId: point.parentId, position: newPosition
          )
        }
      }
    }
    return handled
  }
}
