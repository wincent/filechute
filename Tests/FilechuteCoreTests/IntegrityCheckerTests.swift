import Foundation
import Testing

@testable import FilechuteCore

private func withTestEnv<T>(_ body: (ObjectStore, Database, IntegrityChecker) async throws -> T)
  async throws -> T
{
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("filechute-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let store = try ObjectStore(rootDirectory: dir)
  let db = try Database(path: dir.appendingPathComponent("test.db").path)
  let checker = IntegrityChecker(objectStore: store, database: db)

  return try await body(store, db, checker)
}

@Suite("IntegrityChecker")
struct IntegrityCheckerTests {
  @Test("Clean store passes check")
  func cleanStore() async throws {
    try await withTestEnv { store, db, checker in
      let data = Data("hello".utf8)
      let (hash, _) = try store.store(data: data)
      _ = try await db.insertObject(hash: hash, name: "test.txt")

      let report = try await checker.check()
      #expect(report.isClean)
      #expect(report.objectsChecked == 1)
      #expect(report.blobsScanned == 1)
    }
  }

  @Test("Detects dangling reference when blob missing")
  func danglingReference() async throws {
    try await withTestEnv { store, db, checker in
      let hash = ContentHash(hexString: "aa" + String(repeating: "00", count: 31))
      _ = try await db.insertObject(hash: hash, name: "missing.txt")

      let report = try await checker.check()
      #expect(!report.isClean)
      #expect(report.danglingReferences.count == 1)
    }
  }

  @Test("Detects orphaned blob not in database")
  func orphanedBlob() async throws {
    try await withTestEnv { store, _, checker in
      let data = Data("orphan".utf8)
      let (_, _) = try store.store(data: data)

      let report = try await checker.check()
      #expect(!report.isClean)
      #expect(report.orphanedBlobs.count == 1)
    }
  }

  @Test("Repair removes orphaned blobs")
  func repairOrphans() async throws {
    try await withTestEnv { store, _, checker in
      let data = Data("orphan".utf8)
      let (hash, _) = try store.store(data: data)
      #expect(store.exists(hash))

      let report = try await checker.check()
      let removed = try checker.repair(report: report)
      #expect(removed == 1)
      #expect(!store.exists(hash))
    }
  }

  @Test("Detects corrupted object")
  func corruptedObject() async throws {
    try await withTestEnv { store, db, checker in
      let data = Data("original".utf8)
      let (hash, _) = try store.store(data: data)
      _ = try await db.insertObject(hash: hash, name: "test.txt")

      let objectURL = store.url(for: hash)
      try Data("tampered".utf8).write(to: objectURL)

      let report = try await checker.check()
      #expect(!report.isClean)
      #expect(report.corruptedObjects.count == 1)
    }
  }

  @Test("Empty store passes check")
  func emptyStore() async throws {
    try await withTestEnv { _, _, checker in
      let report = try await checker.check()
      #expect(report.isClean)
      #expect(report.objectsChecked == 0)
    }
  }

  @Test("Multiple objects all verified")
  func multipleObjects() async throws {
    try await withTestEnv { store, db, checker in
      for i in 0..<10 {
        let data = Data("file-\(i)".utf8)
        let (hash, _) = try store.store(data: data)
        _ = try await db.insertObject(hash: hash, name: "file-\(i).txt")
      }

      let report = try await checker.check()
      #expect(report.isClean)
      #expect(report.objectsChecked == 10)
      #expect(report.blobsScanned == 10)
    }
  }
}
