import AppKit
import Darwin
import FilechuteCore
import Foundation

@Observable
@MainActor
final class IngestionProgress {
  var isActive = false
  var totalFiles = 0
  var processedFiles = 0
  var currentFileName = ""

  var fractionCompleted: Double {
    guard totalFiles > 0 else { return 0 }
    return Double(processedFiles) / Double(totalFiles)
  }
}

@Observable
@MainActor
final class StoreManager {
  private(set) var objects: [StoredObject] = []
  private(set) var allTags: [TagCount] = []
  private(set) var deletedObjects: [StoredObject] = []
  private(set) var tagNamesByObject: [Int64: [String]] = [:]
  private(set) var sizesByObject: [Int64: UInt64] = [:]
  private(set) var folders: [Folder] = []
  nonisolated let ingestionProgress: IngestionProgress

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
    self.ingestionProgress = MainActor.assumeIsolated { IngestionProgress() }
    Log.info("Initialized store at \(storeRoot.path)", category: .general)
  }

  func refresh() async throws {
    objects = try await database.allObjects()
    allTags = try await database.allTagsWithCounts()
    deletedObjects = try await database.allObjects(includeDeleted: true)
      .filter { $0.deletedAt != nil }
    tagNamesByObject = try await database.allTagNamesByObject()
    sizesByObject = try await database.allSizes()
    folders = try await database.allFolders()
    for i in objects.indices {
      objects[i].sizeBytes = sizesByObject[objects[i].id] ?? 0
    }
    for i in deletedObjects.indices {
      deletedObjects[i].sizeBytes = sizesByObject[deletedObjects[i].id] ?? 0
    }
    Log.debug(
      "Refreshed: \(objects.count) objects, \(allTags.count) tags, \(deletedObjects.count) deleted, \(folders.count) folders",
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

  // MARK: - Folders

  func createFolder(name: String, parentId: Int64? = nil) async throws -> Folder {
    let maxPos = try await database.maxFolderPosition(parentId: parentId)
    let folder = try await database.createFolder(
      name: name, parentId: parentId, position: maxPos + 1.0
    )
    try await refresh()
    return folder
  }

  func renameFolder(_ folderId: Int64, to name: String) async throws {
    try await database.renameFolder(id: folderId, name: name)
    try await refresh()
  }

  func moveFolder(_ folderId: Int64, parentId: Int64?, position: Double) async throws {
    try await database.moveFolder(id: folderId, parentId: parentId, position: position)
    try await checkAndRenumber(parentId: parentId)
    try await refresh()
  }

  func softDeleteFolder(_ folderId: Int64) async throws {
    try await database.softDeleteFolder(id: folderId)
    try await refresh()
  }

  func restoreFolder(_ folderId: Int64) async throws {
    try await database.restoreFolder(id: folderId)
    try await refresh()
  }

  func addItemToFolder(objectId: Int64, folderId: Int64) async throws {
    try await database.addItemToFolder(objectId: objectId, folderId: folderId)
    try await refresh()
  }

  func removeItemFromFolder(objectId: Int64, folderId: Int64) async throws {
    try await database.removeItemFromFolder(objectId: objectId, folderId: folderId)
    try await refresh()
  }

  func itemsInFolder(_ folderId: Int64, recursive: Bool = true) async throws -> [StoredObject] {
    var items = try await database.items(inFolder: folderId, recursive: recursive)
    for i in items.indices {
      items[i].sizeBytes = sizesByObject[items[i].id] ?? 0
    }
    return items
  }

  func foldersContaining(objectId: Int64) async throws -> [Folder] {
    try await database.folders(containingObject: objectId)
  }

  func directFolderForObject(_ objectId: Int64, inSubtreeOf rootFolderId: Int64) async throws
    -> Folder?
  {
    guard
      let folderId = try await database.directFolderIdForObject(
        objectId, inSubtreeOf: rootFolderId
      )
    else { return nil }
    return try await database.getFolder(byId: folderId)
  }

  func ingestDirectory(at url: URL, intoFolder parentFolderId: Int64? = nil) async throws {
    let ignorePatterns =
      UserDefaults.standard.stringArray(forKey: "ignoredFilePatterns") ?? [".DS_Store"]
    var countPaths: Set<String> = []
    ingestionProgress.totalFiles = countFiles(
      at: url, ignorePatterns: ignorePatterns, visitedPaths: &countPaths
    )
    ingestionProgress.processedFiles = 0
    ingestionProgress.currentFileName = ""
    ingestionProgress.isActive = true
    defer { ingestionProgress.isActive = false }

    var visitedPaths: Set<String> = []
    try await ingestDirectoryRecursive(
      at: url, parentFolderId: parentFolderId, ignorePatterns: ignorePatterns,
      visitedPaths: &visitedPaths
    )
    try await refresh()
  }

  private func shouldIgnoreFile(named name: String, patterns: [String]) -> Bool {
    patterns.contains { pattern in
      fnmatch(pattern, name, FNM_NOESCAPE) == 0
    }
  }

  private func countFiles(
    at url: URL, ignorePatterns: [String], visitedPaths: inout Set<String>
  ) -> Int {
    let realPath = url.resolvingSymlinksInPath().path
    guard !visitedPaths.contains(realPath) else { return 0 }
    visitedPaths.insert(realPath)
    let fm = FileManager.default
    guard
      let contents = try? fm.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey]
      )
    else { return 0 }
    var count = 0
    for item in contents {
      let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
      if isDir {
        count += countFiles(at: item, ignorePatterns: ignorePatterns, visitedPaths: &visitedPaths)
      } else if !shouldIgnoreFile(named: item.lastPathComponent, patterns: ignorePatterns) {
        count += 1
      }
    }
    return count
  }

  private func ingestDirectoryRecursive(
    at url: URL, parentFolderId: Int64?, ignorePatterns: [String],
    visitedPaths: inout Set<String>
  ) async throws {
    let realPath = url.resolvingSymlinksInPath().path
    guard !visitedPaths.contains(realPath) else {
      Log.debug("Skipping symlink cycle: \(url.path) -> \(realPath)", category: .folders)
      return
    }
    visitedPaths.insert(realPath)

    let folder = try await createFolder(name: url.lastPathComponent, parentId: parentFolderId)

    let fm = FileManager.default
    let contents = try fm.contentsOfDirectory(
      at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
    )

    var fileCount = 0
    var dirCount = 0
    for item in contents {
      let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])
      if resourceValues.isDirectory == true {
        dirCount += 1
        try await ingestDirectoryRecursive(
          at: item, parentFolderId: folder.id, ignorePatterns: ignorePatterns,
          visitedPaths: &visitedPaths
        )
      } else if !shouldIgnoreFile(named: item.lastPathComponent, patterns: ignorePatterns) {
        ingestionProgress.currentFileName = item.lastPathComponent
        let object = try await ingestionService.ingest(fileAt: item)
        try await database.addItemToFolder(objectId: object.id, folderId: folder.id)
        ingestionProgress.processedFiles += 1
        fileCount += 1
      }
    }
    Log.debug(
      "Imported directory '\(url.lastPathComponent)': \(fileCount) files, \(dirCount) subdirectories",
      category: .folders
    )
  }

  private func checkAndRenumber(parentId: Int64?) async throws {
    let siblings: [Folder]
    if let parentId {
      siblings = folders.filter { $0.parentId == parentId }
    } else {
      siblings = folders.filter { $0.parentId == nil }
    }

    guard siblings.count >= 2 else { return }
    let sorted = siblings.sorted { $0.position < $1.position }
    for i in 0..<(sorted.count - 1) {
      let gap = sorted[i + 1].position - sorted[i].position
      if gap < 1e-6 {
        try await database.renumberFolderPositions(parentId: parentId)
        return
      }
    }
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
