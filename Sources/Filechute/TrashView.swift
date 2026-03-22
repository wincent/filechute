import FilechuteCore
import SwiftUI

struct TrashView: View {
  var storeManager: StoreManager
  @Binding var showInspector: Bool
  @State private var selection: Set<Int64> = []
  @State private var searchText = ""
  @State private var sortOrder: [KeyPathComparator<StoredObject>] = [
    KeyPathComparator(\.effectiveDeletedAt, order: .reverse)
  ]
  @State private var showEmptyTrashConfirmation = false

  var selectedObject: StoredObject? {
    guard selection.count == 1, let id = selection.first else { return nil }
    return displayedObjects.first { $0.id == id }
  }

  var displayedObjects: [StoredObject] {
    var result = storeManager.deletedObjects
    if !searchText.isEmpty {
      let terms = searchText.lowercased().split(separator: " ").map(String.init)
      result = result.filter { obj in
        terms.allSatisfy { term in
          obj.name.lowercased().contains(term)
        }
      }
    }
    result.sort(using: sortOrder)
    return result
  }

  var body: some View {
    Group {
      if storeManager.deletedObjects.isEmpty {
        ContentUnavailableView {
          Label("Trash is Empty", systemImage: "trash")
        } description: {
          Text("Deleted items will appear here.")
        }
      } else if displayedObjects.isEmpty {
        ContentUnavailableView.search(text: searchText)
      } else {
        VStack(spacing: 0) {
          tableView
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          StatusBarView(
            objects: displayedObjects,
            selection: selection,
            sizesByObject: storeManager.sizesByObject,
            isGridMode: false,
            thumbnailSize: .constant(128)
          )
        }
      }
    }
    .inspector(isPresented: $showInspector) {
      if let selectedObject {
        Form {
          Section("Details") {
            LabeledContent("Name", value: selectedObject.name)
            LabeledContent("Type", value: selectedObject.fileTypeDisplay)
            if selectedObject.sizeBytes > 0 {
              LabeledContent(
                "Size",
                value: ByteCountFormatter.string(
                  fromByteCount: Int64(selectedObject.sizeBytes),
                  countStyle: .file
                )
              )
            }
            if let date = selectedObject.deletedAt {
              LabeledContent("Deleted") {
                Text(date, format: .dateTime.month().day().year().hour().minute())
              }
            }
          }
        }
        .formStyle(.grouped)
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
    .navigationTitle("Trash")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          showEmptyTrashConfirmation = true
        } label: {
          Label("Delete Permanently", systemImage: "trash.slash")
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .help("Permanently delete selected items")
        .disabled(selection.isEmpty)
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          showInspector.toggle()
        } label: {
          Label("Inspector", systemImage: "sidebar.right")
        }
        .accessibilityLabel("Toggle inspector panel")
      }
      ToolbarItem(placement: .principal) {
        SearchField(text: $searchText)
          .frame(width: 300)
      }
    }
    .confirmationDialog(
      selection.count == 1
        ? "Permanently delete this item?"
        : "Permanently delete \(selection.count) items?",
      isPresented: $showEmptyTrashConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete Permanently", role: .destructive) {
        let ids = selection
        selection = []
        Task {
          for id in ids {
            try? await storeManager.permanentlyDelete(id)
          }
        }
      }
    } message: {
      Text("This action cannot be undone.")
    }
  }

  private var tableView: some View {
    Table(displayedObjects, selection: $selection, sortOrder: $sortOrder) {
      TableColumn("Name", value: \.name) { obj in
        Text(obj.name)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      TableColumn("Type", value: \.fileExtension) { obj in
        Text(obj.fileTypeDisplay)
          .foregroundStyle(.secondary)
      }
      .width(min: 60, ideal: 120, max: 180)

      TableColumn("Size", value: \.sizeBytes) { obj in
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

      TableColumn("Deleted", value: \.effectiveDeletedAt) { obj in
        if let date = obj.deletedAt {
          Text(date, format: .dateTime.month().day().year().hour().minute())
        }
      }
      .width(min: 100, ideal: 150)
    }
    .contextMenu(forSelectionType: Int64.self) { ids in
      if !ids.isEmpty {
        Button("Restore") {
          selection.subtract(ids)
          Task {
            for id in ids {
              try? await storeManager.restoreObject(id)
            }
          }
        }
        Button("Delete Permanently", role: .destructive) {
          selection.subtract(ids)
          Task {
            for id in ids {
              try? await storeManager.permanentlyDelete(id)
            }
          }
        }
      }
    }
  }
}
