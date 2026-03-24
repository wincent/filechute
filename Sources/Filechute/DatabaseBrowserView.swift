import FilechuteCore
import SwiftUI

struct DatabaseBrowserView: View {
  let coordinator = StoreCoordinator.shared
  @State private var selectedStoreURL: URL?
  @State private var selectedTable: String?
  @State private var tables: [String] = []
  @State private var columns: [String] = []
  @State private var rows: [[String?]] = []
  @State private var totalRowCount = 0
  @State private var isLoadingPage = false

  private let pageSize = 200

  private static let timestampColumns: Set<String> = [
    "created_at", "modified_at", "last_opened_at", "renamed_at", "deleted_at",
  ]

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .medium
    return f
  }()

  private var selectedStore: StoreManager? {
    guard let url = selectedStoreURL else { return nil }
    return coordinator.openStores[url]
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      if columns.isEmpty {
        emptyState
      } else {
        tableContent
        Divider()
        footer
      }
    }
    .frame(minWidth: 700, minHeight: 400)
    .onChange(of: selectedStoreURL) {
      loadTables()
    }
    .onChange(of: selectedTable) {
      loadTableData()
    }
    .onAppear {
      if selectedStoreURL == nil {
        selectedStoreURL =
          coordinator.openStores.keys
          .sorted(by: { $0.path < $1.path })
          .first
      }
    }
  }

  private var toolbar: some View {
    HStack {
      Picker("Store", selection: $selectedStoreURL) {
        Text("Select Store").tag(nil as URL?)
        Divider()
        ForEach(
          Array(coordinator.openStores.keys).sorted(by: { $0.path < $1.path }),
          id: \.self
        ) { url in
          Text(url.deletingPathExtension().lastPathComponent)
            .tag(url as URL?)
        }
      }
      .frame(width: 200)

      Picker("Table", selection: $selectedTable) {
        Text("Select Table").tag(nil as String?)
        Divider()
        ForEach(tables, id: \.self) { table in
          Text(table).tag(table as String?)
        }
      }
      .frame(width: 200)
      .disabled(tables.isEmpty)

      Spacer()
    }
    .padding(8)
  }

  private var emptyState: some View {
    ContentUnavailableView(
      coordinator.openStores.isEmpty ? "No Stores Open" : "No Table Selected",
      systemImage: "tablecells",
      description: Text(
        coordinator.openStores.isEmpty
          ? "Open a store window to inspect its database."
          : "Select a table from the toolbar."
      )
    )
  }

  private var tableContent: some View {
    ScrollView([.horizontal, .vertical]) {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
        Section {
          ForEach(rows.indices, id: \.self) { index in
            rowView(rows[index], index: index)
              .onAppear {
                if index >= rows.count - 20 {
                  loadNextPage()
                }
              }
          }
        } header: {
          headerView
        }
      }
    }
  }

  private var headerView: some View {
    HStack(spacing: 0) {
      ForEach(columns, id: \.self) { name in
        Text(name)
          .font(.caption.bold())
          .frame(width: 160, alignment: .leading)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
      }
    }
    .background(.bar)
  }

  private func rowView(_ row: [String?], index: Int) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(zip(columns.indices, row)), id: \.0) { colIdx, value in
        cellView(value: value, columnName: columns[colIdx])
          .frame(width: 160, alignment: .leading)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
      }
    }
    .background(
      index % 2 == 0
        ? Color.clear
        : Color(nsColor: .alternatingContentBackgroundColors[1])
    )
  }

  @ViewBuilder
  private func cellView(value: String?, columnName: String) -> some View {
    if let value {
      if Self.timestampColumns.contains(columnName), let timestamp = Int64(value) {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        Text(Self.dateFormatter.string(from: date))
          .font(.caption.monospaced())
          .lineLimit(1)
          .truncationMode(.tail)
          .textSelection(.enabled)
          .help(value)
      } else {
        Text(value)
          .font(.caption.monospaced())
          .lineLimit(1)
          .truncationMode(.tail)
          .textSelection(.enabled)
          .help(value)
      }
    } else {
      Text("NULL")
        .font(.caption.monospaced())
        .foregroundStyle(.tertiary)
        .italic()
    }
  }

  private var footer: some View {
    HStack {
      Text("Showing \(rows.count) of \(totalRowCount) rows")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
  }

  // MARK: - Data Loading

  private func loadTables() {
    selectedTable = nil
    tables = []
    columns = []
    rows = []
    totalRowCount = 0

    guard let store = selectedStore else { return }
    Task {
      do {
        tables = try await store.database.tableNames()
      } catch {
        Log.error("Failed to load tables: \(error)", category: .database)
      }
    }
  }

  private func loadTableData() {
    columns = []
    rows = []
    totalRowCount = 0

    guard let store = selectedStore, let table = selectedTable else { return }
    Task {
      do {
        columns = try await store.database.columnNames(table: table)
        totalRowCount = try await store.database.rowCount(table: table)
        rows = try await store.database.fetchRows(
          table: table, limit: pageSize, offset: 0
        )
      } catch {
        Log.error("Failed to load table data: \(error)", category: .database)
      }
    }
  }

  private func loadNextPage() {
    guard !isLoadingPage,
      rows.count < totalRowCount,
      let store = selectedStore,
      let table = selectedTable
    else { return }

    isLoadingPage = true
    Task {
      defer { isLoadingPage = false }
      do {
        let newRows = try await store.database.fetchRows(
          table: table, limit: pageSize, offset: rows.count
        )
        rows.append(contentsOf: newRows)
      } catch {
        Log.error("Failed to load page: \(error)", category: .database)
      }
    }
  }
}
