import AppKit
import FilechuteCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var storeManager: StoreManager
    @State private var selectedObjectId: Int64?
    @State private var showInspector = true
    @State private var showColumnBrowser = true
    @State private var filteredObjects: [StoredObject]?
    @State private var searchText = ""

    var selectedObject: StoredObject? {
        guard let id = selectedObjectId else { return nil }
        return displayedObjects.first { $0.id == id }
    }

    var displayedObjects: [StoredObject] {
        let base = filteredObjects ?? storeManager.objects
        if searchText.isEmpty {
            return base
        }
        let terms = searchText
            .lowercased()
            .split(separator: " ")
            .map(String.init)
        return base.filter { obj in
            terms.allSatisfy { term in
                obj.name.lowercased().contains(term)
            }
        }
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
                    DetailView(object: selectedObject, storeManager: storeManager)
                        .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
                } else {
                    Text("No selection")
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity)
                        .inspectorColumnWidth(min: 200, ideal: 280, max: 400)
                }
            }
            .searchable(text: $searchText, prompt: "Search by name")
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
                        showInspector.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .accessibilityLabel("Toggle inspector panel")
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
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
        Table(displayedObjects, selection: $selectedObjectId) {
            TableColumn("Name", value: \.name)
            TableColumn("Date Added") { obj in
                Text(obj.createdAt, format: .dateTime.month().day().year())
            }
            .width(min: 80, ideal: 120)
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            if let id = ids.first,
               let obj = storeManager.objects.first(where: { $0.id == id })
            {
                Button("Open") {
                    try? storeManager.openObject(obj)
                }
                Button("Reveal in Finder") {
                    try? storeManager.openObjectWith(obj)
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
        }
        .onKeyPress(.return) {
            if let selectedObject {
                try? storeManager.openObject(selectedObject)
                return .handled
            }
            return .ignored
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
