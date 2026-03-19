import Foundation
import Testing

@testable import FilechuteCore

private func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

@Suite("FileAccessService")
struct FileAccessServiceTests {
    @Test("Creates temporary copy with correct extension")
    func temporaryCopyWithExtension() throws {
        try withTempDir { dir in
            let store = try ObjectStore(rootDirectory: dir)
            let data = Data("test content".utf8)
            let (hash, _) = try store.store(data: data)

            let tmpDir = dir.appendingPathComponent("tmp")
            let service = try FileAccessService(objectStore: store, tmpDirectory: tmpDir)

            let url = try service.openTemporaryCopy(hash: hash, name: "report", extension: "pdf")
            #expect(url.pathExtension == "pdf")
            #expect(url.lastPathComponent == "report.pdf")

            let readBack = try Data(contentsOf: url)
            #expect(readBack == data)
        }
    }

    @Test("Handles name that already has extension")
    func nameWithExtension() throws {
        try withTempDir { dir in
            let store = try ObjectStore(rootDirectory: dir)
            let (hash, _) = try store.store(data: Data("x".utf8))
            let tmpDir = dir.appendingPathComponent("tmp")
            let service = try FileAccessService(objectStore: store, tmpDirectory: tmpDir)

            let url = try service.openTemporaryCopy(hash: hash, name: "report.pdf", extension: "pdf")
            #expect(url.lastPathComponent == "report.pdf")
        }
    }

    @Test("Handles nil extension")
    func nilExtension() throws {
        try withTempDir { dir in
            let store = try ObjectStore(rootDirectory: dir)
            let (hash, _) = try store.store(data: Data("x".utf8))
            let tmpDir = dir.appendingPathComponent("tmp")
            let service = try FileAccessService(objectStore: store, tmpDirectory: tmpDir)

            let url = try service.openTemporaryCopy(hash: hash, name: "readme", extension: nil)
            #expect(url.lastPathComponent == "readme")
        }
    }

    @Test("Sanitizes filename with special characters")
    func sanitizesFilename() throws {
        try withTempDir { dir in
            let store = try ObjectStore(rootDirectory: dir)
            let (hash, _) = try store.store(data: Data("x".utf8))
            let tmpDir = dir.appendingPathComponent("tmp")
            let service = try FileAccessService(objectStore: store, tmpDirectory: tmpDir)

            let url = try service.openTemporaryCopy(hash: hash, name: "path/to:file", extension: "txt")
            #expect(!url.lastPathComponent.contains("/"))
            #expect(!url.lastPathComponent.contains(":"))
        }
    }

    @Test("Overwrites existing temporary copy")
    func overwritesExisting() throws {
        try withTempDir { dir in
            let store = try ObjectStore(rootDirectory: dir)
            let (hash, _) = try store.store(data: Data("original".utf8))
            let tmpDir = dir.appendingPathComponent("tmp")
            let service = try FileAccessService(objectStore: store, tmpDirectory: tmpDir)

            let url1 = try service.openTemporaryCopy(hash: hash, name: "doc", extension: "txt")
            let url2 = try service.openTemporaryCopy(hash: hash, name: "doc", extension: "txt")

            #expect(url1 == url2)
            #expect(FileManager.default.fileExists(atPath: url2.path))
        }
    }
}
