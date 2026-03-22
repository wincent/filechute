import Foundation
import Testing

@testable import FilechuteCore

private func makeDB() throws -> Database {
  try Database(path: ":memory:")
}

private func sampleHash(_ n: Int = 1) -> ContentHash {
  ContentHash(hexString: String(repeating: String(format: "%02x", n), count: 32))
}

@Suite("Database - Objects")
struct DatabaseObjectTests {
  @Test("Insert and retrieve object by ID")
  func insertAndGetById() async throws {
    let db = try makeDB()
    let hash = sampleHash(1)
    let id = try await db.insertObject(hash: hash, name: "test.pdf")

    let obj = try await db.getObject(byId: id)
    #expect(obj != nil)
    #expect(obj?.hash == hash)
    #expect(obj?.name == "test.pdf")
    #expect(obj?.deletedAt == nil)
  }

  @Test("Retrieve object by hash")
  func getByHash() async throws {
    let db = try makeDB()
    let hash = sampleHash(2)
    _ = try await db.insertObject(hash: hash, name: "doc.pdf")

    let obj = try await db.getObject(byHash: hash)
    #expect(obj != nil)
    #expect(obj?.name == "doc.pdf")
  }

  @Test("List all non-deleted objects")
  func allObjects() async throws {
    let db = try makeDB()
    _ = try await db.insertObject(hash: sampleHash(1), name: "a.pdf")
    _ = try await db.insertObject(hash: sampleHash(2), name: "b.pdf")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "c.pdf")
    try await db.softDeleteObject(id: id3)

    let objects = try await db.allObjects()
    #expect(objects.count == 2)

    let all = try await db.allObjects(includeDeleted: true)
    #expect(all.count == 3)
  }

  @Test("Soft delete and restore")
  func softDeleteAndRestore() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "test.pdf")

    try await db.softDeleteObject(id: id)
    let deleted = try await db.getObject(byId: id)
    #expect(deleted?.deletedAt != nil)

    try await db.restoreObject(id: id)
    let restored = try await db.getObject(byId: id)
    #expect(restored?.deletedAt == nil)
  }

  @Test("Permanent delete removes object and cascades")
  func permanentDelete() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "test.pdf")
    let tag = try await db.getOrCreateTag(name: "important")
    try await db.addTag(tag.id, toObject: id)
    try await db.setMetadata(objectId: id, key: "color", value: "red")

    try await db.permanentlyDeleteObject(id: id)

    #expect(try await db.getObject(byId: id) == nil)
    #expect(try await db.tags(forObject: id).isEmpty)
    #expect(try await db.allMetadata(for: id).isEmpty)
  }

  @Test("Rename object")
  func rename() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "old name")
    try await db.renameObject(id: id, newName: "new name")

    let obj = try await db.getObject(byId: id)
    #expect(obj?.name == "new name")
  }

  @Test("Duplicate hash rejected")
  func duplicateHash() async throws {
    let db = try makeDB()
    let hash = sampleHash(1)
    _ = try await db.insertObject(hash: hash, name: "first")

    await #expect(throws: DatabaseError.self) {
      try await db.insertObject(hash: hash, name: "second")
    }
  }

  @Test("Rename records history")
  func renameHistory() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "original")
    try await db.renameObject(id: id, newName: "renamed")
    try await db.renameObject(id: id, newName: "final")

    let history = try await db.renameHistory(for: id)
    #expect(history.count == 2)
    #expect(history[0].oldName == "renamed")
    #expect(history[0].newName == "final")
    #expect(history[1].oldName == "original")
    #expect(history[1].newName == "renamed")
  }

  @Test("Rename updates modified_at")
  func renameUpdatesModifiedAt() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "test")
    let before = try await db.getObject(byId: id)

    try await Task.sleep(for: .seconds(1))
    try await db.renameObject(id: id, newName: "renamed")
    let after = try await db.getObject(byId: id)

    #expect(after!.modifiedAt! > before!.modifiedAt!)
  }

  @Test("touchModified updates timestamp")
  func touchModified() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "test")
    let before = try await db.getObject(byId: id)

    try await Task.sleep(for: .seconds(1))
    try await db.touchModified(id: id)
    let after = try await db.getObject(byId: id)

    #expect(after!.modifiedAt! > before!.modifiedAt!)
  }

  @Test("touchLastOpened updates timestamp")
  func touchLastOpened() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "test")
    let before = try await db.getObject(byId: id)
    #expect(before!.lastOpenedAt == nil)

    try await db.touchLastOpened(id: id)
    let after = try await db.getObject(byId: id)
    #expect(after!.lastOpenedAt != nil)
  }

  @Test("File extension stored on insert")
  func fileExtensionOnInsert() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "doc", fileExtension: "pdf")
    let obj = try await db.getObject(byId: id)
    #expect(obj!.fileExtension == "pdf")
  }

  @Test("File extension defaults to empty string")
  func fileExtensionDefault() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "readme")
    let obj = try await db.getObject(byId: id)
    #expect(obj!.fileExtension == "")
  }

  @Test("fileTypeDisplay uses UTType localized description")
  func fileTypeDisplay() {
    let obj = StoredObject(
      id: 1, hash: sampleHash(1), name: "doc", createdAt: Date(), fileExtension: "pdf")
    #expect(obj.fileTypeDisplay == "PDF document")

    let jpg = StoredObject(
      id: 2, hash: sampleHash(2), name: "photo", createdAt: Date(), fileExtension: "jpg")
    let jpeg = StoredObject(
      id: 3, hash: sampleHash(3), name: "photo", createdAt: Date(), fileExtension: "jpeg")
    #expect(jpg.fileTypeDisplay == jpeg.fileTypeDisplay)

    let noExt = StoredObject(id: 4, hash: sampleHash(4), name: "readme", createdAt: Date())
    #expect(noExt.fileTypeDisplay == "")

    let unknown = StoredObject(
      id: 5, hash: sampleHash(5), name: "data", createdAt: Date(), fileExtension: "zzz123")
    #expect(unknown.fileTypeDisplay == "ZZZ123")
  }

  @Test("effectiveModifiedAt falls back to createdAt")
  func effectiveModifiedAt() {
    let now = Date()
    let obj = StoredObject(id: 1, hash: sampleHash(1), name: "test", createdAt: now)
    #expect(obj.effectiveModifiedAt == now)
    #expect(obj.modifiedAt == nil)
  }

  @Test("effectiveLastOpenedAt falls back to distantPast")
  func effectiveLastOpenedAt() {
    let obj = StoredObject(id: 1, hash: sampleHash(1), name: "test", createdAt: Date())
    #expect(obj.effectiveLastOpenedAt == .distantPast)
    #expect(obj.lastOpenedAt == nil)
  }
}

@Suite("Database - Tags")
struct DatabaseTagTests {
  @Test("Create and retrieve tag")
  func createAndGet() async throws {
    let db = try makeDB()
    let id = try await db.createTag(name: "finance")
    let tag = try await db.getTag(byId: id)

    #expect(tag != nil)
    #expect(tag?.name == "finance")
  }

  @Test("Get tag by name")
  func getByName() async throws {
    let db = try makeDB()
    _ = try await db.createTag(name: "tax")
    let tag = try await db.getTag(byName: "tax")
    #expect(tag != nil)
  }

  @Test("Tags are case-insensitive")
  func caseInsensitive() async throws {
    let db = try makeDB()
    _ = try await db.createTag(name: "Finance")
    let tag = try await db.getTag(byName: "finance")
    #expect(tag != nil)

    let tag2 = try await db.getTag(byName: "FINANCE")
    #expect(tag2 != nil)
    #expect(tag?.id == tag2?.id)
  }

  @Test("getOrCreateTag returns existing")
  func getOrCreateExisting() async throws {
    let db = try makeDB()
    let id = try await db.createTag(name: "docs")
    let tag = try await db.getOrCreateTag(name: "docs")
    #expect(tag.id == id)
  }

  @Test("getOrCreateTag creates new")
  func getOrCreateNew() async throws {
    let db = try makeDB()
    let tag = try await db.getOrCreateTag(name: "newTag")
    #expect(tag.name == "newTag")

    let fetched = try await db.getTag(byName: "newTag")
    #expect(fetched?.id == tag.id)
  }

  @Test("List all tags alphabetically")
  func allTags() async throws {
    let db = try makeDB()
    _ = try await db.createTag(name: "zebra")
    _ = try await db.createTag(name: "alpha")
    _ = try await db.createTag(name: "mid")

    let tags = try await db.allTags()
    #expect(tags.count == 3)
    #expect(tags[0].name == "alpha")
    #expect(tags[1].name == "mid")
    #expect(tags[2].name == "zebra")
  }

  @Test("Delete tag")
  func deleteTag() async throws {
    let db = try makeDB()
    let id = try await db.createTag(name: "temp")
    try await db.deleteTag(id: id)

    #expect(try await db.getTag(byId: id) == nil)
  }
}

@Suite("Database - Taggings")
struct DatabaseTaggingTests {
  @Test("Add tag to object and retrieve")
  func addAndRetrieve() async throws {
    let db = try makeDB()
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc")
    let tag = try await db.getOrCreateTag(name: "important")

    try await db.addTag(tag.id, toObject: objId)

    let tags = try await db.tags(forObject: objId)
    #expect(tags.count == 1)
    #expect(tags[0].name == "important")
  }

  @Test("Remove tag from object")
  func removeTag() async throws {
    let db = try makeDB()
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc")
    let tag = try await db.getOrCreateTag(name: "temp")

    try await db.addTag(tag.id, toObject: objId)
    try await db.removeTag(tag.id, fromObject: objId)

    let tags = try await db.tags(forObject: objId)
    #expect(tags.isEmpty)
  }

  @Test("Duplicate tagging is ignored")
  func duplicateTagging() async throws {
    let db = try makeDB()
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc")
    let tag = try await db.getOrCreateTag(name: "tag1")

    try await db.addTag(tag.id, toObject: objId)
    try await db.addTag(tag.id, toObject: objId)

    let tags = try await db.tags(forObject: objId)
    #expect(tags.count == 1)
  }

  @Test("Multiple tags on one object")
  func multipleTags() async throws {
    let db = try makeDB()
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc")
    let t1 = try await db.getOrCreateTag(name: "alpha")
    let t2 = try await db.getOrCreateTag(name: "beta")
    let t3 = try await db.getOrCreateTag(name: "gamma")

    try await db.addTag(t1.id, toObject: objId)
    try await db.addTag(t2.id, toObject: objId)
    try await db.addTag(t3.id, toObject: objId)

    let tags = try await db.tags(forObject: objId)
    #expect(tags.count == 3)
    #expect(tags.map(\.name) == ["alpha", "beta", "gamma"])
  }
}

@Suite("Database - Search")
struct DatabaseSearchTests {
  @Test("Find objects with a single tag")
  func singleTag() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b")
    _ = try await db.insertObject(hash: sampleHash(3), name: "c")

    let tag = try await db.getOrCreateTag(name: "foo")
    try await db.addTag(tag.id, toObject: id1)
    try await db.addTag(tag.id, toObject: id2)

    let results = try await db.objects(withTagId: tag.id)
    #expect(results.count == 2)
  }

  @Test("Find objects with multiple tags (AND)")
  func multipleTags() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "c")

    let foo = try await db.getOrCreateTag(name: "foo")
    let bar = try await db.getOrCreateTag(name: "bar")

    try await db.addTag(foo.id, toObject: id1)
    try await db.addTag(foo.id, toObject: id2)
    try await db.addTag(bar.id, toObject: id2)
    try await db.addTag(bar.id, toObject: id3)

    let results = try await db.objects(withAllTagIds: [foo.id, bar.id])
    #expect(results.count == 1)
    #expect(results[0].name == "b")
  }

  @Test("Empty tag list returns all objects")
  func emptyTagList() async throws {
    let db = try makeDB()
    _ = try await db.insertObject(hash: sampleHash(1), name: "a")
    _ = try await db.insertObject(hash: sampleHash(2), name: "b")

    let results = try await db.objects(withAllTagIds: [])
    #expect(results.count == 2)
  }

  @Test("Deleted objects excluded from search")
  func deletedExcluded() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b")
    let tag = try await db.getOrCreateTag(name: "shared")
    try await db.addTag(tag.id, toObject: id1)
    try await db.addTag(tag.id, toObject: id2)

    try await db.softDeleteObject(id: id1)

    let results = try await db.objects(withTagId: tag.id)
    #expect(results.count == 1)
    #expect(results[0].name == "b")
  }

  @Test("Reachable tags from one tag")
  func reachableFromOne() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b")

    let foo = try await db.getOrCreateTag(name: "foo")
    let bar = try await db.getOrCreateTag(name: "bar")
    let baz = try await db.getOrCreateTag(name: "baz")

    try await db.addTag(foo.id, toObject: id1)
    try await db.addTag(bar.id, toObject: id1)
    try await db.addTag(foo.id, toObject: id2)
    try await db.addTag(baz.id, toObject: id2)

    let reachable = try await db.reachableTags(from: [foo.id])
    let names = reachable.map(\.tag.name)
    #expect(names.contains("bar"))
    #expect(names.contains("baz"))
    #expect(!names.contains("foo"))
  }

  @Test("Reachable tags from multiple tags")
  func reachableFromMultiple() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a")
    _ = try await db.insertObject(hash: sampleHash(2), name: "b")

    let foo = try await db.getOrCreateTag(name: "foo")
    let bar = try await db.getOrCreateTag(name: "bar")
    let baz = try await db.getOrCreateTag(name: "baz")

    try await db.addTag(foo.id, toObject: id1)
    try await db.addTag(bar.id, toObject: id1)
    try await db.addTag(baz.id, toObject: id1)

    let reachable = try await db.reachableTags(from: [foo.id, bar.id])
    #expect(reachable.count == 1)
    #expect(reachable[0].tag.name == "baz")
  }

  @Test("Tag counts reflect non-deleted objects")
  func tagCounts() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "c")

    let tag = try await db.getOrCreateTag(name: "shared")
    try await db.addTag(tag.id, toObject: id1)
    try await db.addTag(tag.id, toObject: id2)
    try await db.addTag(tag.id, toObject: id3)

    try await db.softDeleteObject(id: id3)

    let counts = try await db.allTagsWithCounts()
    let sharedCount = counts.first { $0.tag.name == "shared" }
    #expect(sharedCount?.count == 2)
  }
}

@Suite("Database - Metadata")
struct DatabaseMetadataTests {
  @Test("Set and get metadata")
  func setAndGet() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "doc")

    try await db.setMetadata(objectId: id, key: "color", value: "blue")
    let value = try await db.getMetadata(objectId: id, key: "color")
    #expect(value == "blue")
  }

  @Test("Get non-existent metadata returns nil")
  func getNonExistent() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "doc")
    let value = try await db.getMetadata(objectId: id, key: "missing")
    #expect(value == nil)
  }

  @Test("Overwrite metadata")
  func overwrite() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "doc")

    try await db.setMetadata(objectId: id, key: "status", value: "draft")
    try await db.setMetadata(objectId: id, key: "status", value: "final")

    let value = try await db.getMetadata(objectId: id, key: "status")
    #expect(value == "final")
  }

  @Test("All metadata for object")
  func allMetadata() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "doc")

    try await db.setMetadata(objectId: id, key: "ext", value: "pdf")
    try await db.setMetadata(objectId: id, key: "size", value: "1024")

    let metadata = try await db.allMetadata(for: id)
    #expect(metadata.count == 2)
    #expect(metadata[0].key == "ext")
    #expect(metadata[1].key == "size")
  }

  @Test("Null metadata value")
  func nullValue() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "doc")

    try await db.setMetadata(objectId: id, key: "note", value: nil)
    let value = try await db.getMetadata(objectId: id, key: "note")
    #expect(value == nil)
  }

  @Test("allExtensions returns extension metadata by object")
  func allExtensions() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "doc")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "photo")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "readme")

    try await db.setMetadata(objectId: id1, key: "extension", value: "pdf")
    try await db.setMetadata(objectId: id2, key: "extension", value: "jpg")
    try await db.setMetadata(objectId: id3, key: "size", value: "100")

    let extensions = try await db.allExtensions()
    #expect(extensions.count == 2)
    #expect(extensions[id1] == "pdf")
    #expect(extensions[id2] == "jpg")
    #expect(extensions[id3] == nil)
  }
}

@Suite("Database - Versions")
struct DatabaseVersionTests {
  @Test("Version history tracks predecessors")
  func versionHistory() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "v1")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "v2")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "v3")

    try await db.addVersion(objectId: id2, previousObjectId: id1)
    try await db.addVersion(objectId: id3, previousObjectId: id2)

    let history = try await db.versionHistory(for: id3)
    #expect(history.count == 2)
    #expect(history[0].name == "v2")
    #expect(history[1].name == "v1")
  }

  @Test("Latest version follows chain forward")
  func latestVersion() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "v1")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "v2")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "v3")

    try await db.addVersion(objectId: id2, previousObjectId: id1)
    try await db.addVersion(objectId: id3, previousObjectId: id2)

    let latest = try await db.latestVersion(of: id1)
    #expect(latest?.name == "v3")
  }

  @Test("Latest version of head returns nil")
  func latestOfHead() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "v1")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "v2")

    try await db.addVersion(objectId: id2, previousObjectId: id1)

    let latest = try await db.latestVersion(of: id2)
    #expect(latest == nil)
  }

  @Test("Empty version history")
  func emptyHistory() async throws {
    let db = try makeDB()
    let id = try await db.insertObject(hash: sampleHash(1), name: "standalone")

    let history = try await db.versionHistory(for: id)
    #expect(history.isEmpty)
  }
}

@Suite("Database - Tag names by object")
struct DatabaseTagNamesByObjectTests {
  @Test("allTagNamesByObject returns tag names grouped by object ID")
  func tagNamesByObject() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "c")

    let t1 = try await db.getOrCreateTag(name: "alpha")
    let t2 = try await db.getOrCreateTag(name: "beta")
    let t3 = try await db.getOrCreateTag(name: "gamma")

    try await db.addTag(t1.id, toObject: id1)
    try await db.addTag(t2.id, toObject: id1)
    try await db.addTag(t3.id, toObject: id2)

    let result = try await db.allTagNamesByObject()
    #expect(result[id1] == ["alpha", "beta"])
    #expect(result[id2] == ["gamma"])
    #expect(result[id3] == nil)
  }

  @Test("allTagNamesByObject returns empty dictionary when no taggings")
  func emptyTagNamesByObject() async throws {
    let db = try makeDB()
    _ = try await db.insertObject(hash: sampleHash(1), name: "untagged")

    let result = try await db.allTagNamesByObject()
    #expect(result.isEmpty)
  }
}

@Suite("Database - Bulk tagging")
struct DatabaseBulkTaggingTests {
  @Test("Add same tag to multiple objects")
  func addTagToMultiple() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a.pdf")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b.pdf")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "c.pdf")
    let tag = try await db.getOrCreateTag(name: "important")

    for id in [id1, id2, id3] {
      try await db.addTag(tag.id, toObject: id)
    }

    let names = try await db.allTagNamesByObject()
    #expect(names[id1]?.contains("important") == true)
    #expect(names[id2]?.contains("important") == true)
    #expect(names[id3]?.contains("important") == true)
  }

  @Test("Remove tag from multiple objects")
  func removeTagFromMultiple() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a.pdf")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b.pdf")
    let tag = try await db.getOrCreateTag(name: "temp")

    try await db.addTag(tag.id, toObject: id1)
    try await db.addTag(tag.id, toObject: id2)

    for id in [id1, id2] {
      try await db.removeTag(tag.id, fromObject: id)
    }

    let names = try await db.allTagNamesByObject()
    #expect(names[id1]?.contains("temp") != true)
    #expect(names[id2]?.contains("temp") != true)
  }

  @Test("Tag counts update after bulk add and remove")
  func tagCountsAfterBulk() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a.pdf")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b.pdf")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "c.pdf")
    let tag = try await db.getOrCreateTag(name: "bulk")

    for id in [id1, id2, id3] {
      try await db.addTag(tag.id, toObject: id)
    }

    let counts = try await db.allTagsWithCounts()
    let bulkCount = counts.first { $0.tag.name == "bulk" }
    #expect(bulkCount?.count == 3)

    try await db.removeTag(tag.id, fromObject: id3)
    let updated = try await db.allTagsWithCounts()
    let newCount = updated.first { $0.tag.name == "bulk" }
    #expect(newCount?.count == 2)
  }

  @Test("Partial tag application reflected in tag names by object")
  func partialTagApplication() async throws {
    let db = try makeDB()
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a.pdf")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b.pdf")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "c.pdf")
    let tag = try await db.getOrCreateTag(name: "partial")

    try await db.addTag(tag.id, toObject: id1)
    try await db.addTag(tag.id, toObject: id3)

    let names = try await db.allTagNamesByObject()
    #expect(names[id1]?.contains("partial") == true)
    #expect(names[id2]?.contains("partial") != true)
    #expect(names[id3]?.contains("partial") == true)
  }
}
