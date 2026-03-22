import Foundation
import UniformTypeIdentifiers

public struct StoredObject: Identifiable, Sendable, Hashable {
  public let id: Int64
  public let hash: ContentHash
  public let name: String
  public let createdAt: Date
  public let deletedAt: Date?
  public let modifiedAt: Date?
  public let lastOpenedAt: Date?
  public let fileExtension: String
  public let notes: String?
  public var sizeBytes: UInt64

  public var effectiveModifiedAt: Date { modifiedAt ?? createdAt }
  public var effectiveLastOpenedAt: Date { lastOpenedAt ?? .distantPast }
  public var effectiveDeletedAt: Date { deletedAt ?? .distantPast }
  public var fileTypeDisplay: String {
    UTType(filenameExtension: fileExtension)?.localizedDescription ?? fileExtension.uppercased()
  }

  public init(
    id: Int64,
    hash: ContentHash,
    name: String,
    createdAt: Date,
    deletedAt: Date? = nil,
    modifiedAt: Date? = nil,
    lastOpenedAt: Date? = nil,
    fileExtension: String = "",
    notes: String? = nil,
    sizeBytes: UInt64 = 0
  ) {
    self.id = id
    self.hash = hash
    self.name = name
    self.createdAt = createdAt
    self.deletedAt = deletedAt
    self.modifiedAt = modifiedAt
    self.lastOpenedAt = lastOpenedAt
    self.fileExtension = fileExtension
    self.notes = notes
    self.sizeBytes = sizeBytes
  }
}

public struct Tag: Identifiable, Sendable, Hashable {
  public let id: Int64
  public let name: String

  public init(id: Int64, name: String) {
    self.id = id
    self.name = name
  }
}

public struct TagCount: Sendable, Hashable {
  public let tag: Tag
  public let count: Int

  public init(tag: Tag, count: Int) {
    self.tag = tag
    self.count = count
  }
}

public struct RenameEntry: Identifiable, Sendable, Hashable {
  public let id: String
  public let oldName: String
  public let newName: String
  public let date: Date

  public init(oldName: String, newName: String, date: Date) {
    self.id = "\(oldName)-\(newName)-\(date.timeIntervalSince1970)"
    self.oldName = oldName
    self.newName = newName
    self.date = date
  }
}

public enum TagApplyState: Sendable, Hashable {
  case none
  case some
  case all
}

public enum BulkTagState {
  public static func compute(
    tagName: String,
    selectedObjectIds: Set<Int64>,
    tagNamesByObject: [Int64: [String]]
  ) -> TagApplyState {
    let count = selectedObjectIds.count
    guard count > 0 else { return .none }
    var matched = 0
    for objectId in selectedObjectIds {
      let names = tagNamesByObject[objectId] ?? []
      if names.contains(where: { $0.caseInsensitiveCompare(tagName) == .orderedSame }) {
        matched += 1
      }
    }
    if matched == 0 { return .none }
    if matched == count { return .all }
    return .some
  }
}

public struct ObjectInfo: Codable, Sendable {
  public let originalName: String
  public let importDate: Date
  public let contentHash: String
  public let sizeBytes: UInt64
  public let mimeType: String?

  public init(
    originalName: String,
    importDate: Date,
    contentHash: String,
    sizeBytes: UInt64,
    mimeType: String?
  ) {
    self.originalName = originalName
    self.importDate = importDate
    self.contentHash = contentHash
    self.sizeBytes = sizeBytes
    self.mimeType = mimeType
  }

  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()
}

public struct ObjectMetadata: Sendable, Hashable {
  public let objectId: Int64
  public let key: String
  public let value: String?

  public init(objectId: Int64, key: String, value: String?) {
    self.objectId = objectId
    self.key = key
    self.value = value
  }
}
