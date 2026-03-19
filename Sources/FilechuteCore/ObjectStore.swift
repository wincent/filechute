import Foundation

public struct ObjectStore: Sendable {
    public let rootDirectory: URL

    public var objectsDirectory: URL {
        rootDirectory.appendingPathComponent("objects")
    }

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        try FileManager.default.createDirectory(
            at: rootDirectory.appendingPathComponent("objects"),
            withIntermediateDirectories: true
        )
    }

    public func store(fileAt sourceURL: URL) throws -> (hash: ContentHash, isNew: Bool) {
        let contentHash = try ContentHash.compute(fromFileAt: sourceURL)

        if exists(contentHash) {
            return (contentHash, false)
        }

        let objectURL = url(for: contentHash)
        let directoryURL = objectURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: objectURL)
        } catch {
            throw ObjectStoreError.writeFailed(objectURL, underlying: error)
        }

        return (contentHash, true)
    }

    public func store(data: Data) throws -> (hash: ContentHash, isNew: Bool) {
        let contentHash = ContentHash.compute(from: data)

        if exists(contentHash) {
            return (contentHash, false)
        }

        let objectURL = url(for: contentHash)
        let directoryURL = objectURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        do {
            try data.write(to: objectURL)
        } catch {
            throw ObjectStoreError.writeFailed(objectURL, underlying: error)
        }

        return (contentHash, true)
    }

    public func url(for hash: ContentHash) -> URL {
        objectsDirectory
            .appendingPathComponent(hash.prefix)
            .appendingPathComponent(hash.suffix)
    }

    public func exists(_ hash: ContentHash) -> Bool {
        FileManager.default.fileExists(atPath: url(for: hash).path)
    }

    public func read(_ hash: ContentHash) throws -> Data {
        let objectURL = url(for: hash)
        guard FileManager.default.fileExists(atPath: objectURL.path) else {
            throw ObjectStoreError.objectNotFound(hash)
        }
        return try Data(contentsOf: objectURL)
    }

    public func verify(_ hash: ContentHash) throws -> Bool {
        let data = try read(hash)
        let actual = ContentHash.compute(from: data)
        return actual == hash
    }

    public func remove(_ hash: ContentHash) throws {
        let objectURL = url(for: hash)
        guard FileManager.default.fileExists(atPath: objectURL.path) else {
            throw ObjectStoreError.objectNotFound(hash)
        }
        try FileManager.default.removeItem(at: objectURL)
    }
}
