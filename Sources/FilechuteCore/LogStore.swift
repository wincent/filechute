import Foundation

public enum LogLevel: String, Sendable, CaseIterable {
  case debug
  case info
  case error
}

public enum LogCategory: String, Sendable, CaseIterable {
  case database
  case objectStore
  case ingestion
  case fileAccess
  case garbageCollector
  case integrity
  case ui
  case general
}

public struct LogEntry: Identifiable, Sendable {
  public let id: UInt64
  public let timestamp: Date
  public let level: LogLevel
  public let category: LogCategory
  public let message: String
}

@Observable
@MainActor
public final class LogStore {
  public static let shared = LogStore()

  public private(set) var entries: [LogEntry] = []
  private let maxEntries = 5000
  private var nextId: UInt64 = 0

  init() {}

  public func append(level: LogLevel, category: LogCategory, message: String) {
    let entry = LogEntry(
      id: nextId,
      timestamp: Date(),
      level: level,
      category: category,
      message: message
    )
    nextId += 1
    entries.append(entry)
    if entries.count > maxEntries {
      entries.removeFirst(entries.count - maxEntries)
    }
  }

  public func clear() {
    entries.removeAll()
  }
}
