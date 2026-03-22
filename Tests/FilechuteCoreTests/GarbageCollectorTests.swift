import Foundation
import Testing

@testable import FilechuteCore

private func withTestEnv<T>(_ body: (ObjectStore, Database, GarbageCollector) async throws -> T)
  async throws -> T
{
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("filechute-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let store = try ObjectStore(rootDirectory: dir)
  let db = try Database(path: ":memory:")
  let gc = GarbageCollector(objectStore: store, database: db)

  return try await body(store, db, gc)
}

@Suite("GarbageCollector")
struct GarbageCollectorTests {
  @Test("Collects tombstoned objects older than cutoff")
  func collectsOldTombstones() async throws {
    try await withTestEnv { store, db, gc in
      let data = Data("garbage".utf8)
      let (hash, _) = try store.store(data: data)
      let id = try await db.insertObject(hash: hash, name: "old")
      try await db.softDeleteObject(id: id)

      let collected = try await gc.collectGarbage(olderThan: Date.distantFuture)
      #expect(collected == 1)
      #expect(!store.exists(hash))
      #expect(try await db.getObject(byId: id) == nil)
    }
  }

  @Test("Does not collect objects newer than cutoff")
  func skipsNewTombstones() async throws {
    try await withTestEnv { store, db, gc in
      let data = Data("recent".utf8)
      let (hash, _) = try store.store(data: data)
      let id = try await db.insertObject(hash: hash, name: "recent")
      try await db.softDeleteObject(id: id)

      let collected = try await gc.collectGarbage(olderThan: Date.distantPast)
      #expect(collected == 0)
      #expect(store.exists(hash))
    }
  }

  @Test("Does not collect objects referenced by version chains")
  func preservesVersionedObjects() async throws {
    try await withTestEnv { store, db, gc in
      let data1 = Data("v1".utf8)
      let (hash1, _) = try store.store(data: data1)
      let id1 = try await db.insertObject(hash: hash1, name: "doc-v1")

      let data2 = Data("v2".utf8)
      let (hash2, _) = try store.store(data: data2)
      let id2 = try await db.insertObject(hash: hash2, name: "doc-v2")
      try await db.addVersion(objectId: id2, previousObjectId: id1)

      try await db.softDeleteObject(id: id1)

      let collected = try await gc.collectGarbage(olderThan: Date.distantFuture)
      #expect(collected == 0)
      #expect(store.exists(hash1))
    }
  }

  @Test("Does not collect non-deleted objects")
  func skipsLiveObjects() async throws {
    try await withTestEnv { store, db, gc in
      let data = Data("alive".utf8)
      let (hash, _) = try store.store(data: data)
      _ = try await db.insertObject(hash: hash, name: "alive")

      let collected = try await gc.collectGarbage(olderThan: Date.distantFuture)
      #expect(collected == 0)
      #expect(store.exists(hash))
    }
  }

  @Test("Collects multiple tombstoned objects at once")
  func collectsMultiple() async throws {
    try await withTestEnv { store, db, gc in
      var hashes: [ContentHash] = []
      for i in 0..<3 {
        let data = Data("garbage-\(i)".utf8)
        let (hash, _) = try store.store(data: data)
        let id = try await db.insertObject(hash: hash, name: "old-\(i)")
        try await db.softDeleteObject(id: id)
        hashes.append(hash)
      }

      let liveData = Data("keep me".utf8)
      let (liveHash, _) = try store.store(data: liveData)
      _ = try await db.insertObject(hash: liveHash, name: "alive")

      let collected = try await gc.collectGarbage(olderThan: Date.distantFuture)
      #expect(collected == 3)
      for hash in hashes {
        #expect(!store.exists(hash))
      }
      #expect(store.exists(liveHash))
    }
  }

  @Test("Does not collect deleted object that is a successor in a version chain")
  func preservesSuccessorInChain() async throws {
    try await withTestEnv { store, db, gc in
      let data1 = Data("v1".utf8)
      let (hash1, _) = try store.store(data: data1)
      let id1 = try await db.insertObject(hash: hash1, name: "doc-v1")

      let data2 = Data("v2".utf8)
      let (hash2, _) = try store.store(data: data2)
      let id2 = try await db.insertObject(hash: hash2, name: "doc-v2")
      try await db.addVersion(objectId: id2, previousObjectId: id1)

      try await db.softDeleteObject(id: id2)

      let collected = try await gc.collectGarbage(olderThan: Date.distantFuture)
      #expect(collected == 0)
      #expect(store.exists(hash2))
    }
  }
}
