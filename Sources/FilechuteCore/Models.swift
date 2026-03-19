import Foundation

public struct StoredObject: Identifiable, Sendable, Hashable {
    public let id: Int64
    public let hash: ContentHash
    public let name: String
    public let createdAt: Date
    public let deletedAt: Date?

    public init(id: Int64, hash: ContentHash, name: String, createdAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.hash = hash
        self.name = name
        self.createdAt = createdAt
        self.deletedAt = deletedAt
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
