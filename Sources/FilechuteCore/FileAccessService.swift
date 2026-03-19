import Foundation

public struct FileAccessService: Sendable {
    public let objectStore: ObjectStore
    public let tmpDirectory: URL

    public init(objectStore: ObjectStore, tmpDirectory: URL) throws {
        self.objectStore = objectStore
        self.tmpDirectory = tmpDirectory
        try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
    }

    public func openTemporaryCopy(
        hash: ContentHash,
        name: String,
        extension ext: String?
    ) throws -> URL {
        let data = try objectStore.read(hash)

        var filename = name
        if let ext, !ext.isEmpty, !name.hasSuffix(".\(ext)") {
            filename = "\(name).\(ext)"
        }

        let sanitized = filename
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")

        let dir = tmpDirectory.appendingPathComponent(hash.hexString.prefix(8).description)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent(sanitized)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try data.write(to: fileURL)

        return fileURL
    }

    public func cleanupTemporaryFiles() throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: tmpDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        )
        let cutoff = Date().addingTimeInterval(-86400)
        for item in contents {
            let values = try item.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, modified < cutoff {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }
}
