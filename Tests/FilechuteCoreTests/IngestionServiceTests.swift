import Foundation
import Testing

@testable import FilechuteCore

private func withTestStore<T>(_ body: (ObjectStore, Database, IngestionService) async throws -> T)
  async throws -> T
{
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("filechute-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let store = try ObjectStore(rootDirectory: dir)
  let db = try Database(path: ":memory:")
  let service = IngestionService(objectStore: store, database: db)

  return try await body(store, db, service)
}

private func createTempFile(in dir: URL, name: String, contents: String) throws -> URL {
  let fileURL = dir.appendingPathComponent(name)
  try contents.write(to: fileURL, atomically: true, encoding: .utf8)
  return fileURL
}

@Suite("IngestionService")
struct IngestionServiceTests {
  @Test("Basic ingestion creates object with metadata")
  func basicIngestion() async throws {
    try await withTestStore { store, db, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "report.pdf", contents: "pdf content")
      let obj = try await service.ingest(fileAt: fileURL)

      #expect(obj.name == "report")
      #expect(store.exists(obj.hash))

      let ext = try await db.getMetadata(objectId: obj.id, key: "extension")
      #expect(ext == "pdf")

      let size = try await db.getMetadata(objectId: obj.id, key: "size_bytes")
      #expect(size != nil)
    }
  }

  @Test("Ingestion with tags")
  func ingestionWithTags() async throws {
    try await withTestStore { _, db, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "tax.pdf", contents: "tax data")
      let obj = try await service.ingest(fileAt: fileURL, tags: ["tax", "2024", "w-2"])

      let tags = try await db.tags(forObject: obj.id)
      #expect(tags.count == 3)
      let names = Set(tags.map(\.name))
      #expect(names.contains("tax"))
      #expect(names.contains("2024"))
      #expect(names.contains("w-2"))
    }
  }

  @Test("Ingestion with custom name")
  func customName() async throws {
    try await withTestStore { _, _, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "967164278.pdf", contents: "bank stuff")
      let obj = try await service.ingest(fileAt: fileURL, name: "January Statement")

      #expect(obj.name == "January Statement")
    }
  }

  @Test("Duplicate ingestion returns existing object and adds new tags")
  func duplicateIngestion() async throws {
    try await withTestStore { _, db, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "doc.txt", contents: "same content")
      let obj1 = try await service.ingest(fileAt: fileURL, tags: ["first"])

      let fileURL2 = try createTempFile(in: dir, name: "doc2.txt", contents: "same content")
      let obj2 = try await service.ingest(fileAt: fileURL2, tags: ["second"])

      #expect(obj1.id == obj2.id)

      let tags = try await db.tags(forObject: obj1.id)
      #expect(tags.count == 2)
    }
  }

  @Test("Update creates new version linked to old")
  func updateCreatesVersion() async throws {
    try await withTestStore { store, db, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "doc.txt", contents: "version 1")
      let v1 = try await service.ingest(fileAt: fileURL, tags: ["draft"])

      let updatedURL = try createTempFile(in: dir, name: "doc-v2.txt", contents: "version 2")
      let v2 = try await service.update(objectId: v1.id, withFileAt: updatedURL)

      #expect(v2.id != v1.id)
      #expect(v2.hash != v1.hash)
      #expect(v2.name == v1.name)
      #expect(store.exists(v1.hash))
      #expect(store.exists(v2.hash))

      let history = try await db.versionHistory(for: v2.id)
      #expect(history.count == 1)
      #expect(history[0].id == v1.id)

      let v2Tags = try await db.tags(forObject: v2.id)
      #expect(v2Tags.count == 1)
      #expect(v2Tags[0].name == "draft")
    }
  }

  @Test("Update with same content returns existing")
  func updateSameContent() async throws {
    try await withTestStore { _, _, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "doc.txt", contents: "unchanged")
      let v1 = try await service.ingest(fileAt: fileURL)

      let sameURL = try createTempFile(in: dir, name: "doc-copy.txt", contents: "unchanged")
      let v2 = try await service.update(objectId: v1.id, withFileAt: sameURL)

      #expect(v2.id == v1.id)
    }
  }

  @Test("Update with non-existent object throws")
  func updateNonExistent() async throws {
    try await withTestStore { _, _, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "new.txt", contents: "data")

      await #expect(throws: DatabaseError.self) {
        try await service.update(objectId: 99999, withFileAt: fileURL)
      }
    }
  }

  @Test("Ingestion writes info.json with correct metadata")
  func writesInfoJson() async throws {
    try await withTestStore { store, _, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "photo.jpg", contents: "jpeg data")
      let obj = try await service.ingest(fileAt: fileURL)

      #expect(store.infoExists(for: obj.hash))

      let infoData = try Data(contentsOf: store.infoURL(for: obj.hash))
      let json = try JSONSerialization.jsonObject(with: infoData) as! [String: Any]
      #expect(json["original_name"] as? String == "photo.jpg")
      #expect(json["content_hash"] as? String == "sha256:\(obj.hash.hexString)")
      #expect(json["mime_type"] as? String == "image/jpeg")
      #expect(json["size_bytes"] as? Int != nil)
      #expect(json["import_date"] as? String != nil)
    }
  }

  @Test("info.json does not escape forward slashes")
  func infoJsonNoEscapedSlashes() async throws {
    try await withTestStore { store, _, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "photo.jpg", contents: "jpeg data")
      let obj = try await service.ingest(fileAt: fileURL)

      let raw = try String(contentsOf: store.infoURL(for: obj.hash), encoding: .utf8)
      #expect(raw.contains("image/jpeg"))
      #expect(!raw.contains("\\/"))
    }
  }

  @Test("Duplicate ingestion does not overwrite info.json")
  func duplicateDoesNotOverwriteInfo() async throws {
    try await withTestStore { store, _, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let file1 = try createTempFile(in: dir, name: "first.txt", contents: "same content")
      _ = try await service.ingest(fileAt: file1)

      let infoData1 = try Data(
        contentsOf: store.infoURL(
          for: ContentHash.compute(from: Data("same content".utf8))
        ))

      let file2 = try createTempFile(in: dir, name: "second.txt", contents: "same content")
      _ = try await service.ingest(fileAt: file2)

      let infoData2 = try Data(
        contentsOf: store.infoURL(
          for: ContentHash.compute(from: Data("same content".utf8))
        ))

      #expect(infoData1 == infoData2)
      let json = try JSONSerialization.jsonObject(with: infoData2) as! [String: Any]
      #expect(json["original_name"] as? String == "first.txt")
    }
  }

  @Test("Update writes info.json for new version")
  func updateWritesInfo() async throws {
    try await withTestStore { store, _, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "doc.txt", contents: "version 1")
      let v1 = try await service.ingest(fileAt: fileURL)

      let updatedURL = try createTempFile(in: dir, name: "doc-v2.txt", contents: "version 2")
      let v2 = try await service.update(objectId: v1.id, withFileAt: updatedURL)

      #expect(store.infoExists(for: v2.hash))
      let infoData = try Data(contentsOf: store.infoURL(for: v2.hash))
      let json = try JSONSerialization.jsonObject(with: infoData) as! [String: Any]
      #expect(json["original_name"] as? String == "doc-v2.txt")
    }
  }

  @Test("Ingestion of file without extension")
  func noExtension() async throws {
    try await withTestStore { _, db, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "Makefile", contents: "all: build")
      let obj = try await service.ingest(fileAt: fileURL)

      #expect(obj.name == "Makefile")
      let ext = try await db.getMetadata(objectId: obj.id, key: "extension")
      #expect(ext == nil)
    }
  }

  @Test("Ingestion stores file extension on object record")
  func storesFileExtension() async throws {
    try await withTestStore { _, db, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-ingest-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = try createTempFile(in: dir, name: "image.png", contents: "png data")
      let obj = try await service.ingest(fileAt: fileURL)

      #expect(obj.fileExtension == "png")
      let fetched = try await db.getObject(byId: obj.id)
      #expect(fetched?.fileExtension == "png")
    }
  }
}
