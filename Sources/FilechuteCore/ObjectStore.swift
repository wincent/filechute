import Foundation

public struct ObjectStore: Sendable {
  public let rootDirectory: URL

  public var objectsDirectory: URL {
    rootDirectory.appendingPathComponent("objects")
  }

  public init(rootDirectory: URL) throws {
    self.rootDirectory = rootDirectory
    try FileManager.default.createDirectory(
      at: rootDirectory.appendingPathComponent("objects"),
      withIntermediateDirectories: true
    )
  }

  public func store(fileAt sourceURL: URL) throws -> (hash: ContentHash, isNew: Bool) {
    let contentHash = try ContentHash.compute(fromFileAt: sourceURL)

    if exists(contentHash) {
      return (contentHash, false)
    }

    let objectDir = url(for: contentHash)
    try FileManager.default.createDirectory(at: objectDir, withIntermediateDirectories: true)

    do {
      try FileManager.default.copyItem(at: sourceURL, to: dataURL(for: contentHash))
    } catch {
      throw ObjectStoreError.writeFailed(objectDir, underlying: error)
    }

    Log.debug(
      "Stored \(sourceURL.lastPathComponent) (\(contentHash.hexString.prefix(8)))",
      category: .objectStore
    )
    return (contentHash, true)
  }

  public func store(data: Data) throws -> (hash: ContentHash, isNew: Bool) {
    let contentHash = ContentHash.compute(from: data)

    if exists(contentHash) {
      return (contentHash, false)
    }

    let objectDir = url(for: contentHash)
    try FileManager.default.createDirectory(at: objectDir, withIntermediateDirectories: true)

    do {
      try data.write(to: dataURL(for: contentHash))
    } catch {
      throw ObjectStoreError.writeFailed(objectDir, underlying: error)
    }

    return (contentHash, true)
  }

  public func url(for hash: ContentHash) -> URL {
    objectsDirectory
      .appendingPathComponent(hash.prefix)
      .appendingPathComponent(hash.suffix)
  }

  public func dataURL(for hash: ContentHash) -> URL {
    url(for: hash).appendingPathComponent("data.bin")
  }

  public func thumbnailURL(for hash: ContentHash) -> URL {
    url(for: hash).appendingPathComponent("thumbnail.png")
  }

  public func infoURL(for hash: ContentHash) -> URL {
    url(for: hash).appendingPathComponent("info.json")
  }

  public func exists(_ hash: ContentHash) -> Bool {
    FileManager.default.fileExists(atPath: dataURL(for: hash).path)
  }

  public func read(_ hash: ContentHash) throws -> Data {
    let fileURL = dataURL(for: hash)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw ObjectStoreError.objectNotFound(hash)
    }
    return try Data(contentsOf: fileURL)
  }

  public func verify(_ hash: ContentHash) throws -> Bool {
    let data = try read(hash)
    let actual = ContentHash.compute(from: data)
    return actual == hash
  }

  public func remove(_ hash: ContentHash) throws {
    let objectDir = url(for: hash)
    guard FileManager.default.fileExists(atPath: objectDir.path) else {
      throw ObjectStoreError.objectNotFound(hash)
    }
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: objectDir.path
    )
    try FileManager.default.removeItem(at: objectDir)
    Log.debug("Removed blob \(hash.hexString.prefix(8))", category: .objectStore)
  }

  public func storeThumbnail(data: Data, for hash: ContentHash) throws {
    let thumbURL = thumbnailURL(for: hash)
    try data.write(to: thumbURL)
  }

  public func thumbnailExists(for hash: ContentHash) -> Bool {
    FileManager.default.fileExists(atPath: thumbnailURL(for: hash).path)
  }

  public func readThumbnail(for hash: ContentHash) throws -> Data {
    let thumbURL = thumbnailURL(for: hash)
    guard FileManager.default.fileExists(atPath: thumbURL.path) else {
      throw ObjectStoreError.objectNotFound(hash)
    }
    return try Data(contentsOf: thumbURL)
  }

  public func setReadOnly(for hash: ContentHash) throws {
    let objectDir = url(for: hash)
    let fm = FileManager.default
    let contents = try fm.contentsOfDirectory(
      at: objectDir,
      includingPropertiesForKeys: nil
    )
    for fileURL in contents {
      try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fileURL.path)
    }
    try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: objectDir.path)
  }

  public func setWritable(for hash: ContentHash) throws {
    let objectDir = url(for: hash)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: objectDir.path
    )
  }

  public func storeInfo(_ data: Data, for hash: ContentHash) throws {
    try data.write(to: infoURL(for: hash))
  }

  public func infoExists(for hash: ContentHash) -> Bool {
    FileManager.default.fileExists(atPath: infoURL(for: hash).path)
  }
}
