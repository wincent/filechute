import FilechuteCore
import SwiftUI

@MainActor @Observable
final class TableInfoState {
  static let shared = TableInfoState()
  var database: Database?
  var tableName: String?
}

struct TableInfoView: View {
  @State private var state = TableInfoState.shared
  @State private var info: Database.TableInfo?
  @State private var error: String?
  @State private var loadedKey: String?

  private var currentKey: String? {
    guard let db = state.database, let table = state.tableName else { return nil }
    return "\(ObjectIdentifier(db)):\(table)"
  }

  var body: some View {
    Group {
      if let info {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            schemaSection(info)
            columnsSection(info)
            indicesSection(info)
            statsSection(info)
          }
          .padding()
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else if let error {
        ContentUnavailableView(
          "Error",
          systemImage: "exclamationmark.triangle",
          description: Text(error)
        )
      } else if state.tableName != nil {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "No Table Selected",
          systemImage: "tablecells",
          description: Text("Select a table in the database browser.")
        )
      }
    }
    .frame(minWidth: 500, minHeight: 400)
    .navigationTitle(state.tableName.map { "Table Info: \($0)" } ?? "Table Info")
    .onChange(of: currentKey, initial: true) {
      loadInfo()
    }
  }

  private func loadInfo() {
    let key = currentKey
    guard key != loadedKey else { return }
    loadedKey = key
    info = nil
    error = nil

    guard let database = state.database, let table = state.tableName else { return }
    Task {
      do {
        let result = try await database.tableInfo(table: table)
        if currentKey == key {
          info = result
        }
      } catch {
        if currentKey == key {
          self.error = error.localizedDescription
        }
      }
    }
  }

  private func schemaSection(_ info: Database.TableInfo) -> some View {
    Section {
      Text(info.schema)
        .font(.system(.body, design: .monospaced))
        .textSelection(.enabled)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    } header: {
      Text("Schema")
        .font(.headline)
    }
  }

  private func columnsSection(_ info: Database.TableInfo) -> some View {
    Section {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
        GridRow {
          Text("Name").fontWeight(.medium)
          Text("Type").fontWeight(.medium)
          Text("Not Null").fontWeight(.medium)
          Text("Default").fontWeight(.medium)
          Text("PK").fontWeight(.medium)
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        Divider()
          .gridCellColumns(5)

        ForEach(info.columns, id: \.name) { col in
          GridRow {
            Text(col.name)
              .font(.system(.body, design: .monospaced))
            Text(col.type)
              .font(.system(.body, design: .monospaced))
              .foregroundStyle(.secondary)
            Text(col.notNull ? "YES" : "")
              .font(.caption)
            Text(col.defaultValue ?? "")
              .font(.system(.body, design: .monospaced))
              .foregroundStyle(.secondary)
            Text(col.primaryKey ? "YES" : "")
              .font(.caption)
          }
        }
      }
    } header: {
      Text("Columns (\(info.columns.count))")
        .font(.headline)
    }
  }

  private func indicesSection(_ info: Database.TableInfo) -> some View {
    Section {
      if info.indices.isEmpty {
        Text("No indices")
          .foregroundStyle(.secondary)
      } else {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
          GridRow {
            Text("Name").fontWeight(.medium)
            Text("Unique").fontWeight(.medium)
            Text("Columns").fontWeight(.medium)
          }
          .font(.caption)
          .foregroundStyle(.secondary)

          Divider()
            .gridCellColumns(3)

          ForEach(info.indices, id: \.name) { idx in
            GridRow {
              Text(idx.name)
                .font(.system(.body, design: .monospaced))
              Text(idx.unique ? "YES" : "")
                .font(.caption)
              Text(idx.columns.joined(separator: ", "))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    } header: {
      Text("Indices (\(info.indices.count))")
        .font(.headline)
    }
  }

  private func statsSection(_ info: Database.TableInfo) -> some View {
    Section {
      LabeledContent("Row Count") {
        Text("\(info.rowCount)")
          .font(.system(.body, design: .monospaced))
      }
    } header: {
      Text("Statistics")
        .font(.headline)
    }
  }
}
