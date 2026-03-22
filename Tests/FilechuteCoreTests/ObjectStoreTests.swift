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

private func createTempFile(in dir: URL, name: String, contents: String) throws -> URL {
  let fileURL = dir.appendingPathComponent(name)
  try contents.write(to: fileURL, atomically: true, encoding: .utf8)
  return fileURL
}

@Suite("ObjectStore")
struct ObjectStoreTests {
  @Test("Store data and read it back")
  func storeAndReadData() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("hello world".utf8)

      let (hash, isNew) = try store.store(data: data)
      #expect(isNew)
      #expect(store.exists(hash))

      let readBack = try store.read(hash)
      #expect(readBack == data)
    }
  }

  @Test("Deduplication returns isNew=false for same content")
  func deduplication() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("duplicate content".utf8)

      let (hash1, isNew1) = try store.store(data: data)
      let (hash2, isNew2) = try store.store(data: data)

      #expect(isNew1)
      #expect(!isNew2)
      #expect(hash1 == hash2)
    }
  }

  @Test("Store file from URL")
  func storeFile() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let fileURL = try createTempFile(in: dir, name: "test.txt", contents: "file content")

      let (hash, isNew) = try store.store(fileAt: fileURL)
      #expect(isNew)

      let readBack = try store.read(hash)
      #expect(String(data: readBack, encoding: .utf8) == "file content")
    }
  }

  @Test("Reading non-existent object throws")
  func readNonExistent() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let fakeHash = ContentHash(
        hexString: "0000000000000000000000000000000000000000000000000000000000000000")

      #expect(throws: ObjectStoreError.self) {
        try store.read(fakeHash)
      }
    }
  }

  @Test("Verify returns true for valid object")
  func verifyValid() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("verify me".utf8)

      let (hash, _) = try store.store(data: data)
      #expect(try store.verify(hash))
    }
  }

  @Test("Remove deletes object from store")
  func remove() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("remove me".utf8)

      let (hash, _) = try store.store(data: data)
      #expect(store.exists(hash))

      try store.remove(hash)
      #expect(!store.exists(hash))
    }
  }

  @Test("Remove non-existent object throws")
  func removeNonExistent() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let fakeHash = ContentHash(
        hexString: "0000000000000000000000000000000000000000000000000000000000000000")

      #expect(throws: ObjectStoreError.self) {
        try store.remove(fakeHash)
      }
    }
  }

  @Test("Zero-byte data")
  func zeroByte() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data()

      let (hash, isNew) = try store.store(data: data)
      #expect(isNew)

      let readBack = try store.read(hash)
      #expect(readBack.isEmpty)
    }
  }

  @Test("Content hash is deterministic")
  func hashDeterminism() {
    let data = Data("deterministic".utf8)
    let hash1 = ContentHash.compute(from: data)
    let hash2 = ContentHash.compute(from: data)
    #expect(hash1 == hash2)
  }

  @Test("Different content produces different hashes")
  func hashUniqueness() {
    let hash1 = ContentHash.compute(from: Data("aaa".utf8))
    let hash2 = ContentHash.compute(from: Data("bbb".utf8))
    #expect(hash1 != hash2)
  }

  @Test("Hash prefix and suffix split correctly")
  func hashPrefixSuffix() {
    let hash = ContentHash(
      hexString: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
    #expect(hash.prefix == "ab")
    #expect(hash.suffix == "cdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")
  }

  @Test("Object stored at expected path")
  func storagePath() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("path test".utf8)

      let (hash, _) = try store.store(data: data)
      let expectedURL =
        dir
        .appendingPathComponent("objects")
        .appendingPathComponent(hash.prefix)
        .appendingPathComponent(hash.suffix)

      #expect(FileManager.default.fileExists(atPath: expectedURL.path))
    }
  }

  @Test("File-based hash matches data-based hash for same content")
  func fileHashMatchesDataHash() throws {
    try withTempDir { dir in
      let content = "hash consistency"
      let data = Data(content.utf8)
      let fileURL = try createTempFile(in: dir, name: "hash-test.txt", contents: content)

      let dataHash = ContentHash.compute(from: data)
      let fileHash = try ContentHash.compute(fromFileAt: fileURL)

      #expect(dataHash == fileHash)
    }
  }
}
