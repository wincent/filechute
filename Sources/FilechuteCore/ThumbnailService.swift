import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

public struct ThumbnailService: Sendable {
  public let objectStore: ObjectStore

  public init(objectStore: ObjectStore) {
    self.objectStore = objectStore
  }

  public func generateThumbnail(for sourceURL: URL, hash: ContentHash) async {
    if objectStore.thumbnailExists(for: hash) {
      return
    }

    let request = QLThumbnailGenerator.Request(
      fileAt: sourceURL,
      size: CGSize(width: 1024, height: 1024),
      scale: 1.0,
      representationTypes: .all
    )

    do {
      let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
      guard let pngData = pngData(from: thumbnail.cgImage) else {
        Log.debug(
          "Failed to encode thumbnail as PNG (\(hash.hexString.prefix(8)))",
          category: .objectStore
        )
        return
      }
      try objectStore.storeThumbnail(data: pngData, for: hash)
      Log.debug("Generated thumbnail (\(hash.hexString.prefix(8)))", category: .objectStore)
    } catch {
      Log.debug(
        "Thumbnail generation failed for \(hash.hexString.prefix(8)): \(error.localizedDescription)",
        category: .objectStore
      )
    }
  }

  public func generateThumbnailFromStore(hash: ContentHash, fileExtension: String) async {
    if objectStore.thumbnailExists(for: hash) {
      return
    }

    let dataURL = objectStore.dataURL(for: hash)
    guard FileManager.default.fileExists(atPath: dataURL.path) else { return }

    let tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("filechute-thumb-\(hash.hexString.prefix(8))")
    let tmpFile = tmpDir.appendingPathComponent(
      fileExtension.isEmpty ? "file" : "file.\(fileExtension)"
    )

    do {
      try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: tmpFile.path) {
        try FileManager.default.removeItem(at: tmpFile)
      }
      try FileManager.default.createSymbolicLink(at: tmpFile, withDestinationURL: dataURL)
      await generateThumbnail(for: tmpFile, hash: hash)
      try? FileManager.default.removeItem(at: tmpDir)
    } catch {
      try? FileManager.default.removeItem(at: tmpDir)
      Log.debug(
        "Backfill thumbnail setup failed for \(hash.hexString.prefix(8)): \(error.localizedDescription)",
        category: .objectStore
      )
    }
  }

  private func pngData(from cgImage: CGImage) -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else {
      return nil
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return data as Data
  }
}
