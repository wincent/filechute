import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import FilechuteCore

private func withTestStore<T>(_ body: (ObjectStore, ThumbnailService) async throws -> T)
  async throws -> T
{
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("filechute-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let store = try ObjectStore(rootDirectory: dir)
  let service = ThumbnailService(objectStore: store)

  return try await body(store, service)
}

private func createTempImage(in dir: URL, name: String) throws -> URL {
  let size = 64
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  guard
    let context = CGContext(
      data: nil,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw TestError(message: "Failed to create CGContext")
  }

  context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: size, height: size))

  guard let cgImage = context.makeImage() else {
    throw TestError(message: "Failed to make CGImage")
  }

  let url = dir.appendingPathComponent(name)
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, "public.png" as CFString, 1, nil
    )
  else {
    throw TestError(message: "Failed to create image destination")
  }
  CGImageDestinationAddImage(destination, cgImage, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw TestError(message: "Failed to write PNG")
  }

  return url
}

private struct TestError: Error {
  let message: String
}

@Suite("ThumbnailService")
struct ThumbnailServiceTests {
  @Test("Generates thumbnail for PNG image")
  func generateForImage() async throws {
    try await withTestStore { store, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-thumb-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let imageURL = try createTempImage(in: dir, name: "test.png")
      let (hash, _) = try store.store(fileAt: imageURL)

      #expect(!store.thumbnailExists(for: hash))
      await service.generateThumbnail(for: imageURL, hash: hash)
      #expect(store.thumbnailExists(for: hash))

      let thumbData = try store.readThumbnail(for: hash)
      #expect(!thumbData.isEmpty)
    }
  }

  @Test("Skips generation when thumbnail already exists")
  func skipsExisting() async throws {
    try await withTestStore { store, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-thumb-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let imageURL = try createTempImage(in: dir, name: "test.png")
      let (hash, _) = try store.store(fileAt: imageURL)

      let sentinel = Data("existing thumbnail".utf8)
      try store.storeThumbnail(data: sentinel, for: hash)

      await service.generateThumbnail(for: imageURL, hash: hash)

      let thumbData = try store.readThumbnail(for: hash)
      #expect(thumbData == sentinel)
    }
  }

  @Test("Does not throw for unsupported file type")
  func unsupportedType() async throws {
    try await withTestStore { store, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-thumb-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let fileURL = dir.appendingPathComponent("random.xyz123")
      try Data("not a real file type".utf8).write(to: fileURL)
      let (hash, _) = try store.store(fileAt: fileURL)

      await service.generateThumbnail(for: fileURL, hash: hash)
      // Should not crash; thumbnail may or may not exist depending on OS
    }
  }

  @Test("Backfill generates thumbnail from stored data")
  func backfillFromStore() async throws {
    try await withTestStore { store, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-thumb-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let imageURL = try createTempImage(in: dir, name: "backfill.png")
      let (hash, _) = try store.store(fileAt: imageURL)

      #expect(!store.thumbnailExists(for: hash))
      await service.generateThumbnailFromStore(hash: hash, fileExtension: "png")
      #expect(store.thumbnailExists(for: hash))
    }
  }

  @Test("Backfill skips when thumbnail already exists")
  func backfillSkipsExisting() async throws {
    try await withTestStore { store, service in
      let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("filechute-thumb-test-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: dir) }

      let imageURL = try createTempImage(in: dir, name: "backfill.png")
      let (hash, _) = try store.store(fileAt: imageURL)

      let sentinel = Data("pre-existing".utf8)
      try store.storeThumbnail(data: sentinel, for: hash)

      await service.generateThumbnailFromStore(hash: hash, fileExtension: "png")

      let thumbData = try store.readThumbnail(for: hash)
      #expect(thumbData == sentinel)
    }
  }

  @Test("Backfill does nothing for missing object")
  func backfillMissingObject() async throws {
    try await withTestStore { store, service in
      let fakeHash = ContentHash(
        hexString: "0000000000000000000000000000000000000000000000000000000000000000"
      )

      await service.generateThumbnailFromStore(hash: fakeHash, fileExtension: "png")
      #expect(!store.thumbnailExists(for: fakeHash))
    }
  }
}
