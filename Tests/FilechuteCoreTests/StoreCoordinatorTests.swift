import Foundation
import Testing

@testable import FilechuteCore

@Suite("StoreCoordinator", .serialized)
@MainActor
struct StoreCoordinatorTests {
  // Tests use the shared singleton; each test cleans up its own state.

  @Test("uniqueNewStoreName returns base name when no conflicts")
  func uniqueNewStoreNameBase() async throws {
    let coordinator = StoreCoordinator.shared
    let name = coordinator.uniqueNewStoreName()
    #expect(name.hasPrefix("New Filechute Store"))
  }

  @Test("addRecentStore inserts at front")
  func addRecentStoreInsertsAtFront() async throws {
    let coordinator = StoreCoordinator.shared
    coordinator.clearRecentStores()

    let url1 = URL(fileURLWithPath: "/tmp/filechute-test-1.filechute")
    let url2 = URL(fileURLWithPath: "/tmp/filechute-test-2.filechute")

    // Create the directories so they pass the fileExists check on load
    try FileManager.default.createDirectory(at: url1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: url2, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: url1)
      try? FileManager.default.removeItem(at: url2)
    }

    coordinator.addRecentStore(url1)
    coordinator.addRecentStore(url2)

    #expect(coordinator.recentStores.first == url2)
    #expect(coordinator.recentStores.count == 2)

    coordinator.clearRecentStores()
  }

  @Test("addRecentStore deduplicates and moves to front")
  func addRecentStoreDeduplicates() async throws {
    let coordinator = StoreCoordinator.shared
    coordinator.clearRecentStores()

    let url1 = URL(fileURLWithPath: "/tmp/filechute-test-dedup-1.filechute")
    let url2 = URL(fileURLWithPath: "/tmp/filechute-test-dedup-2.filechute")
    try FileManager.default.createDirectory(at: url1, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: url2, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: url1)
      try? FileManager.default.removeItem(at: url2)
    }

    coordinator.addRecentStore(url1)
    coordinator.addRecentStore(url2)
    coordinator.addRecentStore(url1)

    #expect(coordinator.recentStores.count == 2)
    #expect(coordinator.recentStores[0] == url1)
    #expect(coordinator.recentStores[1] == url2)

    coordinator.clearRecentStores()
  }

  @Test("addRecentStore enforces max limit")
  func maxRecentStores() async throws {
    let coordinator = StoreCoordinator.shared
    coordinator.clearRecentStores()

    var urls: [URL] = []
    for i in 0..<12 {
      let url = URL(fileURLWithPath: "/tmp/filechute-test-max-\(i).filechute")
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      urls.append(url)
    }
    defer {
      for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    for url in urls {
      coordinator.addRecentStore(url)
    }

    #expect(coordinator.recentStores.count == 10)
    // Most recent should be at front
    #expect(coordinator.recentStores[0] == urls.last)

    coordinator.clearRecentStores()
  }

  @Test("removeRecentStore removes the URL")
  func removeRecentStore() async throws {
    let coordinator = StoreCoordinator.shared
    coordinator.clearRecentStores()

    let url = URL(fileURLWithPath: "/tmp/filechute-test-remove.filechute")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }

    coordinator.addRecentStore(url)
    #expect(coordinator.recentStores.count == 1)

    coordinator.removeRecentStore(url)
    #expect(coordinator.recentStores.isEmpty)
  }

  @Test("clearRecentStores removes all")
  func clearRecentStores() async throws {
    let coordinator = StoreCoordinator.shared
    let url = URL(fileURLWithPath: "/tmp/filechute-test-clear.filechute")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }

    coordinator.addRecentStore(url)
    coordinator.clearRecentStores()
    #expect(coordinator.recentStores.isEmpty)
  }

  @Test("registerStore and deregisterStore manage ref counts")
  func refCounting() async throws {
    let coordinator = StoreCoordinator.shared
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filechute-coord-test-\(UUID().uuidString)")
    let storeRoot = dir.appendingPathComponent("refcount.filechute")
    defer { try? FileManager.default.removeItem(at: dir) }

    let manager = try StoreManager(storeRoot: storeRoot)

    coordinator.registerStore(manager)
    #expect(coordinator.openStores[storeRoot] != nil)

    // Register again (simulating a second window)
    coordinator.registerStore(manager)

    // First deregister shouldn't remove it (ref count > 0)
    coordinator.deregisterStore(url: storeRoot)
    #expect(coordinator.openStores[storeRoot] != nil)

    // Second deregister should remove it
    coordinator.deregisterStore(url: storeRoot)
    #expect(coordinator.openStores[storeRoot] == nil)
  }

  @Test("urlForStoreName appends extension")
  func urlForStoreName() async throws {
    let coordinator = StoreCoordinator.shared
    let url = coordinator.urlForStoreName("My Store")
    #expect(url.lastPathComponent == "My Store.filechute")
  }

  @Test("storeNameExists returns false for nonexistent")
  func storeNameExistsFalse() async throws {
    let coordinator = StoreCoordinator.shared
    #expect(!coordinator.storeNameExists("Nonexistent Store \(UUID().uuidString)"))
  }

  @Test("createStore creates directory and adds to recent")
  func createStore() async throws {
    let coordinator = StoreCoordinator.shared
    coordinator.clearRecentStores()

    let name = "Test Store \(UUID().uuidString)"
    let url = try coordinator.createStore(name: name)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(coordinator.storeNameExists(name))
    #expect(coordinator.recentStores.contains(url))

    coordinator.clearRecentStores()
  }

  @Test("renameStore moves directory and updates recent stores")
  func renameStore() async throws {
    let coordinator = StoreCoordinator.shared
    coordinator.clearRecentStores()

    let oldName = "OldName-\(UUID().uuidString)"
    let oldURL = try coordinator.createStore(name: oldName)
    defer {
      try? FileManager.default.removeItem(at: oldURL)
    }

    let newName = "NewName-\(UUID().uuidString)"
    let newURL = try coordinator.renameStore(from: oldURL, to: newName)
    defer {
      try? FileManager.default.removeItem(at: newURL)
    }

    #expect(!FileManager.default.fileExists(atPath: oldURL.path))
    #expect(FileManager.default.fileExists(atPath: newURL.path))
    #expect(!coordinator.recentStores.contains(oldURL))
    #expect(coordinator.recentStores.contains(newURL))

    coordinator.clearRecentStores()
  }

  @Test("setLastActiveStore and lastActiveStoreURL round-trip")
  func lastActiveStore() async throws {
    let coordinator = StoreCoordinator.shared

    let url = URL(fileURLWithPath: "/tmp/filechute-test-active-\(UUID().uuidString).filechute")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }

    coordinator.setLastActiveStore(url)
    // Compare paths since URL trailing slash can differ for directories
    #expect(coordinator.lastActiveStoreURL.path == url.path)
  }

  @Test("lastActiveStoreURL falls back to default when path missing")
  func lastActiveStoreFallback() async throws {
    let coordinator = StoreCoordinator.shared

    // Set a non-existent path
    AppDefaults.shared.set("/tmp/nonexistent-\(UUID().uuidString)", forKey: "lastActiveStoreURL")

    #expect(coordinator.lastActiveStoreURL == coordinator.defaultStoreURL)
  }
}
