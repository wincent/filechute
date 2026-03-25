import FilechuteCore
import SwiftUI

struct LogWindowView: View {
  let logStore = LogStore.shared
  @State private var filterCategory: LogCategory?
  @State private var filterLevel: LogLevel?
  @State private var autoScroll = true

  var filteredEntries: [LogEntry] {
    logStore.entries.filter { entry in
      if let cat = filterCategory, entry.category != cat { return false }
      if let lvl = filterLevel, entry.level != lvl { return false }
      return true
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      logList
    }
    .frame(minWidth: 600, minHeight: 300)
  }

  private var toolbar: some View {
    HStack {
      Picker("Category", selection: $filterCategory) {
        Text("All Categories").tag(nil as LogCategory?)
        Divider()
        ForEach(LogCategory.allCases, id: \.self) { cat in
          Text(cat.rawValue).tag(cat as LogCategory?)
        }
      }
      .frame(width: 180)
      .accessibilityIdentifier("log-category-picker")

      Picker("Level", selection: $filterLevel) {
        Text("All Levels").tag(nil as LogLevel?)
        Divider()
        ForEach(LogLevel.allCases, id: \.self) { lvl in
          Text(lvl.rawValue).tag(lvl as LogLevel?)
        }
      }
      .frame(width: 140)
      .accessibilityIdentifier("log-level-picker")

      Spacer()

      Toggle("Auto-scroll", isOn: $autoScroll)
        .accessibilityIdentifier("log-auto-scroll")

      Button("Clear") {
        logStore.clear()
      }
      .accessibilityIdentifier("log-clear-button")
    }
    .padding(8)
  }

  private var logList: some View {
    ScrollViewReader { proxy in
      List(filteredEntries) { entry in
        LogEntryRow(entry: entry)
      }
      .onChange(of: logStore.entries.count) {
        if autoScroll, let lastId = filteredEntries.last?.id {
          proxy.scrollTo(lastId, anchor: .bottom)
        }
      }
    }
  }
}

private struct LogEntryRow: View {
  static let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
  }()

  let entry: LogEntry

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(Self.timestampFormatter.string(from: entry.timestamp))
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)

      Text(entry.level.rawValue.uppercased())
        .font(.caption.monospaced().bold())
        .foregroundStyle(levelColor)
        .frame(width: 44, alignment: .leading)

      Text(entry.category.rawValue)
        .font(.caption)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 3))

      Text(entry.message)
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
  }

  private var levelColor: Color {
    switch entry.level {
    case .debug: .secondary
    case .info: .primary
    case .error: .red
    }
  }
}
