import Foundation

@Observable
@MainActor
public final class StoreCoordinator {
  public static let shared = StoreCoordinator()

  public let storesDirectory: URL
  public let defaultStoreURL: URL
  public private(set) var recentStores: [URL] = []
  public private(set) var openStores: [URL: StoreManager] = [:]
  private var storeRefCounts: [URL: Int] = [:]

  private let recentStoresKey = "recentStoreURLs"
  private let lastActiveStoreKey = "lastActiveStoreURL"
  private let maxRecentStores = 10

  private init() {
    let args = CommandLine.arguments
    let stores: URL
    if let index = args.firstIndex(of: "-StoreBaseDirectory"),
      index + 1 < args.count
    {
      stores = URL(fileURLWithPath: args[index + 1], isDirectory: true)
    } else {
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      stores =
        appSupport
        .appendingPathComponent("Filechute")
        .appendingPathComponent("stores")
    }
    self.storesDirectory = stores
    self.defaultStoreURL = stores.appendingPathComponent("Default Store.filechute")
    loadRecentStores()
  }

  public func uniqueNewStoreName() -> String {
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

  public func urlForStoreName(_ name: String) -> URL {
    storesDirectory.appendingPathComponent("\(name).filechute")
  }

  public func createStore(name: String) throws -> URL {
    let url = urlForStoreName(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addRecentStore(url)
    Log.info("Created store: \(url.path)", category: .general)
    return url
  }

  public func storeNameExists(_ name: String) -> Bool {
    FileManager.default.fileExists(
      atPath: urlForStoreName(name).path
    )
  }

  public func renameStore(from oldURL: URL, to newName: String) throws -> URL {
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

  public var lastActiveStoreURL: URL {
    if let path = AppDefaults.shared.string(forKey: lastActiveStoreKey),
      FileManager.default.fileExists(atPath: path)
    {
      return URL(fileURLWithPath: path)
    }
    return defaultStoreURL
  }

  public func setLastActiveStore(_ url: URL) {
    AppDefaults.shared.set(url.path, forKey: lastActiveStoreKey)
  }

  public func registerStore(_ manager: StoreManager) {
    let url = manager.storeRoot
    openStores[url] = manager
    storeRefCounts[url, default: 0] += 1
  }

  public func deregisterStore(url: URL) {
    let count = storeRefCounts[url, default: 0] - 1
    if count <= 0 {
      openStores.removeValue(forKey: url)
      storeRefCounts.removeValue(forKey: url)
    } else {
      storeRefCounts[url] = count
    }
  }

  public func addRecentStore(_ url: URL) {
    recentStores.removeAll { $0 == url }
    recentStores.insert(url, at: 0)
    if recentStores.count > maxRecentStores {
      recentStores = Array(recentStores.prefix(maxRecentStores))
    }
    saveRecentStores()
  }

  public func removeRecentStore(_ url: URL) {
    recentStores.removeAll { $0 == url }
    saveRecentStores()
  }

  public func clearRecentStores() {
    recentStores.removeAll()
    saveRecentStores()
  }

  private func loadRecentStores() {
    guard let paths = AppDefaults.shared.stringArray(forKey: recentStoresKey) else { return }
    recentStores = paths.compactMap { URL(fileURLWithPath: $0) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  private func saveRecentStores() {
    let paths = recentStores.map(\.path)
    AppDefaults.shared.set(paths, forKey: recentStoresKey)
  }
}
