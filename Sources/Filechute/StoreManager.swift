import AppKit
import FilechuteCore
import Foundation

@Observable
@MainActor
final class StoreManager {
  private(set) var objects: [StoredObject] = []
  private(set) var allTags: [TagCount] = []
  private(set) var deletedObjects: [StoredObject] = []
  private(set) var tagNamesByObject: [Int64: [String]] = [:]
  private(set) var sizesByObject: [Int64: UInt64] = [:]

  nonisolated let storeRoot: URL
  nonisolated let objectStore: ObjectStore
  nonisolated let database: Database
  nonisolated let ingestionService: IngestionService
  nonisolated let fileAccessService: FileAccessService
  nonisolated let garbageCollector: GarbageCollector
  nonisolated let thumbnailService: ThumbnailService

  nonisolated var storeName: String {
    storeRoot.deletingPathExtension().lastPathComponent
  }

  nonisolated init(storeRoot: URL) throws {
    self.storeRoot = storeRoot
    try FileManager.default.createDirectory(at: storeRoot, withIntermediateDirectories: true)
    let store = try ObjectStore(rootDirectory: storeRoot)
    let db = try Database(path: storeRoot.appendingPathComponent("filechute.db").path)
    self.objectStore = store
    self.database = db
    self.ingestionService = IngestionService(objectStore: store, database: db)
    self.fileAccessService = try FileAccessService(
      objectStore: store,
      tmpDirectory: storeRoot.appendingPathComponent("tmp")
    )
    self.garbageCollector = GarbageCollector(objectStore: store, database: db)
    self.thumbnailService = ThumbnailService(objectStore: store)
    Log.info("Initialized store at \(storeRoot.path)", category: .general)
  }

  func refresh() async throws {
    objects = try await database.allObjects()
    allTags = try await database.allTagsWithCounts()
    deletedObjects = try await database.allObjects(includeDeleted: true)
      .filter { $0.deletedAt != nil }
    tagNamesByObject = try await database.allTagNamesByObject()
    sizesByObject = try await database.allSizes()
    for i in objects.indices {
      objects[i].sizeBytes = sizesByObject[objects[i].id] ?? 0
    }
    for i in deletedObjects.indices {
      deletedObjects[i].sizeBytes = sizesByObject[deletedObjects[i].id] ?? 0
    }
    Log.debug(
      "Refreshed: \(objects.count) objects, \(allTags.count) tags, \(deletedObjects.count) deleted",
      category: .ui
    )
  }

  func ingest(urls: [URL]) async throws {
    Log.debug("Ingesting \(urls.count) file(s)", category: .ui)
    for url in urls {
      _ = try await ingestionService.ingest(fileAt: url)
    }
    try await refresh()
  }

  func tags(for objectId: Int64) async throws -> [Tag] {
    try await database.tags(forObject: objectId)
  }

  func addTag(_ name: String, to objectId: Int64) async throws {
    let tag = try await database.getOrCreateTag(name: name)
    try await database.addTag(tag.id, toObject: objectId)
    try await database.touchModified(id: objectId)
    try await refresh()
  }

  func removeTag(_ tagId: Int64, from objectId: Int64) async throws {
    try await database.removeTag(tagId, fromObject: objectId)
    try await database.touchModified(id: objectId)
    try await refresh()
  }

  func addTagToObjects(_ name: String, objectIds: Set<Int64>) async throws {
    let tag = try await database.getOrCreateTag(name: name)
    for objectId in objectIds {
      try await database.addTag(tag.id, toObject: objectId)
      try await database.touchModified(id: objectId)
    }
    try await refresh()
  }

  func removeTagFromObjects(_ tagId: Int64, objectIds: Set<Int64>) async throws {
    for objectId in objectIds {
      try await database.removeTag(tagId, fromObject: objectId)
      try await database.touchModified(id: objectId)
    }
    try await refresh()
  }

  func deleteObject(_ objectId: Int64) async throws {
    try await database.softDeleteObject(id: objectId)
    try await refresh()
  }

  func restoreObject(_ objectId: Int64) async throws {
    try await database.restoreObject(id: objectId)
    try await refresh()
  }

  func permanentlyDelete(_ objectId: Int64) async throws {
    if let obj = try await database.getObject(byId: objectId) {
      try? objectStore.remove(obj.hash)
    }
    try await database.permanentlyDeleteObject(id: objectId)
    try await refresh()
  }

  func updateNotes(_ objectId: Int64, notes: String?) async throws {
    try await database.updateNotes(id: objectId, notes: notes)
    try await refresh()
  }

  func renameObject(_ objectId: Int64, to name: String) async throws {
    try await database.renameObject(id: objectId, newName: name)
    try await refresh()
  }

  func fileExtension(for object: StoredObject) async -> String? {
    if let ext = try? await database.getMetadata(objectId: object.id, key: "extension"),
      !ext.isEmpty
    {
      return ext
    }
    let components = object.name.components(separatedBy: ".")
    return components.count > 1 ? components.last : nil
  }

  private func extensionFromName(_ name: String) -> String? {
    let components = name.components(separatedBy: ".")
    return components.count > 1 ? components.last : nil
  }

  func temporaryCopyURL(for object: StoredObject) async throws -> URL {
    let ext = await fileExtension(for: object)
    return try fileAccessService.openTemporaryCopy(
      hash: object.hash,
      name: object.name,
      extension: ext
    )
  }

  func thumbnailURL(for object: StoredObject) -> URL {
    objectStore.thumbnailURL(for: object.hash)
  }

  func openObject(_ object: StoredObject) async throws {
    let url = try await temporaryCopyURL(for: object)
    try await database.touchLastOpened(id: object.id)
    try await refresh()
    NSWorkspace.shared.open(url)
  }

  func openObjectWith(_ object: StoredObject) async throws {
    let url = try await temporaryCopyURL(for: object)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func versionHistory(for objectId: Int64) async throws -> [StoredObject] {
    try await database.versionHistory(for: objectId)
  }

  func emptyTrash() async throws {
    Log.info("Emptying trash: \(deletedObjects.count) objects", category: .ui)
    for obj in deletedObjects {
      try? objectStore.remove(obj.hash)
      try await database.permanentlyDeleteObject(id: obj.id)
    }
    try await refresh()
  }

  func backfillThumbnails() async {
    let allObjects = (try? await database.allObjects()) ?? []
    var generated = 0
    for object in allObjects {
      if objectStore.thumbnailExists(for: object.hash) { continue }
      let ext = (await fileExtension(for: object)) ?? ""
      await thumbnailService.generateThumbnailFromStore(hash: object.hash, fileExtension: ext)
      if objectStore.thumbnailExists(for: object.hash) {
        generated += 1
      }
    }
    if generated > 0 {
      Log.info("Backfill: generated \(generated) thumbnails", category: .objectStore)
    }
  }
}
