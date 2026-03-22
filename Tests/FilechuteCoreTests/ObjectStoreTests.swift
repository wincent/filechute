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
      let expectedDir =
        dir
        .appendingPathComponent("objects")
        .appendingPathComponent(hash.prefix)
        .appendingPathComponent(hash.suffix)
      let expectedFile = expectedDir.appendingPathComponent("data.bin")

      var isDir: ObjCBool = false
      #expect(FileManager.default.fileExists(atPath: expectedDir.path, isDirectory: &isDir))
      #expect(isDir.boolValue)
      #expect(FileManager.default.fileExists(atPath: expectedFile.path))
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

  @Test("File-based deduplication returns isNew=false for same content")
  func fileDeduplication() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let file1 = try createTempFile(in: dir, name: "a.txt", contents: "same")
      let file2 = try createTempFile(in: dir, name: "b.txt", contents: "same")

      let (hash1, isNew1) = try store.store(fileAt: file1)
      let (hash2, isNew2) = try store.store(fileAt: file2)

      #expect(isNew1)
      #expect(!isNew2)
      #expect(hash1 == hash2)
    }
  }

  @Test("Verify returns false for corrupted object")
  func verifyCorrupted() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("original content".utf8)

      let (hash, _) = try store.store(data: data)
      try Data("tampered".utf8).write(to: store.dataURL(for: hash))

      #expect(try !store.verify(hash))
    }
  }

  @Test("ContentHash description returns hex string")
  func contentHashDescription() {
    let hex = "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
    let hash = ContentHash(hexString: hex)
    #expect(hash.description == hex)
    #expect("\(hash)" == hex)
  }

  @Test("dataURL points to data.bin inside object directory")
  func dataURLPath() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("test".utf8)
      let (hash, _) = try store.store(data: data)

      let dataURL = store.dataURL(for: hash)
      #expect(dataURL.lastPathComponent == "data.bin")
      #expect(dataURL.deletingLastPathComponent() == store.url(for: hash))
      #expect(FileManager.default.fileExists(atPath: dataURL.path))
    }
  }

  @Test("thumbnailURL points to thumbnail.png inside object directory")
  func thumbnailURLPath() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("test".utf8)
      let (hash, _) = try store.store(data: data)

      let thumbURL = store.thumbnailURL(for: hash)
      #expect(thumbURL.lastPathComponent == "thumbnail.png")
      #expect(thumbURL.deletingLastPathComponent() == store.url(for: hash))
    }
  }

  @Test("Store and read thumbnail")
  func storeThumbnail() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("object data".utf8)
      let (hash, _) = try store.store(data: data)

      #expect(!store.thumbnailExists(for: hash))

      let thumbData = Data("fake png".utf8)
      try store.storeThumbnail(data: thumbData, for: hash)

      #expect(store.thumbnailExists(for: hash))
      let readBack = try store.readThumbnail(for: hash)
      #expect(readBack == thumbData)
    }
  }

  @Test("thumbnailExists returns false when no thumbnail stored")
  func thumbnailNotExists() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("no thumb".utf8)
      let (hash, _) = try store.store(data: data)

      #expect(!store.thumbnailExists(for: hash))
    }
  }

  @Test("readThumbnail throws for missing thumbnail")
  func readThumbnailMissing() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("no thumb".utf8)
      let (hash, _) = try store.store(data: data)

      #expect(throws: ObjectStoreError.self) {
        try store.readThumbnail(for: hash)
      }
    }
  }

  @Test("Remove deletes thumbnail along with data")
  func removeDeletesThumbnail() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("with thumb".utf8)
      let (hash, _) = try store.store(data: data)
      try store.storeThumbnail(data: Data("thumb".utf8), for: hash)

      #expect(store.exists(hash))
      #expect(store.thumbnailExists(for: hash))

      try store.remove(hash)
      #expect(!store.exists(hash))
      #expect(!store.thumbnailExists(for: hash))
      #expect(!FileManager.default.fileExists(atPath: store.url(for: hash).path))
    }
  }

  @Test("infoURL points to info.json inside object directory")
  func infoURLPath() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("test".utf8)
      let (hash, _) = try store.store(data: data)

      let infoURL = store.infoURL(for: hash)
      #expect(infoURL.lastPathComponent == "info.json")
      #expect(infoURL.deletingLastPathComponent() == store.url(for: hash))
    }
  }

  @Test("Store and check info existence")
  func storeInfo() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("object data".utf8)
      let (hash, _) = try store.store(data: data)

      #expect(!store.infoExists(for: hash))

      let infoData = Data("{\"test\": true}".utf8)
      try store.storeInfo(infoData, for: hash)

      #expect(store.infoExists(for: hash))
      let onDisk = try Data(contentsOf: store.infoURL(for: hash))
      #expect(onDisk == infoData)
    }
  }

  @Test("Remove deletes info.json along with data")
  func removeDeletesInfo() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let data = Data("with info".utf8)
      let (hash, _) = try store.store(data: data)
      try store.storeInfo(Data("{}".utf8), for: hash)

      #expect(store.infoExists(for: hash))
      try store.remove(hash)
      #expect(!store.infoExists(for: hash))
    }
  }

  @Test("Store from file creates directory with data.bin")
  func storeFileCreatesDirectory() throws {
    try withTempDir { dir in
      let store = try ObjectStore(rootDirectory: dir)
      let fileURL = try createTempFile(in: dir, name: "doc.txt", contents: "hello")
      let (hash, _) = try store.store(fileAt: fileURL)

      var isDir: ObjCBool = false
      FileManager.default.fileExists(
        atPath: store.url(for: hash).path, isDirectory: &isDir
      )
      #expect(isDir.boolValue)
      #expect(FileManager.default.fileExists(atPath: store.dataURL(for: hash).path))
    }
  }
}
