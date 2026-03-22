import Foundation
import Testing

@testable import FilechuteCore

@Suite("LogStore")
@MainActor
struct LogStoreTests {
  @Test("Append adds entry with correct fields")
  func appendEntry() {
    let store = LogStore()
    store.append(level: .debug, category: .database, message: "test message")

    #expect(store.entries.count == 1)
    let entry = store.entries[0]
    #expect(entry.id == 0)
    #expect(entry.level == .debug)
    #expect(entry.category == .database)
    #expect(entry.message == "test message")
  }

  @Test("Entry IDs increment")
  func entryIds() {
    let store = LogStore()
    store.append(level: .debug, category: .general, message: "first")
    store.append(level: .info, category: .general, message: "second")
    store.append(level: .error, category: .general, message: "third")

    #expect(store.entries[0].id == 0)
    #expect(store.entries[1].id == 1)
    #expect(store.entries[2].id == 2)
  }

  @Test("Timestamp is set to current time")
  func timestamp() {
    let store = LogStore()
    let before = Date()
    store.append(level: .debug, category: .general, message: "test")
    let after = Date()

    let timestamp = store.entries[0].timestamp
    #expect(timestamp >= before)
    #expect(timestamp <= after)
  }

  @Test("All log levels preserved")
  func logLevels() {
    let store = LogStore()
    store.append(level: .debug, category: .general, message: "d")
    store.append(level: .info, category: .general, message: "i")
    store.append(level: .error, category: .general, message: "e")

    #expect(store.entries[0].level == .debug)
    #expect(store.entries[1].level == .info)
    #expect(store.entries[2].level == .error)
  }

  @Test("All categories preserved")
  func categories() {
    let store = LogStore()
    for category in LogCategory.allCases {
      store.append(level: .debug, category: category, message: category.rawValue)
    }

    #expect(store.entries.count == LogCategory.allCases.count)
    for (entry, category) in zip(store.entries, LogCategory.allCases) {
      #expect(entry.category == category)
    }
  }

  @Test("Entries capped at 5000")
  func ringBuffer() {
    let store = LogStore()
    for i in 0...5000 {
      store.append(level: .debug, category: .general, message: "entry \(i)")
    }

    #expect(store.entries.count == 5000)
    #expect(store.entries.first?.message == "entry 1")
    #expect(store.entries.last?.message == "entry 5000")
  }

  @Test("Clear removes all entries")
  func clear() {
    let store = LogStore()
    store.append(level: .debug, category: .general, message: "one")
    store.append(level: .info, category: .general, message: "two")
    #expect(store.entries.count == 2)

    store.clear()
    #expect(store.entries.isEmpty)
  }
}

@Suite("Log facade")
@MainActor
struct LogFacadeTests {
  @Test("debug dispatches to LogStore with debug level")
  func debugLevel() async throws {
    let countBefore = LogStore.shared.entries.count
    Log.debug("facade debug test", category: .database)
    await Task.yield()

    let entry = LogStore.shared.entries.dropFirst(countBefore)
      .first { $0.message == "facade debug test" }
    #expect(entry != nil)
    #expect(entry?.level == .debug)
    #expect(entry?.category == .database)
  }

  @Test("info dispatches to LogStore with info level")
  func infoLevel() async throws {
    let countBefore = LogStore.shared.entries.count
    Log.info("facade info test", category: .ingestion)
    await Task.yield()

    let entry = LogStore.shared.entries.dropFirst(countBefore)
      .first { $0.message == "facade info test" }
    #expect(entry != nil)
    #expect(entry?.level == .info)
    #expect(entry?.category == .ingestion)
  }

  @Test("error dispatches to LogStore with error level")
  func errorLevel() async throws {
    let countBefore = LogStore.shared.entries.count
    Log.error("facade error test", category: .integrity)
    await Task.yield()

    let entry = LogStore.shared.entries.dropFirst(countBefore)
      .first { $0.message == "facade error test" }
    #expect(entry != nil)
    #expect(entry?.level == .error)
    #expect(entry?.category == .integrity)
  }

  @Test("Default category is general")
  func defaultCategory() async throws {
    let countBefore = LogStore.shared.entries.count
    Log.debug("default category test")
    await Task.yield()

    let entry = LogStore.shared.entries.dropFirst(countBefore)
      .first { $0.message == "default category test" }
    #expect(entry?.category == .general)
  }
}
