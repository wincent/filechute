import FilechuteCore
import SwiftUI

struct ColumnBrowserView: View {
  var storeManager: StoreManager
  @Binding var filteredObjects: [StoredObject]?
  @State private var columns: [BrowserColumn] = []
  @State private var columnWidths: [Int: CGFloat] = [:]
  @FocusState private var focusedColumn: Int?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: true) {
      ScrollViewReader { proxy in
        HStack(alignment: .top, spacing: 0) {
          BrowserColumnView(
            title: "Tags",
            items: storeManager.allTags,
            selection: columns.isEmpty ? nil : columns[0].selectedTagIds,
            columnIndex: 0,
            focusedColumn: $focusedColumn,
            columnCount: visibleColumnCount,
            width: columnWidths[0] ?? 180,
            onSelect: { tagIds in
              selectTags(tagIds, atLevel: 0)
            }
          )
          .id(0)
          .accessibilityIdentifier("browser-column-0")
          .accessibilityLabel("All tags")

          ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
            if !column.reachableTags.isEmpty {
              ColumnDivider(
                width: columnWidthBinding(index),
                minWidth: 100,
                maxWidth: 400,
                onResizeAll: setAllColumnWidths
              )
              BrowserColumnView(
                title: "Refine",
                items: column.reachableTags,
                selection: nextSelection(after: index),
                columnIndex: index + 1,
                focusedColumn: $focusedColumn,
                columnCount: visibleColumnCount,
                width: columnWidths[index + 1] ?? 180,
                onSelect: { tagIds in
                  selectTags(tagIds, atLevel: index + 1)
                }
              )
              .id(index + 1)
              .accessibilityIdentifier("browser-column-\(index + 1)")
              .accessibilityLabel("Refinement column \(index + 1)")
            }
          }
        }
        .onChange(of: focusedColumn) { _, newValue in
          if let column = newValue {
            withAnimation {
              proxy.scrollTo(column)
            }
          }
        }
      }
    }
    .frame(maxHeight: .infinity)
    .background(.background)
    .task {
      try? await storeManager.refresh()
    }
  }

  private func nextSelection(after index: Int) -> Set<Int64>? {
    let nextIndex = index + 1
    guard nextIndex < columns.count else { return nil }
    return columns[nextIndex].selectedTagIds
  }

  private func selectTags(_ tagIds: Set<Int64>, atLevel level: Int) {
    if level == 0 {
      columns.removeAll()
    } else if level < columns.count {
      columns.removeSubrange(level...)
    }

    guard !tagIds.isEmpty else {
      filteredObjects = nil
      return
    }

    let allSelectedTagIds = accumulatedTagIds(through: level - 1).union(tagIds)
    let newColumn = BrowserColumn(selectedTagIds: tagIds, reachableTags: [])
    columns.append(newColumn)

    Task {
      let tagIdArray = Array(allSelectedTagIds)
      let reachable = try? await storeManager.database.reachableTags(from: tagIdArray)
      let objects = try? await storeManager.database.objects(withAllTagIds: tagIdArray)

      if level < columns.count {
        columns[level].reachableTags = reachable ?? []
      }
      filteredObjects = objects
    }
  }

  private func accumulatedTagIds(through level: Int) -> Set<Int64> {
    var ids = Set<Int64>()
    for i in 0...max(0, level) {
      guard i < columns.count else { break }
      ids.formUnion(columns[i].selectedTagIds)
    }
    return ids
  }

  private var visibleColumnCount: Int {
    1 + columns.filter { !$0.reachableTags.isEmpty }.count
  }

  private func setAllColumnWidths(_ width: CGFloat) {
    for i in 0..<visibleColumnCount {
      columnWidths[i] = width
    }
  }

  private func columnWidthBinding(_ index: Int) -> Binding<CGFloat> {
    Binding(
      get: { columnWidths[index] ?? 180 },
      set: { columnWidths[index] = $0 }
    )
  }
}

struct BrowserColumn: Identifiable {
  let id = UUID()
  var selectedTagIds: Set<Int64>
  var reachableTags: [TagCount]
}

enum TagSortField {
  case name
  case count
}

struct BrowserColumnView: View {
  let title: String
  let items: [TagCount]
  let selection: Set<Int64>?
  let columnIndex: Int
  var focusedColumn: FocusState<Int?>.Binding
  let columnCount: Int
  let width: CGFloat
  let onSelect: (Set<Int64>) -> Void

  @State private var localSelection: Set<Int64> = []
  @State private var sortField: TagSortField = .count
  @State private var sortAscending = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Text(allLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .onTapGesture {
            localSelection = []
            onSelect([])
          }
          .accessibilityIdentifier("browser-column-\(columnIndex)-all")
          .accessibilityLabel("Show all, \(items.count) tags")
        sortMenu
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(localSelection.isEmpty ? Color.accentColor.opacity(0.1) : .clear)

      Divider()

      List(selection: $localSelection) {
        ForEach(sortedItems, id: \.tag.id) { tagCount in
          HStack {
            Text(tagCount.tag.name)
              .lineLimit(1)
              .truncationMode(.tail)
            Spacer()
            Text("\(tagCount.count)")
              .foregroundStyle(.secondary)
              .font(.caption)
          }
          .tag(tagCount.tag.id)
          .accessibilityIdentifier("browser-tag-\(tagCount.tag.name)")
          .accessibilityLabel("\(tagCount.tag.name), \(tagCount.count) items")
        }
      }
      .listStyle(.plain)
      .focused(focusedColumn, equals: columnIndex)
      .onKeyPress(.leftArrow) {
        guard columnIndex > 0 else { return .ignored }
        focusedColumn.wrappedValue = columnIndex - 1
        return .handled
      }
      .onKeyPress(.rightArrow) {
        guard columnIndex < columnCount - 1 else { return .ignored }
        focusedColumn.wrappedValue = columnIndex + 1
        return .handled
      }
      .onChange(of: localSelection) { _, newValue in
        onSelect(newValue)
      }
    }
    .frame(width: width)
    .onAppear {
      if let selection {
        localSelection = selection
      }
    }
  }

  private var allLabel: String {
    "All (\(items.count))"
  }

  private var sortedItems: [TagCount] {
    items.sorted { a, b in
      switch sortField {
      case .name:
        let cmp = a.tag.name.localizedStandardCompare(b.tag.name)
        return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
      case .count:
        if a.count != b.count {
          return sortAscending ? a.count < b.count : a.count > b.count
        }
        return a.tag.name.localizedStandardCompare(b.tag.name) == .orderedAscending
      }
    }
  }

  private var sortMenu: some View {
    Menu {
      Picker("Sort By", selection: $sortField) {
        Text("Name").tag(TagSortField.name)
        Text("Count").tag(TagSortField.count)
      }
      Picker("Order", selection: $sortAscending) {
        Text("Ascending").tag(true)
        Text("Descending").tag(false)
      }
    } label: {
      Image(systemName: "arrow.up.arrow.down")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityIdentifier("browser-column-\(columnIndex)-sort")
    .accessibilityLabel("Sort order")
  }
}

struct ColumnDivider: View {
  @Binding var width: CGFloat
  let minWidth: CGFloat
  let maxWidth: CGFloat
  var onResizeAll: ((CGFloat) -> Void)?
  @State private var startWidth: CGFloat?

  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .frame(width: 1)
      .frame(maxHeight: .infinity)
      .overlay {
        Rectangle()
          .fill(Color.clear)
          .frame(width: 8)
          .contentShape(Rectangle())
          .cursor(.resizeLeftRight)
          .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
              .onChanged { value in
                if startWidth == nil {
                  startWidth = width
                }
                let newWidth = min(
                  max((startWidth ?? width) + value.translation.width, minWidth),
                  maxWidth
                )
                if NSEvent.modifierFlags.contains(.option) {
                  onResizeAll?(newWidth)
                } else {
                  width = newWidth
                }
              }
              .onEnded { _ in
                startWidth = nil
              }
          )
      }
  }
}
