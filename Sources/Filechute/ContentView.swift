import AppKit
import FilechuteCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  var storeManager: StoreManager
  var onRenameStore: (String) -> Void = { _ in }
  @State private var selection: Set<Int64> = []
  @State private var showInspector = true
  @State private var showColumnBrowser = true
  @State private var filteredObjects: [StoredObject]?
  @State private var searchText = ""
  @State private var searchResults: [StoredObject]?
  @State private var quickLookCoordinator = QuickLookCoordinator()
  @State private var sortOrder: [KeyPathComparator<StoredObject>] = [
    KeyPathComparator(\.name)
  ]
  @SceneStorage("tableColumnCustomization")
  private var columnCustomization: TableColumnCustomization<StoredObject>
  @State private var editingObjectId: Int64?
  @State private var editingName = ""
  @State private var showColumnSettings = false
  @State private var showBulkTagEditor = false
  @State private var keyMonitor = KeyEventMonitor()
  @SceneStorage("columnBrowserHeight") private var columnBrowserHeight: Double = 180
  @SceneStorage("viewMode") private var viewMode: String = "table"
  @State private var gridColumnCount = 4
  @SceneStorage("thumbnailSize") private var thumbnailSize: Double = 128
  @State private var sidebarSelection: NavigationSection? = .allItems
  @State private var folderObjects: [StoredObject]?
  @SceneStorage("expandedFolderIds") private var expandedFolderIds: String = ""
  @Environment(\.undoManager) private var undoManager

  var selectedObject: StoredObject? {
    guard selection.count == 1, let id = selection.first else { return nil }
    return displayedObjects.first { $0.id == id }
  }

  var displayedObjects: [StoredObject] {
    if let searchResults {
      return searchResults
    }
    var result = folderObjects ?? filteredObjects ?? storeManager.objects
    result.sort(using: sortOrder)
    return result
  }

  var body: some View {
    NavigationSplitView {
      SidebarView(
        storeManager: storeManager,
        selection: $sidebarSelection,
        expandedFolderIds: $expandedFolderIds,
        onRename: onRenameStore
      )
    } detail: {
      switch sidebarSelection {
      case .store, .allItems:
        allItemsView
          .navigationTitle("All Items")
      case .folder(let folderId):
        allItemsView
          .navigationTitle(storeManager.folders.first { $0.id == folderId }?.name ?? "Folder")
      case .trash:
        TrashView(storeManager: storeManager, showInspector: $showInspector)
      case nil:
        ContentUnavailableView("Select a section", systemImage: "sidebar.left")
      }
    }
    .onAppear {
      setupKeyMonitor()
      keyMonitor.install()
    }
    .onDisappear {
      keyMonitor.uninstall()
    }
    .onChange(of: sidebarSelection) { _, newSelection in
      selection = []
      loadFolderObjects(for: newSelection)
    }
    .onChange(of: storeManager.folders) { _, _ in
      loadFolderObjects(for: sidebarSelection)
    }
    .onChange(of: storeManager.objects) { _, _ in
      loadFolderObjects(for: sidebarSelection)
    }
    .onChange(of: searchText) { _, newValue in
      performSearch(query: newValue)
    }
    .focusedSceneValue(\.showBulkTagEditor, $showBulkTagEditor)
    .focusedSceneValue(\.thumbnailSize, $thumbnailSize)
    .focusedSceneValue(\.isGridMode, viewMode == "preview")
  }

  private var allItemsView: some View {
    let objects = displayedObjects
    return VStack(spacing: 0) {
      if showColumnBrowser {
        ColumnBrowserView(
          storeManager: storeManager,
          filteredObjects: $filteredObjects
        )
        .frame(height: columnBrowserHeight)

        ResizableDivider(height: $columnBrowserHeight, minHeight: 80, maxHeight: 400)
      }

      contentArea(objects: objects)

      if !storeManager.objects.isEmpty {
        StatusBarView(
          objects: objects,
          selection: selection,
          sizesByObject: storeManager.sizesByObject,
          isGridMode: viewMode == "preview",
          thumbnailSize: $thumbnailSize
        )
      }
    }
    .inspector(isPresented: $showInspector) {
      if selection.count == 1, let id = selection.first,
        let selected = objects.first(where: { $0.id == id })
      {
        DetailView(object: selected, storeManager: storeManager) {
          activateQuickLook(for: selected)
        }
        .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
      } else if selection.count > 1 {
        VStack {
          Image(systemName: "square.stack")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text("\(selection.count) items selected")
            .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
        .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
      } else {
        Text("No selection")
          .foregroundStyle(.secondary)
          .frame(maxHeight: .infinity)
          .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Picker("View Mode", selection: $viewMode) {
          Image(systemName: "list.bullet")
            .tag("table")
            .accessibilityLabel("Table view")
          Image(systemName: "square.grid.2x2")
            .tag("preview")
            .accessibilityLabel("Preview grid")
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .keyboardShortcut(viewMode == "table" ? "2" : "1", modifiers: .command)
        .accessibilityIdentifier("view-mode-picker")
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          openFilePicker()
        } label: {
          Label("Add Files", systemImage: "plus")
        }
        .accessibilityIdentifier("add-files-button")
        .accessibilityLabel("Add files to the store")
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          showColumnBrowser.toggle()
        } label: {
          Label("Column Browser", systemImage: "rectangle.split.3x1")
        }
        .accessibilityIdentifier("toggle-column-browser")
        .accessibilityLabel("Toggle column browser")
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          showColumnSettings.toggle()
        } label: {
          Label("Columns", systemImage: "tablecells")
        }
        .popover(isPresented: $showColumnSettings) {
          ColumnSettingsView(customization: $columnCustomization)
        }
        .accessibilityIdentifier("column-settings-button")
        .accessibilityLabel("Configure visible columns")
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          showInspector.toggle()
        } label: {
          Label("Inspector", systemImage: "sidebar.right")
        }
        .accessibilityIdentifier("toggle-inspector")
        .accessibilityLabel("Toggle inspector panel")
      }
      ToolbarItem(placement: .principal) {
        SearchField(text: $searchText)
          .frame(width: 300)
          .accessibilityIdentifier("search-field")
      }
    }
    .accessibilityIdentifier("objects-table")
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      handleDrop(providers)
    }
    .onChange(of: selection) { _, newSelection in
      guard viewMode == "preview", quickLookCoordinator.isVisible,
        newSelection.count == 1, let id = newSelection.first,
        let obj = displayedObjects.first(where: { $0.id == id })
      else { return }
      Task {
        if let url = try? await storeManager.temporaryCopyURL(for: obj) {
          quickLookCoordinator.updatePreview(for: url)
        }
      }
    }
    .overlay {
      if showBulkTagEditor {
        BulkTagEditView(
          selectedObjectIds: selection,
          storeManager: storeManager,
          onDismiss: { showBulkTagEditor = false }
        )
      }
    }
    .sheet(
      isPresented: Binding(
        get: { storeManager.ingestionProgress.isActive },
        set: { _ in }
      )
    ) {
      IngestionProgressView(progress: storeManager.ingestionProgress)
        .interactiveDismissDisabled()
    }
  }

  private func setupKeyMonitor() {
    keyMonitor.context = { [self] in
      InteractionContext(
        isEditing: editingObjectId != nil,
        hasSelection: !selection.isEmpty,
        isQuickLookVisible: quickLookCoordinator.isVisible,
        isGridMode: viewMode == "preview",
        gridColumnCount: gridColumnCount,
        isInTrash: sidebarSelection == .trash
      )
    }
    keyMonitor.perform = { [self] effect in
      handleEffect(effect)
    }
    keyMonitor.onBulkTagDismiss = { [self] in
      showBulkTagEditor = false
    }
    keyMonitor.isBulkTagEditorVisible = { [self] in
      showBulkTagEditor
    }
    keyMonitor.isFolderSelected = { [self] in
      if case .folder = sidebarSelection, selection.isEmpty { return true }
      return false
    }
    keyMonitor.onDeleteFolder = { [self] in
      if case .folder(let folderId) = sidebarSelection {
        deleteFolderWithUndo(folderId)
      }
    }
    keyMonitor.onSearchFocus = {
      SearchField.focus()
    }
  }

  private func handleEffect(_ effect: InteractionEffect) {
    switch effect {
    case .startRename:
      if let selectedObject { startRename(for: selectedObject) }
    case .cancelRename:
      cancelRename()
    case .toggleQuickLook:
      if let selectedObject { activateQuickLook(for: selectedObject) }
    case .navigateQuickLook(let direction):
      navigateQuickLook(direction: direction)
    case .openSelected:
      openSelected()
    case .moveToTrash:
      deleteWithUndo(selection)
    case .passthrough:
      break
    }
  }

  private var emptyStateView: some View {
    ContentUnavailableView {
      Label("No Files", systemImage: "doc")
    } description: {
      Text("Drop files here or click \(Image(systemName: "plus")) to get started.")
    }
    .accessibilityIdentifier("empty-state")
  }

  @ViewBuilder
  private func contentArea(objects: [StoredObject]) -> some View {
    if storeManager.objects.isEmpty {
      emptyStateView
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if objects.isEmpty {
      ContentUnavailableView.search(text: searchText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if viewMode == "preview" {
      PreviewGridView(
        storeManager: storeManager,
        objects: objects,
        selection: $selection,
        columnCount: $gridColumnCount,
        thumbnailSize: thumbnailSize,
        onOpen: { obj in
          Task { try? await storeManager.openObject(obj) }
        },
        onQuickLook: { obj in
          activateQuickLook(for: obj)
        },
        onRevealInFinder: { obj in
          Task { try? await storeManager.openObjectWith(obj) }
        },
        onDelete: { ids in
          deleteWithUndo(ids)
        },
        currentFolderId: sidebarSelection?.folderId,
        onRemoveFromFolder: sidebarSelection?.folderId != nil
          ? { objectId, folderId in
            Task {
              if let folder = try? await storeManager.directFolderForObject(
                objectId, inSubtreeOf: folderId
              ) {
                try? await storeManager.removeItemFromFolder(
                  objectId: objectId, folderId: folder.id
                )
                loadFolderObjects(for: sidebarSelection)
              }
            }
          } : nil,
        dragProvider: { ids in dragProvider(for: ids) }
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      tableView(for: objects)
        .id(sortOrder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func tableView(for objects: [StoredObject]) -> some View {
    Table(
      objects, selection: $selection, sortOrder: $sortOrder,
      columnCustomization: $columnCustomization
    ) {
      TableColumn("Name", value: \StoredObject.name) { obj in
        Text(obj.name)
          .frame(maxWidth: .infinity, alignment: .leading)
          .popover(
            isPresented: Binding(
              get: { editingObjectId == obj.id },
              set: { if !$0 { commitRename(for: obj.id) } }
            )
          ) {
            RenamePopover(
              name: $editingName,
              onCommit: { commitRename(for: obj.id) }
            )
          }
      }
      .customizationID("name")

      TableColumn("Type", value: \StoredObject.fileExtension) { obj in
        Text(obj.fileTypeDisplay)
          .foregroundStyle(.secondary)
      }
      .width(min: 60, ideal: 120, max: 180)
      .customizationID("type")

      TableColumn("Size", value: \StoredObject.sizeBytes) { obj in
        if obj.sizeBytes > 0 {
          Text(
            ByteCountFormatter.string(
              fromByteCount: Int64(obj.sizeBytes), countStyle: .file
            )
          )
          .foregroundStyle(.secondary)
        }
      }
      .width(min: 60, ideal: 90, max: 140)
      .customizationID("size")

      TableColumn("Date Added", value: \StoredObject.createdAt) { obj in
        Text(obj.createdAt, format: .dateTime.month().day().year().hour().minute())
      }
      .width(min: 100, ideal: 150)
      .customizationID("dateAdded")

      TableColumn("Last Modified", value: \StoredObject.effectiveModifiedAt) { obj in
        if let date = obj.modifiedAt {
          Text(date, format: .dateTime.month().day().year().hour().minute())
        }
      }
      .width(min: 100, ideal: 150)
      .customizationID("lastModified")

      TableColumn("Last Opened", value: \StoredObject.effectiveLastOpenedAt) { obj in
        if let date = obj.lastOpenedAt {
          Text(date, format: .dateTime.month().day().year().hour().minute())
        }
      }
      .width(min: 100, ideal: 150)
      .customizationID("lastOpened")
    }
    .contextMenu(forSelectionType: Int64.self) { ids in
      if let id = ids.first,
        let obj = objects.first(where: { $0.id == id })
      {
        Button("Open") {
          Task { try? await storeManager.openObject(obj) }
        }
        Button("Quick Look") {
          activateQuickLook(for: obj)
        }
        Button("Reveal in Finder") {
          Task { try? await storeManager.openObjectWith(obj) }
        }
        if ids.count == 1 {
          Button("Rename") {
            startRename(for: obj)
          }
        }
        if case .folder(let folderId) = sidebarSelection {
          Divider()
          removeFromFolderButton(objectIds: ids, rootFolderId: folderId)
        }
        Divider()
      }
      if !ids.isEmpty {
        if !storeManager.folders.isEmpty {
          addToFolderMenu(objectIds: ids)
        }
        Button("Move to Trash", role: .destructive) {
          deleteWithUndo(ids)
        }
      }
    } primaryAction: { ids in
      for id in ids {
        guard let obj = objects.first(where: { $0.id == id }) else { continue }
        Task { try? await storeManager.openObject(obj) }
      }
    }
    .onKeyPress(keys: [.downArrow], phases: .down) { keyPress in
      guard keyPress.modifiers.contains(.command) else { return .ignored }
      openSelected()
      return selection.isEmpty ? .ignored : .handled
    }
    .onKeyPress(.space) {
      if editingObjectId != nil { return .ignored }
      if let selectedObject {
        activateQuickLook(for: selectedObject)
        return .handled
      }
      return .ignored
    }
  }

  @State private var searchTask: Task<Void, Never>?

  private func performSearch(query: String) {
    searchTask?.cancel()
    guard !query.isEmpty else {
      searchResults = nil
      return
    }
    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      let results = try? await storeManager.search(query)
      guard !Task.isCancelled else { return }
      searchResults = results
    }
  }

  private func loadFolderObjects(for section: NavigationSection?) {
    guard case .folder(let folderId) = section else {
      folderObjects = nil
      return
    }
    Task {
      folderObjects = try? await storeManager.itemsInFolder(folderId, recursive: true)
    }
  }

  private func dragProvider(for objectIds: [Int64]) -> NSItemProvider {
    let payload = DraggedObjectIDs(ids: objectIds)
    guard let internalData = try? JSONEncoder().encode(payload) else {
      return NSItemProvider()
    }

    let provider = NSItemProvider(
      item: internalData as NSData,
      typeIdentifier: UTType.filechuteObjectIDs.identifier
    )

    if objectIds.count == 1, let id = objectIds.first,
      let obj = displayedObjects.first(where: { $0.id == id })
    {
      let contentType = UTType(filenameExtension: obj.fileExtension) ?? .data
      let nameWithExt =
        obj.fileExtension.isEmpty || obj.name.hasSuffix(".\(obj.fileExtension)")
        ? obj.name : "\(obj.name).\(obj.fileExtension)"
      let fileAccess = storeManager.fileAccessService
      let database = storeManager.database
      provider.registerFileRepresentation(
        forTypeIdentifier: contentType.identifier,
        fileOptions: [],
        visibility: .all
      ) { completion in
        Task.detached {
          do {
            let ext = try await database.getMetadata(objectId: obj.id, key: "extension")
            let url = try fileAccess.openTemporaryCopy(
              hash: obj.hash, name: obj.name, extension: ext
            )
            completion(url, false, nil)
          } catch {
            completion(nil, false, error)
          }
        }
        return nil
      }
      provider.suggestedName = nameWithExt
    }

    return provider
  }

  private func openSelected() {
    for id in selection {
      guard let obj = displayedObjects.first(where: { $0.id == id }) else { continue }
      Task { try? await storeManager.openObject(obj) }
    }
  }

  private func startRename(for object: StoredObject) {
    editingName = object.name
    editingObjectId = object.id
  }

  private func commitRename(for objectId: Int64) {
    guard editingObjectId == objectId else { return }
    let name = editingName.trimmingCharacters(in: .whitespaces)
    editingObjectId = nil
    guard !name.isEmpty else { return }
    Task {
      try? await storeManager.renameObject(objectId, to: name)
    }
    refocusTable()
  }

  private func cancelRename() {
    editingObjectId = nil
    refocusTable()
  }

  private func refocusTable() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      guard let window = NSApp.keyWindow,
        let contentView = window.contentView
      else { return }
      if let tableView = Self.findTableView(in: contentView) {
        window.makeFirstResponder(tableView)
      }
    }
  }

  private static func findTableView(in view: NSView) -> NSTableView? {
    if let table = view as? NSTableView { return table }
    for subview in view.subviews {
      if let found = findTableView(in: subview) { return found }
    }
    return nil
  }

  private func navigateQuickLook(direction: Int) {
    let objects = displayedObjects
    guard !objects.isEmpty else { return }

    let currentIndex: Int
    if let id = selection.first, let idx = objects.firstIndex(where: { $0.id == id }) {
      currentIndex = idx
    } else {
      currentIndex = 0
    }

    let newIndex = min(max(currentIndex + direction, 0), objects.count - 1)
    let newObject = objects[newIndex]
    selection = [newObject.id]

    Task {
      if let url = try? await storeManager.temporaryCopyURL(for: newObject) {
        quickLookCoordinator.updatePreview(for: url)
      }
    }
  }

  private func activateQuickLook(for object: StoredObject) {
    let objects = displayedObjects
    Task {
      var urls: [URL] = []
      var selectedURL: URL?
      for obj in objects {
        if let url = try? await storeManager.temporaryCopyURL(for: obj) {
          urls.append(url)
          if obj.id == object.id {
            selectedURL = url
          }
        }
      }
      if let selectedURL {
        quickLookCoordinator.toggle(url: selectedURL, allItems: urls)
      }
    }
  }

  private func openFilePicker() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.message = "Choose files or folders to add to Filechute"
    if panel.runModal() == .OK {
      Log.debug("File picker: \(panel.urls.count) items selected", category: .ui)
      Task {
        var files: [URL] = []
        for url in panel.urls {
          var isDir: ObjCBool = false
          if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
            isDir.boolValue,
            url.pathExtension.lowercased() != "filechute"
          {
            try? await storeManager.ingestDirectory(at: url)
          } else {
            files.append(url)
          }
        }
        if !files.isEmpty {
          try? await storeManager.ingest(urls: files)
        }
      }
    }
  }

  private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    Log.debug("Drop received: \(providers.count) items", category: .ui)
    var didHandle = false
    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        didHandle = true
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
          guard let data = item as? Data,
            let url = URL(dataRepresentation: data, relativeTo: nil)
          else { return }
          Task { @MainActor in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if exists && isDir.boolValue && url.pathExtension.lowercased() != "filechute" {
              try? await storeManager.ingestDirectory(at: url)
            } else {
              try? await storeManager.ingest(urls: [url])
            }
          }
        }
      }
    }
    return didHandle
  }

  @ViewBuilder
  private func removeFromFolderButton(objectIds: Set<Int64>, rootFolderId: Int64) -> some View {
    if objectIds.count == 1, let objectId = objectIds.first {
      let folderName =
        storeManager.folders.first { $0.id == rootFolderId }?.name ?? "Folder"
      Button("Remove from \"\(folderName)\"") {
        Task {
          if let folder = try? await storeManager.directFolderForObject(
            objectId, inSubtreeOf: rootFolderId
          ) {
            try? await storeManager.removeItemFromFolder(
              objectId: objectId, folderId: folder.id
            )
            loadFolderObjects(for: sidebarSelection)
          }
        }
      }
    } else {
      let folderName =
        storeManager.folders.first { $0.id == rootFolderId }?.name ?? "Folder"
      Button("Remove from \"\(folderName)\"") {
        Task {
          for objectId in objectIds {
            if let folder = try? await storeManager.directFolderForObject(
              objectId, inSubtreeOf: rootFolderId
            ) {
              try? await storeManager.removeItemFromFolder(
                objectId: objectId, folderId: folder.id
              )
            }
          }
          loadFolderObjects(for: sidebarSelection)
        }
      }
    }
  }

  @ViewBuilder
  private func addToFolderMenu(objectIds: Set<Int64>) -> some View {
    let roots = storeManager.folders.filter { $0.parentId == nil }.sorted {
      $0.position < $1.position
    }
    Menu("Add to Folder") {
      ForEach(roots) { folder in
        folderMenuItem(folder, objectIds: objectIds)
      }
    }
  }

  private func folderMenuItem(_ folder: Folder, objectIds: Set<Int64>) -> AnyView {
    let children = storeManager.folders.filter { $0.parentId == folder.id }.sorted {
      $0.position < $1.position
    }
    if children.isEmpty {
      return AnyView(
        Button(folder.name) {
          Task {
            for id in objectIds {
              try? await storeManager.addItemToFolder(objectId: id, folderId: folder.id)
            }
          }
        }
      )
    } else {
      return AnyView(
        Menu(folder.name) {
          Button("This Folder") {
            Task {
              for id in objectIds {
                try? await storeManager.addItemToFolder(objectId: id, folderId: folder.id)
              }
            }
          }
          Divider()
          ForEach(children) { child in
            folderMenuItem(child, objectIds: objectIds)
          }
        }
      )
    }
  }

  private func deleteFolderWithUndo(_ folderId: Int64) {
    Task {
      try? await storeManager.softDeleteFolder(folderId)
    }
    sidebarSelection = .allItems
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

  private func deleteWithUndo(_ ids: Set<Int64>) {
    Task {
      for id in ids {
        try? await storeManager.deleteObject(id)
      }
    }
    selection.subtract(ids)
    guard let undoManager else { return }
    Self.registerDeleteUndo(
      ids: ids,
      storeManager: storeManager,
      undoManager: undoManager
    )
  }

  private static func registerDeleteUndo(
    ids: Set<Int64>,
    storeManager: StoreManager,
    undoManager: UndoManager
  ) {
    undoManager.registerUndo(withTarget: storeManager) { [weak undoManager] manager in
      Task { @MainActor in
        for id in ids {
          try? await manager.restoreObject(id)
        }
        if let undoManager {
          registerDeleteRedo(ids: ids, storeManager: manager, undoManager: undoManager)
        }
      }
    }
    undoManager.setActionName("Delete")
  }

  private static func registerDeleteRedo(
    ids: Set<Int64>,
    storeManager: StoreManager,
    undoManager: UndoManager
  ) {
    undoManager.registerUndo(withTarget: storeManager) { [weak undoManager] manager in
      Task { @MainActor in
        for id in ids {
          try? await manager.deleteObject(id)
        }
        if let undoManager {
          registerDeleteUndo(ids: ids, storeManager: manager, undoManager: undoManager)
        }
      }
    }
    undoManager.setActionName("Delete")
  }
}

private struct RenamePopover: View {
  @Binding var name: String
  var onCommit: () -> Void
  @FocusState private var isFocused: Bool

  var body: some View {
    TextField("Name", text: $name)
      .focused($isFocused)
      .onSubmit { onCommit() }
      .frame(width: 200)
      .padding(8)
      .onAppear { isFocused = true }
      .accessibilityIdentifier("rename-field")
  }
}

struct ColumnSettingsView: View {
  @Binding var customization: TableColumnCustomization<StoredObject>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Visible Columns")
        .font(.headline)
      Toggle("Type", isOn: visibilityBinding("type"))
        .accessibilityIdentifier("column-toggle-type")
      Toggle("Size", isOn: visibilityBinding("size"))
        .accessibilityIdentifier("column-toggle-size")
      Toggle("Date Added", isOn: visibilityBinding("dateAdded"))
        .accessibilityIdentifier("column-toggle-date-added")
      Toggle("Last Modified", isOn: visibilityBinding("lastModified"))
        .accessibilityIdentifier("column-toggle-last-modified")
      Toggle("Last Opened", isOn: visibilityBinding("lastOpened"))
        .accessibilityIdentifier("column-toggle-last-opened")
    }
    .padding()
    .frame(width: 200)
    .accessibilityIdentifier("column-settings")
  }

  private func visibilityBinding(_ id: String) -> Binding<Bool> {
    Binding(
      get: { customization[visibility: id] != .hidden },
      set: { newValue in
        customization[visibility: id] = newValue ? .automatic : .hidden
      }
    )
  }
}

struct IngestionProgressView: View {
  var progress: IngestionProgress

  var body: some View {
    VStack(spacing: 16) {
      Text("Importing Files")
        .font(.headline)
      ProgressView(value: progress.fractionCompleted)
        .frame(width: 280)
        .accessibilityIdentifier("ingestion-progress-bar")
      Text("\(progress.processedFiles) of \(progress.totalFiles) files")
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("ingestion-progress-text")
      if !progress.currentFileName.isEmpty {
        Text(progress.currentFileName)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
          .frame(width: 280)
          .accessibilityIdentifier("ingestion-current-file")
      }
    }
    .padding(32)
    .accessibilityIdentifier("ingestion-progress")
  }
}
