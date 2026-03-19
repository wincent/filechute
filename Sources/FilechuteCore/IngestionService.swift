import Foundation
import UniformTypeIdentifiers

public struct IngestionService: Sendable {
    public let objectStore: ObjectStore
    public let database: Database

    public init(objectStore: ObjectStore, database: Database) {
        self.objectStore = objectStore
        self.database = database
    }

    public func ingest(
        fileAt sourceURL: URL,
        name: String? = nil,
        tags: [String] = []
    ) async throws -> StoredObject {
        let (hash, _) = try objectStore.store(fileAt: sourceURL)

        if let existing = try await database.getObject(byHash: hash) {
            for tagName in tags {
                let tag = try await database.getOrCreateTag(name: tagName)
                try await database.addTag(tag.id, toObject: existing.id)
            }
            return existing
        }

        let objectName = name ?? sourceURL.deletingPathExtension().lastPathComponent

        let objectId = try await database.insertObject(hash: hash, name: objectName)

        let ext = sourceURL.pathExtension
        if !ext.isEmpty {
            try await database.setMetadata(objectId: objectId, key: "extension", value: ext)
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
           let size = attrs[.size] as? UInt64
        {
            try await database.setMetadata(objectId: objectId, key: "size_bytes", value: String(size))
        }

        if let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType {
            try await database.setMetadata(objectId: objectId, key: "mime_type", value: mimeType)
        }

        for tagName in tags {
            let tag = try await database.getOrCreateTag(name: tagName)
            try await database.addTag(tag.id, toObject: objectId)
        }

        guard let object = try await database.getObject(byId: objectId) else {
            throw DatabaseError.notFound
        }
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

        if newHash == existing.hash {
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
        return newObject
    }
}
