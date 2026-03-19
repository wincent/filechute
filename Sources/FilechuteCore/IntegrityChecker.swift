import Foundation

public struct IntegrityReport: Sendable {
    public var corruptedObjects: [(hash: ContentHash, reason: String)] = []
    public var orphanedBlobs: [String] = []
    public var danglingReferences: [(objectId: Int64, hash: ContentHash)] = []
    public var objectsChecked: Int = 0
    public var blobsScanned: Int = 0

    public var isClean: Bool {
        corruptedObjects.isEmpty && orphanedBlobs.isEmpty && danglingReferences.isEmpty
    }
}

public struct IntegrityChecker: Sendable {
    public let objectStore: ObjectStore
    public let database: Database

    public init(objectStore: ObjectStore, database: Database) {
        self.objectStore = objectStore
        self.database = database
    }

    public func check() async throws -> IntegrityReport {
        var report = IntegrityReport()

        let allObjects = try await database.allObjects(includeDeleted: true)
        report.objectsChecked = allObjects.count

        for object in allObjects {
            if !objectStore.exists(object.hash) {
                report.danglingReferences.append((objectId: object.id, hash: object.hash))
                continue
            }

            do {
                let valid = try objectStore.verify(object.hash)
                if !valid {
                    report.corruptedObjects.append((hash: object.hash, reason: "Hash mismatch"))
                }
            } catch {
                report.corruptedObjects.append((hash: object.hash, reason: error.localizedDescription))
            }
        }

        let knownHashes = Set(allObjects.map(\.hash.hexString))
        let objectsDir = objectStore.objectsDirectory

        let fm = FileManager.default
        if let prefixes = try? fm.contentsOfDirectory(atPath: objectsDir.path) {
            for prefix in prefixes {
                let prefixDir = objectsDir.appendingPathComponent(prefix)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: prefixDir.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                if let suffixes = try? fm.contentsOfDirectory(atPath: prefixDir.path) {
                    for suffix in suffixes {
                        report.blobsScanned += 1
                        let fullHash = prefix + suffix
                        if !knownHashes.contains(fullHash) {
                            report.orphanedBlobs.append(fullHash)
                        }
                    }
                }
            }
        }

        return report
    }

    public func repair(report: IntegrityReport) throws -> Int {
        var removed = 0
        for blob in report.orphanedBlobs {
            let hash = ContentHash(hexString: blob)
            try? objectStore.remove(hash)
            removed += 1
        }
        return removed
    }
}
