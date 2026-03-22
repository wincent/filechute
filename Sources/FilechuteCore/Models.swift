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

  public var effectiveModifiedAt: Date { modifiedAt ?? createdAt }
  public var effectiveLastOpenedAt: Date { lastOpenedAt ?? .distantPast }
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
    fileExtension: String = ""
  ) {
    self.id = id
    self.hash = hash
    self.name = name
    self.createdAt = createdAt
    self.deletedAt = deletedAt
    self.modifiedAt = modifiedAt
    self.lastOpenedAt = lastOpenedAt
    self.fileExtension = fileExtension
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
