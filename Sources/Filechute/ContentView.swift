import AppKit
import FilechuteCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var storeManager: StoreManager
    @State private var selection: Set<Int64> = []
    @State private var showInspector = true
    @State private var showColumnBrowser = true
    @State private var filteredObjects: [StoredObject]?
    @State private var searchText = ""
    @State private var quickLookCoordinator = QuickLookCoordinator()
    @State private var sortOrder: [KeyPathComparator<StoredObject>] = [
        KeyPathComparator(\.name)
    ]
    @SceneStorage("tableColumnCustomization")
    private var columnCustomization: TableColumnCustomization<StoredObject>
    @State private var editingObjectId: Int64?
    @State private var editingName = ""
    @FocusState private var isEditingFocused: Bool
    @State private var showColumnSettings = false
    @State private var keyMonitor = KeyEventMonitor()

    var selectedObject: StoredObject? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return displayedObjects.first { $0.id == id }
    }

    var displayedObjects: [StoredObject] {
        var result = filteredObjects ?? storeManager.objects
        if !searchText.isEmpty {
            let terms = searchText
                .lowercased()
                .split(separator: " ")
                .map(String.init)
            result = result.filter { obj in
                let tagNames = storeManager.tagNamesByObject[obj.id] ?? []
                return terms.allSatisfy { term in
                    obj.name.lowercased().contains(term)
                        || tagNames.contains { $0.lowercased().contains(term) }
                }
            }
        }
        result.sort(using: sortOrder)
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showColumnBrowser && !storeManager.allTags.isEmpty {
                    ColumnBrowserView(
                        storeManager: storeManager,
                        filteredObjects: $filteredObjects
                    )
                    Divider()
                }

                if storeManager.objects.isEmpty {
                    emptyStateView
                } else if displayedObjects.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    tableView
                }
            }
            .inspector(isPresented: $showInspector) {
                if let selectedObject {
                    DetailView(object: selectedObject, storeManager: storeManager) {
                        activateQuickLook(for: selectedObject)
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
            .searchable(text: $searchText, prompt: "Search by name or tag")
            .navigationTitle("Filechute")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openFilePicker()
                    } label: {
                        Label("Add Files", systemImage: "plus")
                    }
                    .accessibilityLabel("Add files to the store")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showColumnBrowser.toggle()
                    } label: {
                        Label("Column Browser", systemImage: "rectangle.split.3x1")
                    }
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
                    .accessibilityLabel("Configure visible columns")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .accessibilityLabel("Toggle inspector panel")
                }
            }
        }
        .onAppear {
            setupKeyMonitor()
            keyMonitor.install()
        }
        .onDisappear {
            keyMonitor.uninstall()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func setupKeyMonitor() {
        keyMonitor.context = { [self] in
            InteractionContext(
                isEditing: editingObjectId != nil,
                hasSelection: !selection.isEmpty,
                isQuickLookVisible: quickLookCoordinator.isVisible
            )
        }
        keyMonitor.perform = { [self] effect in
            handleEffect(effect)
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
    }

    private var tableView: some View {
        Table(displayedObjects, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Name", value: \StoredObject.name) { obj in
                if editingObjectId == obj.id {
                    TextField("Name", text: $editingName)
                        .focused($isEditingFocused)
                        .onSubmit { commitRename(for: obj.id) }
                } else {
                    Text(obj.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .customizationID("name")

            TableColumn("Type", value: \StoredObject.fileExtension) { obj in
                Text(obj.fileTypeDisplay)
                    .foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 60, max: 80)
            .customizationID("type")

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
               let obj = displayedObjects.first(where: { $0.id == id })
            {
                Button("Open") {
                    Task { try? await storeManager.openObject(obj) }
                }
                Button("Reveal in Finder") {
                    Task { try? await storeManager.openObjectWith(obj) }
                }
                if ids.count == 1 {
                    Button("Rename") {
                        startRename(for: obj)
                    }
                }
                Divider()
            }
            if !ids.isEmpty {
                Button("Delete", role: .destructive) {
                    Task {
                        for id in ids {
                            try? await storeManager.deleteObject(id)
                        }
                    }
                }
            }
        } primaryAction: { ids in
            for id in ids {
                guard let obj = displayedObjects.first(where: { $0.id == id }) else { continue }
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

    private func openSelected() {
        for id in selection {
            guard let obj = displayedObjects.first(where: { $0.id == id }) else { continue }
            Task { try? await storeManager.openObject(obj) }
        }
    }

    private func startRename(for object: StoredObject) {
        editingName = object.name
        editingObjectId = object.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isEditingFocused = true
        }
    }

    private func commitRename(for objectId: Int64) {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        editingObjectId = nil
        guard !name.isEmpty else { return }
        Task {
            try? await storeManager.renameObject(objectId, to: name)
        }
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
        panel.canChooseDirectories = false
        panel.message = "Choose files to add to Filechute"
        if panel.runModal() == .OK {
            Task {
                try? await storeManager.ingest(urls: panel.urls)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var didHandle = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                didHandle = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil)
                    else { return }
                    Task { @MainActor in
                        try? await storeManager.ingest(urls: [url])
                    }
                }
            }
        }
        return didHandle
    }
}

struct ColumnSettingsView: View {
    @Binding var customization: TableColumnCustomization<StoredObject>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visible Columns")
                .font(.headline)
            Toggle("Type", isOn: visibilityBinding("type"))
            Toggle("Date Added", isOn: visibilityBinding("dateAdded"))
            Toggle("Last Modified", isOn: visibilityBinding("lastModified"))
            Toggle("Last Opened", isOn: visibilityBinding("lastOpened"))
        }
        .padding()
        .frame(width: 200)
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
