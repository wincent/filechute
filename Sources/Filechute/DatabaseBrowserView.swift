import AppKit
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
  @State private var sortColumn: String?
  @State private var sortAscending = true
  @Environment(\.openWindow) private var openWindow

  private let pageSize = 200

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
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        DatabaseTableView(
          columns: columns,
          rows: rows,
          onLoadMore: loadNextPage,
          onSort: handleSort
        )
        Divider()
        footer
      }
    }
    .frame(minWidth: 700, minHeight: 400)
    .onChange(of: selectedStoreURL) {
      loadTables()
      syncTableInfoState()
    }
    .onChange(of: selectedTable) {
      loadTableData()
      syncTableInfoState()
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
      .accessibilityIdentifier("db-store-picker")

      Picker("Table", selection: $selectedTable) {
        Text("Select Table").tag(nil as String?)
        Divider()
        ForEach(tables, id: \.self) { table in
          Text(table).tag(table as String?)
        }
      }
      .frame(width: 200)
      .disabled(tables.isEmpty)
      .accessibilityIdentifier("db-table-picker")

      Button {
        openWindow(id: "table-info")
      } label: {
        Image(systemName: "info.circle")
      }
      .accessibilityIdentifier("db-table-info-button")
      .accessibilityLabel("Table Info")

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

  private func syncTableInfoState() {
    let state = TableInfoState.shared
    state.database = selectedStore?.database
    state.tableName = selectedTable
  }

  // MARK: - Data Loading

  private func loadTables() {
    selectedTable = nil
    tables = []
    columns = []
    rows = []
    totalRowCount = 0
    sortColumn = nil
    sortAscending = true

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
    sortColumn = nil
    sortAscending = true

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
          table: table, limit: pageSize, offset: rows.count,
          orderBy: sortColumn, ascending: sortAscending
        )
        rows.append(contentsOf: newRows)
      } catch {
        Log.error("Failed to load page: \(error)", category: .database)
      }
    }
  }

  private func handleSort(column: String, ascending: Bool) {
    sortColumn = column
    sortAscending = ascending
    rows = []

    guard let store = selectedStore, let table = selectedTable else { return }
    Task {
      do {
        totalRowCount = try await store.database.rowCount(table: table)
        rows = try await store.database.fetchRows(
          table: table, limit: pageSize, offset: 0,
          orderBy: column, ascending: ascending
        )
      } catch {
        Log.error("Failed to sort: \(error)", category: .database)
      }
    }
  }
}

// MARK: - NSTableView Wrapper

private struct DatabaseTableView: NSViewRepresentable {
  let columns: [String]
  let rows: [[String?]]
  let onLoadMore: () -> Void
  let onSort: (String, Bool) -> Void

  static let timestampColumns: Set<String> = [
    "created_at", "modified_at", "last_opened_at", "renamed_at", "deleted_at",
  ]

  static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .medium
    return f
  }()

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true

    let tableView = NSTableView()
    tableView.style = .plain
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.allowsColumnReordering = true
    tableView.allowsColumnResizing = true
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.dataSource = context.coordinator
    tableView.delegate = context.coordinator

    scrollView.documentView = tableView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let tableView = scrollView.documentView as? NSTableView else { return }
    let coordinator = context.coordinator
    coordinator.parent = self

    let columnsChanged = coordinator.columns != columns

    if columnsChanged {
      tableView.sortDescriptors = []
      for col in tableView.tableColumns.reversed() {
        tableView.removeTableColumn(col)
      }
      for name in columns {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
        col.title = name
        col.minWidth = 60
        col.width = 140
        col.sortDescriptorPrototype = NSSortDescriptor(key: name, ascending: true)
        tableView.addTableColumn(col)
      }
      coordinator.columns = columns
      coordinator.rows = rows
      tableView.reloadData()
    } else {
      let oldCount = coordinator.rows.count
      coordinator.rows = rows
      if rows.count > oldCount && oldCount > 0 {
        tableView.insertRows(
          at: IndexSet(integersIn: oldCount..<rows.count),
          withAnimation: []
        )
      } else if rows.count != oldCount {
        tableView.reloadData()
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: DatabaseTableView
    var columns: [String] = []
    var rows: [[String?]] = []

    init(_ parent: DatabaseTableView) {
      self.parent = parent
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
      rows.count
    }

    func tableView(
      _ tableView: NSTableView,
      viewFor tableColumn: NSTableColumn?,
      row: Int
    ) -> NSView? {
      guard let tableColumn,
        let colIdx = columns.firstIndex(of: tableColumn.identifier.rawValue),
        row < rows.count
      else { return nil }

      let cellId = NSUserInterfaceItemIdentifier("DataCell")
      let textField: NSTextField
      if let existing = tableView.makeView(
        withIdentifier: cellId, owner: nil
      ) as? NSTextField {
        textField = existing
      } else {
        textField = NSTextField()
        textField.identifier = cellId
        textField.isEditable = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.font = .monospacedSystemFont(
          ofSize: NSFont.smallSystemFontSize, weight: .regular
        )
        textField.lineBreakMode = .byTruncatingTail
      }

      let value = rows[row][colIdx]
      if let value {
        let colName = tableColumn.identifier.rawValue
        if DatabaseTableView.timestampColumns.contains(colName),
          let timestamp = Int64(value)
        {
          let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
          textField.stringValue = DatabaseTableView.dateFormatter.string(from: date)
          textField.toolTip = value
        } else {
          textField.stringValue = value
          textField.toolTip = value
        }
        textField.textColor = .labelColor
      } else {
        textField.stringValue = "NULL"
        textField.textColor = .tertiaryLabelColor
        textField.toolTip = nil
      }

      if row >= rows.count - 20 {
        DispatchQueue.main.async { [parent] in
          parent.onLoadMore()
        }
      }

      return textField
    }

    func tableView(
      _ tableView: NSTableView,
      sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
      guard let sort = tableView.sortDescriptors.first,
        let key = sort.key
      else { return }
      parent.onSort(key, sort.ascending)
    }
  }
}
