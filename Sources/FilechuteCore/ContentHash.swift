import CryptoKit
import Foundation

public struct ContentHash: Hashable, Sendable, CustomStringConvertible, Codable {
  public let hexString: String

  public init(hexString: String) {
    self.hexString = hexString
  }

  public var prefix: String {
    String(hexString.prefix(2))
  }

  public var suffix: String {
    String(hexString.dropFirst(2))
  }

  public var description: String {
    hexString
  }

  public static func compute(from data: Data) -> ContentHash {
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return ContentHash(hexString: hex)
  }

  public static func compute(fromFileAt url: URL) throws -> ContentHash {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256()
    let chunkSize = 1_048_576
    while true {
      let chunk = handle.readData(ofLength: chunkSize)
      if chunk.isEmpty { break }
      hasher.update(data: chunk)
    }

    let digest = hasher.finalize()
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return ContentHash(hexString: hex)
  }
}
