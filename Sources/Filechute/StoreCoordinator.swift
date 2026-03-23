import FilechuteCore
import Foundation

@Observable
@MainActor
final class StoreCoordinator {
  static let shared = StoreCoordinator()

  let storesDirectory: URL
  let defaultStoreURL: URL
  private(set) var recentStores: [URL] = []

  private let recentStoresKey = "recentStoreURLs"
  private let lastActiveStoreKey = "lastActiveStoreURL"
  private let maxRecentStores = 10

  private init() {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let stores =
      appSupport
      .appendingPathComponent("Filechute")
      .appendingPathComponent("stores")
    self.storesDirectory = stores
    self.defaultStoreURL = stores.appendingPathComponent("Default Store.filechute")
    loadRecentStores()
  }

  func uniqueNewStoreName() -> String {
    let fm = FileManager.default
    let base = "New Filechute Store"
    var candidate = base
    var n = 1
    while fm.fileExists(
      atPath: storesDirectory.appendingPathComponent("\(candidate).filechute").path
    ) {
      n += 1
      candidate = "\(base) \(n)"
    }
    return candidate
  }

  func urlForStoreName(_ name: String) -> URL {
    storesDirectory.appendingPathComponent("\(name).filechute")
  }

  func createStore(name: String) throws -> URL {
    let url = urlForStoreName(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addRecentStore(url)
    Log.info("Created store: \(url.path)", category: .general)
    return url
  }

  func storeNameExists(_ name: String) -> Bool {
    FileManager.default.fileExists(
      atPath: urlForStoreName(name).path
    )
  }

  func renameStore(from oldURL: URL, to newName: String) throws -> URL {
    let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(
      "\(newName).filechute"
    )
    try FileManager.default.moveItem(at: oldURL, to: newURL)
    removeRecentStore(oldURL)
    addRecentStore(newURL)
    Log.info(
      "Renamed store: \(oldURL.lastPathComponent) -> \(newURL.lastPathComponent)",
      category: .general)
    return newURL
  }

  var lastActiveStoreURL: URL {
    if let path = UserDefaults.standard.string(forKey: lastActiveStoreKey),
      FileManager.default.fileExists(atPath: path)
    {
      return URL(fileURLWithPath: path)
    }
    return defaultStoreURL
  }

  func setLastActiveStore(_ url: URL) {
    UserDefaults.standard.set(url.path, forKey: lastActiveStoreKey)
  }

  func addRecentStore(_ url: URL) {
    recentStores.removeAll { $0 == url }
    recentStores.insert(url, at: 0)
    if recentStores.count > maxRecentStores {
      recentStores = Array(recentStores.prefix(maxRecentStores))
    }
    saveRecentStores()
  }

  func removeRecentStore(_ url: URL) {
    recentStores.removeAll { $0 == url }
    saveRecentStores()
  }

  func clearRecentStores() {
    recentStores.removeAll()
    saveRecentStores()
  }

  private func loadRecentStores() {
    guard let paths = UserDefaults.standard.stringArray(forKey: recentStoresKey) else { return }
    recentStores = paths.compactMap { URL(fileURLWithPath: $0) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  private func saveRecentStores() {
    let paths = recentStores.map(\.path)
    UserDefaults.standard.set(paths, forKey: recentStoresKey)
  }
}
