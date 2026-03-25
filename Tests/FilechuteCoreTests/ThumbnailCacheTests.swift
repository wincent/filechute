import AppKit
import Foundation
import Testing

@testable import FilechuteCore

private func sampleHash(_ n: Int = 1) -> ContentHash {
  ContentHash(hexString: String(repeating: String(format: "%02x", n), count: 32))
}

private func makePNGData() -> Data {
  let bitmapRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1,
    pixelsHigh: 1,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 4,
    bitsPerPixel: 32
  )!
  return bitmapRep.representation(using: .png, properties: [:])!
}

@Suite("ThumbnailCache")
struct ThumbnailCacheTests {
  @Test("Cache miss returns nil for nonexistent file")
  func cacheMissNonexistent() {
    let cache = ThumbnailCache()

    let hash = sampleHash(200)
    let url = URL(fileURLWithPath: "/tmp/nonexistent-thumbnail-\(UUID().uuidString).png")
    let result = cache.image(for: hash, at: url)
    #expect(result == nil)
  }

  @Test("Cache hit returns image for existing file")
  func cacheHit() throws {
    let cache = ThumbnailCache()

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filechute-thumb-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let pngData = makePNGData()
    let thumbURL = dir.appendingPathComponent("thumb.png")
    try pngData.write(to: thumbURL)

    let hash = sampleHash(201)
    let result1 = cache.image(for: hash, at: thumbURL)
    #expect(result1 != nil)

    // Second call should return cached version (even if we deleted the file)
    try FileManager.default.removeItem(at: thumbURL)
    let result2 = cache.image(for: hash, at: thumbURL)
    #expect(result2 != nil)
  }

  @Test("Invalidate removes specific hash from cache")
  func invalidateSpecific() throws {
    let cache = ThumbnailCache()

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filechute-thumb-inv-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let pngData = makePNGData()
    let thumbURL = dir.appendingPathComponent("thumb.png")
    try pngData.write(to: thumbURL)

    let hash = sampleHash(202)
    _ = cache.image(for: hash, at: thumbURL)

    // Remove the file, then invalidate the cache entry
    try FileManager.default.removeItem(at: thumbURL)
    cache.invalidate(hash)

    // Now it should return nil (no file and no cache)
    let result = cache.image(for: hash, at: thumbURL)
    #expect(result == nil)
  }

  @Test("InvalidateAll clears entire cache")
  func invalidateAll() throws {
    let cache = ThumbnailCache()

    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filechute-thumb-all-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let pngData = makePNGData()
    let url1 = dir.appendingPathComponent("t1.png")
    let url2 = dir.appendingPathComponent("t2.png")
    try pngData.write(to: url1)
    try pngData.write(to: url2)

    let h1 = sampleHash(203)
    let h2 = sampleHash(204)
    _ = cache.image(for: h1, at: url1)
    _ = cache.image(for: h2, at: url2)

    // Delete files, then clear cache
    try FileManager.default.removeItem(at: url1)
    try FileManager.default.removeItem(at: url2)
    cache.invalidateAll()

    #expect(cache.image(for: h1, at: url1) == nil)
    #expect(cache.image(for: h2, at: url2) == nil)
  }
}
