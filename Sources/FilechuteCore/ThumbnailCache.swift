import AppKit

public final class ThumbnailCache: @unchecked Sendable {
  public static let shared = ThumbnailCache()

  private let cache = NSCache<NSString, NSImage>()

  private init() {
    cache.countLimit = 500
  }

  public func image(for hash: ContentHash, at url: URL) -> NSImage? {
    let key = hash.hexString as NSString
    if let cached = cache.object(forKey: key) {
      return cached
    }
    guard FileManager.default.fileExists(atPath: url.path),
      let image = NSImage(contentsOf: url)
    else {
      return nil
    }
    cache.setObject(image, forKey: key)
    return image
  }

  public func invalidate(_ hash: ContentHash) {
    cache.removeObject(forKey: hash.hexString as NSString)
  }

  public func invalidateAll() {
    cache.removeAllObjects()
  }
}
