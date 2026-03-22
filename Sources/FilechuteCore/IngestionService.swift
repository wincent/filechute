import Foundation
import UniformTypeIdentifiers

public struct IngestionService: Sendable {
  public let objectStore: ObjectStore
  public let database: Database
  public let thumbnailService: ThumbnailService

  public init(objectStore: ObjectStore, database: Database) {
    self.objectStore = objectStore
    self.database = database
    self.thumbnailService = ThumbnailService(objectStore: objectStore)
  }

  public func ingest(
    fileAt sourceURL: URL,
    name: String? = nil,
    tags: [String] = []
  ) async throws -> StoredObject {
    let (hash, _) = try objectStore.store(fileAt: sourceURL)

    let ext = sourceURL.pathExtension
    let sizeBytes: UInt64? =
      (try? FileManager.default.attributesOfItem(atPath: sourceURL.path))?[.size] as? UInt64
    let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType

    writeInfo(
      originalName: sourceURL.lastPathComponent,
      hash: hash,
      sizeBytes: sizeBytes ?? 0,
      mimeType: mimeType
    )

    await thumbnailService.generateThumbnail(for: sourceURL, hash: hash)
    try? objectStore.setReadOnly(for: hash)

    if let existing = try await database.getObject(byHash: hash) {
      Log.debug(
        "Found existing object for \(sourceURL.lastPathComponent)",
        category: .ingestion
      )
      for tagName in tags {
        let tag = try await database.getOrCreateTag(name: tagName)
        try await database.addTag(tag.id, toObject: existing.id)
      }
      return existing
    }

    let objectName = name ?? sourceURL.deletingPathExtension().lastPathComponent

    let objectId = try await database.insertObject(hash: hash, name: objectName, fileExtension: ext)
    if !ext.isEmpty {
      try await database.setMetadata(objectId: objectId, key: "extension", value: ext)
    }

    if let sizeBytes {
      try await database.setMetadata(
        objectId: objectId, key: "size_bytes", value: String(sizeBytes))
    }

    if let mimeType {
      try await database.setMetadata(objectId: objectId, key: "mime_type", value: mimeType)
    }

    for tagName in tags {
      let tag = try await database.getOrCreateTag(name: tagName)
      try await database.addTag(tag.id, toObject: objectId)
    }

    guard let object = try await database.getObject(byId: objectId) else {
      throw DatabaseError.notFound
    }
    Log.info("Ingested \(objectName) (\(hash.hexString.prefix(8)))", category: .ingestion)
    return object
  }

  public func update(
    objectId: Int64,
    withFileAt sourceURL: URL
  ) async throws -> StoredObject {
    guard let existing = try await database.getObject(byId: objectId) else {
      throw DatabaseError.notFound
    }

    let (newHash, _) = try objectStore.store(fileAt: sourceURL)

    let ext = sourceURL.pathExtension
    let sizeBytes: UInt64 =
      ((try? FileManager.default.attributesOfItem(atPath: sourceURL.path))?[.size] as? UInt64) ?? 0
    let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType
    writeInfo(
      originalName: sourceURL.lastPathComponent,
      hash: newHash,
      sizeBytes: sizeBytes,
      mimeType: mimeType
    )

    await thumbnailService.generateThumbnail(for: sourceURL, hash: newHash)
    try? objectStore.setReadOnly(for: newHash)

    if newHash == existing.hash {
      Log.debug("Content unchanged for object \(objectId)", category: .ingestion)
      return existing
    }

    let newObjectId = try await database.insertObject(hash: newHash, name: existing.name)

    let existingTags = try await database.tags(forObject: objectId)
    for tag in existingTags {
      try await database.addTag(tag.id, toObject: newObjectId)
    }

    let existingMetadata = try await database.allMetadata(for: objectId)
    for meta in existingMetadata {
      try await database.setMetadata(objectId: newObjectId, key: meta.key, value: meta.value)
    }

    try await database.addVersion(objectId: newObjectId, previousObjectId: objectId)

    guard let newObject = try await database.getObject(byId: newObjectId) else {
      throw DatabaseError.notFound
    }
    Log.info(
      "Updated object \(objectId): \(existing.hash.hexString.prefix(8)) -> \(newHash.hexString.prefix(8))",
      category: .ingestion
    )
    return newObject
  }

  private func writeInfo(
    originalName: String,
    hash: ContentHash,
    sizeBytes: UInt64,
    mimeType: String?
  ) {
    guard !objectStore.infoExists(for: hash) else { return }
    let info = ObjectInfo(
      originalName: originalName,
      importDate: Date(),
      contentHash: "sha256:\(hash.hexString)",
      sizeBytes: sizeBytes,
      mimeType: mimeType
    )
    do {
      let data = try ObjectInfo.encoder.encode(info)
      try objectStore.storeInfo(data, for: hash)
      Log.debug("Wrote info.json (\(hash.hexString.prefix(8)))", category: .objectStore)
    } catch {
      Log.debug(
        "Failed to write info.json (\(hash.hexString.prefix(8))): \(error.localizedDescription)",
        category: .objectStore
      )
    }
  }
}
