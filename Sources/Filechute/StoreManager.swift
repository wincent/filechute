import AppKit
import FilechuteCore
import Foundation

@Observable
@MainActor
final class StoreManager {
    private(set) var objects: [StoredObject] = []
    private(set) var allTags: [TagCount] = []
    private(set) var deletedObjects: [StoredObject] = []

    nonisolated let objectStore: ObjectStore
    nonisolated let database: Database
    nonisolated let ingestionService: IngestionService
    nonisolated let fileAccessService: FileAccessService
    nonisolated let garbageCollector: GarbageCollector

    nonisolated init(storeRoot: URL) throws {
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
    }

    func refresh() async throws {
        objects = try await database.allObjects()
        allTags = try await database.allTagsWithCounts()
        deletedObjects = try await database.allObjects(includeDeleted: true)
            .filter { $0.deletedAt != nil }
    }

    func ingest(urls: [URL]) async throws {
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
        try await refresh()
    }

    func removeTag(_ tagId: Int64, from objectId: Int64) async throws {
        try await database.removeTag(tagId, fromObject: objectId)
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

    func renameObject(_ objectId: Int64, to name: String) async throws {
        try await database.renameObject(id: objectId, newName: name)
        try await refresh()
    }

    func fileExtension(for object: StoredObject) async -> String? {
        if let ext = try? await database.getMetadata(objectId: object.id, key: "extension"), !ext.isEmpty {
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

    func openObject(_ object: StoredObject) async throws {
        let url = try await temporaryCopyURL(for: object)
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
        for obj in deletedObjects {
            try? objectStore.remove(obj.hash)
            try await database.permanentlyDeleteObject(id: obj.id)
        }
        try await refresh()
    }
}
