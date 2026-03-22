import Foundation

public struct GarbageCollector: Sendable {
  public let objectStore: ObjectStore
  public let database: Database

  public init(objectStore: ObjectStore, database: Database) {
    self.objectStore = objectStore
    self.database = database
  }

  public func collectGarbage(olderThan cutoff: Date = Date().addingTimeInterval(-30 * 86400))
    async throws -> Int
  {
    let deleted = try await database.allObjects(includeDeleted: true)
      .filter { $0.deletedAt != nil && $0.deletedAt! < cutoff }

    var collected = 0
    for object in deleted {
      let hasHistory = try await !database.versionHistory(for: object.id).isEmpty
      let hasSuccessor = try await database.latestVersion(of: object.id) != nil
      let isReferencedByVersion = hasHistory || hasSuccessor

      if isReferencedByVersion {
        continue
      }

      try? objectStore.remove(object.hash)
      try await database.permanentlyDeleteObject(id: object.id)
      collected += 1
    }
    Log.info(
      "Garbage collection: \(deleted.count) candidates, \(collected) collected",
      category: .garbageCollector
    )
    return collected
  }
}
