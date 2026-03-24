import Foundation
import Testing

@testable import FilechuteCore

private func makeDB() throws -> Database {
  try Database(path: ":memory:")
}

private func sampleHash(_ n: Int = 1) -> ContentHash {
  ContentHash(hexString: String(repeating: String(format: "%02x", n), count: 32))
}

@Suite("Database - Folders")
struct DatabaseFolderTests {
  @Test("Create folder at root")
  func createRootFolder() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Documents")

    #expect(folder.name == "Documents")
    #expect(folder.parentId == nil)
    #expect(folder.position == 0)
    #expect(folder.deletedAt == nil)
  }

  @Test("Create folder with parent")
  func createChildFolder() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Documents")
    let child = try await db.createFolder(name: "Tax", parentId: parent.id)

    #expect(child.parentId == parent.id)
    #expect(child.name == "Tax")
  }

  @Test("Create folder with explicit position")
  func createWithPosition() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "First", position: 5.0)

    #expect(folder.position == 5.0)
  }

  @Test("Get folder by ID")
  func getById() async throws {
    let db = try makeDB()
    let created = try await db.createFolder(name: "Photos")

    let fetched = try await db.getFolder(byId: created.id)
    #expect(fetched != nil)
    #expect(fetched?.name == "Photos")
    #expect(fetched?.id == created.id)
  }

  @Test("Get non-existent folder returns nil")
  func getNonExistent() async throws {
    let db = try makeDB()
    let folder = try await db.getFolder(byId: 9999)
    #expect(folder == nil)
  }

  @Test("List all non-deleted folders")
  func allFolders() async throws {
    let db = try makeDB()
    _ = try await db.createFolder(name: "A", position: 2)
    _ = try await db.createFolder(name: "B", position: 1)
    let c = try await db.createFolder(name: "C", position: 3)

    try await db.softDeleteFolder(id: c.id)

    let folders = try await db.allFolders()
    #expect(folders.count == 2)
    #expect(folders[0].name == "B")
    #expect(folders[1].name == "A")
  }

  @Test("Rename folder")
  func rename() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Old Name")

    try await db.renameFolder(id: folder.id, name: "New Name")

    let fetched = try await db.getFolder(byId: folder.id)
    #expect(fetched?.name == "New Name")
  }

  @Test("Move folder to different parent")
  func moveToParent() async throws {
    let db = try makeDB()
    let a = try await db.createFolder(name: "A")
    let b = try await db.createFolder(name: "B")

    try await db.moveFolder(id: b.id, parentId: a.id, position: 1.0)

    let fetched = try await db.getFolder(byId: b.id)
    #expect(fetched?.parentId == a.id)
    #expect(fetched?.position == 1.0)
  }

  @Test("Move folder to root")
  func moveToRoot() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    let child = try await db.createFolder(name: "Child", parentId: parent.id)

    try await db.moveFolder(id: child.id, parentId: nil, position: 0)

    let fetched = try await db.getFolder(byId: child.id)
    #expect(fetched?.parentId == nil)
  }

  @Test("Soft delete folder")
  func softDelete() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Trash Me")

    try await db.softDeleteFolder(id: folder.id)

    let fetched = try await db.getFolder(byId: folder.id)
    #expect(fetched?.deletedAt != nil)

    let all = try await db.allFolders()
    #expect(all.isEmpty)
  }

  @Test("Soft delete cascades to children")
  func softDeleteCascadesToChildren() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    let child = try await db.createFolder(name: "Child", parentId: parent.id)
    let grandchild = try await db.createFolder(name: "Grandchild", parentId: child.id)

    try await db.softDeleteFolder(id: parent.id)

    let fetchedChild = try await db.getFolder(byId: child.id)
    let fetchedGrandchild = try await db.getFolder(byId: grandchild.id)
    #expect(fetchedChild?.deletedAt != nil)
    #expect(fetchedGrandchild?.deletedAt != nil)

    let all = try await db.allFolders()
    #expect(all.isEmpty)
  }

  @Test("Restore folder")
  func restore() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Revive Me")

    try await db.softDeleteFolder(id: folder.id)
    try await db.restoreFolder(id: folder.id)

    let fetched = try await db.getFolder(byId: folder.id)
    #expect(fetched?.deletedAt == nil)

    let all = try await db.allFolders()
    #expect(all.count == 1)
  }

  @Test("Restore folder restores children")
  func restoreRestoresChildren() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    let child = try await db.createFolder(name: "Child", parentId: parent.id)

    try await db.softDeleteFolder(id: parent.id)
    try await db.restoreFolder(id: parent.id)

    let fetchedChild = try await db.getFolder(byId: child.id)
    #expect(fetchedChild?.deletedAt == nil)
  }
}

@Suite("Database - Folder Items")
struct DatabaseFolderItemTests {
  @Test("Add item to folder and retrieve")
  func addAndRetrieve() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Docs")
    let objId = try await db.insertObject(hash: sampleHash(1), name: "report.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: folder.id)

    let items = try await db.items(inFolder: folder.id)
    #expect(items.count == 1)
    #expect(items[0].name == "report.pdf")
  }

  @Test("Multiple items in folder")
  func multipleItems() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Docs")
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "a.pdf")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "b.pdf")
    let id3 = try await db.insertObject(hash: sampleHash(3), name: "c.pdf")

    try await db.addItemToFolder(objectId: id1, folderId: folder.id)
    try await db.addItemToFolder(objectId: id2, folderId: folder.id)
    try await db.addItemToFolder(objectId: id3, folderId: folder.id)

    let items = try await db.items(inFolder: folder.id)
    #expect(items.count == 3)
    #expect(items.map(\.name) == ["a.pdf", "b.pdf", "c.pdf"])
  }

  @Test("Remove item from folder")
  func removeItem() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Docs")
    let objId = try await db.insertObject(hash: sampleHash(1), name: "report.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: folder.id)
    try await db.removeItemFromFolder(objectId: objId, folderId: folder.id)

    let items = try await db.items(inFolder: folder.id)
    #expect(items.isEmpty)
  }

  @Test("Duplicate add is ignored")
  func duplicateAdd() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Docs")
    let objId = try await db.insertObject(hash: sampleHash(1), name: "report.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: folder.id)
    try await db.addItemToFolder(objectId: objId, folderId: folder.id)

    let items = try await db.items(inFolder: folder.id)
    #expect(items.count == 1)
  }

  @Test("Deleted objects excluded from folder items")
  func deletedObjectsExcluded() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Docs")
    let id1 = try await db.insertObject(hash: sampleHash(1), name: "keep.pdf")
    let id2 = try await db.insertObject(hash: sampleHash(2), name: "delete.pdf")

    try await db.addItemToFolder(objectId: id1, folderId: folder.id)
    try await db.addItemToFolder(objectId: id2, folderId: folder.id)
    try await db.softDeleteObject(id: id2)

    let items = try await db.items(inFolder: folder.id)
    #expect(items.count == 1)
    #expect(items[0].name == "keep.pdf")
  }

  @Test("Object in multiple folders")
  func objectInMultipleFolders() async throws {
    let db = try makeDB()
    let f1 = try await db.createFolder(name: "Work")
    let f2 = try await db.createFolder(name: "Archive")
    let objId = try await db.insertObject(hash: sampleHash(1), name: "shared.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: f1.id)
    try await db.addItemToFolder(objectId: objId, folderId: f2.id)

    let folders = try await db.folders(containingObject: objId)
    #expect(folders.count == 2)
    let names = folders.map(\.name)
    #expect(names.contains("Work"))
    #expect(names.contains("Archive"))
  }

  @Test("Folders containing object excludes deleted folders")
  func foldersContainingExcludesDeleted() async throws {
    let db = try makeDB()
    let f1 = try await db.createFolder(name: "Active")
    let f2 = try await db.createFolder(name: "Deleted")
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: f1.id)
    try await db.addItemToFolder(objectId: objId, folderId: f2.id)
    try await db.softDeleteFolder(id: f2.id)

    let folders = try await db.folders(containingObject: objId)
    #expect(folders.count == 1)
    #expect(folders[0].name == "Active")
  }

  @Test("Empty folder returns no items")
  func emptyFolder() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Empty")

    let items = try await db.items(inFolder: folder.id)
    #expect(items.isEmpty)
  }
}

@Suite("Database - Recursive Folder Items")
struct DatabaseRecursiveFolderTests {
  @Test("Items in folder non-recursive excludes child folder items")
  func nonRecursive() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    let child = try await db.createFolder(name: "Child", parentId: parent.id)
    let parentObj = try await db.insertObject(hash: sampleHash(1), name: "parent.pdf")
    let childObj = try await db.insertObject(hash: sampleHash(2), name: "child.pdf")

    try await db.addItemToFolder(objectId: parentObj, folderId: parent.id)
    try await db.addItemToFolder(objectId: childObj, folderId: child.id)

    let items = try await db.items(inFolder: parent.id)
    #expect(items.count == 1)
    #expect(items[0].name == "parent.pdf")
  }

  @Test("Items in folder recursive includes child folder items")
  func recursive() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    let child = try await db.createFolder(name: "Child", parentId: parent.id)
    let parentObj = try await db.insertObject(hash: sampleHash(1), name: "parent.pdf")
    let childObj = try await db.insertObject(hash: sampleHash(2), name: "child.pdf")

    try await db.addItemToFolder(objectId: parentObj, folderId: parent.id)
    try await db.addItemToFolder(objectId: childObj, folderId: child.id)

    let items = try await db.items(inFolder: parent.id, recursive: true)
    #expect(items.count == 2)
    let names = items.map(\.name)
    #expect(names.contains("parent.pdf"))
    #expect(names.contains("child.pdf"))
  }

  @Test("Recursive includes deeply nested items")
  func deeplyNested() async throws {
    let db = try makeDB()
    let root = try await db.createFolder(name: "Root")
    let mid = try await db.createFolder(name: "Mid", parentId: root.id)
    let leaf = try await db.createFolder(name: "Leaf", parentId: mid.id)

    let obj1 = try await db.insertObject(hash: sampleHash(1), name: "root.pdf")
    let obj2 = try await db.insertObject(hash: sampleHash(2), name: "mid.pdf")
    let obj3 = try await db.insertObject(hash: sampleHash(3), name: "leaf.pdf")

    try await db.addItemToFolder(objectId: obj1, folderId: root.id)
    try await db.addItemToFolder(objectId: obj2, folderId: mid.id)
    try await db.addItemToFolder(objectId: obj3, folderId: leaf.id)

    let items = try await db.items(inFolder: root.id, recursive: true)
    #expect(items.count == 3)
  }

  @Test("Recursive deduplicates objects in multiple subfolders")
  func recursiveDeduplicates() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    let child = try await db.createFolder(name: "Child", parentId: parent.id)
    let objId = try await db.insertObject(hash: sampleHash(1), name: "shared.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: parent.id)
    try await db.addItemToFolder(objectId: objId, folderId: child.id)

    let items = try await db.items(inFolder: parent.id, recursive: true)
    #expect(items.count == 1)
  }

  @Test("Recursive excludes deleted child folder items")
  func recursiveExcludesDeletedFolders() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    let child = try await db.createFolder(name: "Child", parentId: parent.id)
    let parentObj = try await db.insertObject(hash: sampleHash(1), name: "keep.pdf")
    let childObj = try await db.insertObject(hash: sampleHash(2), name: "in-deleted-folder.pdf")

    try await db.addItemToFolder(objectId: parentObj, folderId: parent.id)
    try await db.addItemToFolder(objectId: childObj, folderId: child.id)
    try await db.softDeleteFolder(id: child.id)

    let items = try await db.items(inFolder: parent.id, recursive: true)
    #expect(items.count == 1)
    #expect(items[0].name == "keep.pdf")
  }
}

@Suite("Database - Folder Positioning")
struct DatabaseFolderPositionTests {
  @Test("Max position at root with no folders")
  func maxPositionEmpty() async throws {
    let db = try makeDB()
    let max = try await db.maxFolderPosition(parentId: nil)
    #expect(max == 0)
  }

  @Test("Max position at root")
  func maxPositionRoot() async throws {
    let db = try makeDB()
    _ = try await db.createFolder(name: "A", position: 1.0)
    _ = try await db.createFolder(name: "B", position: 3.0)
    _ = try await db.createFolder(name: "C", position: 2.0)

    let max = try await db.maxFolderPosition(parentId: nil)
    #expect(max == 3.0)
  }

  @Test("Max position under specific parent")
  func maxPositionUnderParent() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    _ = try await db.createFolder(name: "A", parentId: parent.id, position: 10)
    _ = try await db.createFolder(name: "B", parentId: parent.id, position: 20)

    let max = try await db.maxFolderPosition(parentId: parent.id)
    #expect(max == 20.0)
  }

  @Test("Max position excludes deleted folders")
  func maxPositionExcludesDeleted() async throws {
    let db = try makeDB()
    _ = try await db.createFolder(name: "A", position: 1.0)
    let b = try await db.createFolder(name: "B", position: 5.0)

    try await db.softDeleteFolder(id: b.id)

    let max = try await db.maxFolderPosition(parentId: nil)
    #expect(max == 1.0)
  }

  @Test("Renumber positions at root")
  func renumberRoot() async throws {
    let db = try makeDB()
    _ = try await db.createFolder(name: "A", position: 10)
    _ = try await db.createFolder(name: "B", position: 50)
    _ = try await db.createFolder(name: "C", position: 100)

    try await db.renumberFolderPositions(parentId: nil)

    let folders = try await db.allFolders()
    #expect(folders.map(\.position) == [1.0, 2.0, 3.0])
    #expect(folders.map(\.name) == ["A", "B", "C"])
  }

  @Test("Renumber positions under parent")
  func renumberUnderParent() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    _ = try await db.createFolder(name: "X", parentId: parent.id, position: 0.5)
    _ = try await db.createFolder(name: "Y", parentId: parent.id, position: 0.75)

    try await db.renumberFolderPositions(parentId: parent.id)

    let all = try await db.allFolders()
    let children = all.filter { $0.parentId == parent.id }
    #expect(children.map(\.position) == [1.0, 2.0])
  }
}

@Suite("Database - Direct Folder ID")
struct DatabaseDirectFolderIdTests {
  @Test("Direct folder ID for object in root folder")
  func directInRoot() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Root")
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: folder.id)

    let folderId = try await db.directFolderIdForObject(objId, inSubtreeOf: folder.id)
    #expect(folderId == folder.id)
  }

  @Test("Direct folder ID for object in child folder")
  func directInChild() async throws {
    let db = try makeDB()
    let parent = try await db.createFolder(name: "Parent")
    let child = try await db.createFolder(name: "Child", parentId: parent.id)
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: child.id)

    let folderId = try await db.directFolderIdForObject(objId, inSubtreeOf: parent.id)
    #expect(folderId == child.id)
  }

  @Test("Direct folder ID returns nil when object not in subtree")
  func notInSubtree() async throws {
    let db = try makeDB()
    let folder = try await db.createFolder(name: "Folder")
    let other = try await db.createFolder(name: "Other")
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc.pdf")

    try await db.addItemToFolder(objectId: objId, folderId: other.id)

    let folderId = try await db.directFolderIdForObject(objId, inSubtreeOf: folder.id)
    #expect(folderId == nil)
  }
}

@Suite("Database - Tag deletion cascades")
struct DatabaseTagDeletionTests {
  @Test("Deleting tag removes it from tagged objects")
  func deleteCascadesToTaggings() async throws {
    let db = try makeDB()
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc.pdf")
    let tag = try await db.getOrCreateTag(name: "temp")
    try await db.addTag(tag.id, toObject: objId)

    try await db.deleteTag(id: tag.id)

    let tags = try await db.tags(forObject: objId)
    #expect(tags.isEmpty)
  }

  @Test("Deleting tag does not affect other tags on same object")
  func deleteDoesNotAffectOthers() async throws {
    let db = try makeDB()
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc.pdf")
    let keep = try await db.getOrCreateTag(name: "keep")
    let remove = try await db.getOrCreateTag(name: "remove")
    try await db.addTag(keep.id, toObject: objId)
    try await db.addTag(remove.id, toObject: objId)

    try await db.deleteTag(id: remove.id)

    let tags = try await db.tags(forObject: objId)
    #expect(tags.count == 1)
    #expect(tags[0].name == "keep")
  }

  @Test("Deleting tag removes it from tag counts")
  func deleteRemovesFromCounts() async throws {
    let db = try makeDB()
    let objId = try await db.insertObject(hash: sampleHash(1), name: "doc.pdf")
    let tag = try await db.getOrCreateTag(name: "doomed")
    try await db.addTag(tag.id, toObject: objId)

    try await db.deleteTag(id: tag.id)

    let counts = try await db.allTagsWithCounts()
    #expect(counts.first { $0.tag.name == "doomed" } == nil)
  }
}

@Suite("Database - Browser")
struct DatabaseBrowserTests {
  @Test("Table names includes expected tables")
  func tableNames() async throws {
    let db = try makeDB()
    let names = try await db.tableNames()
    #expect(names.contains("objects"))
    #expect(names.contains("tags"))
    #expect(names.contains("folders"))
    #expect(names.contains("folder_items"))
  }

  @Test("Column names for objects table")
  func columnNames() async throws {
    let db = try makeDB()
    let cols = try await db.columnNames(table: "objects")
    #expect(cols.contains("id"))
    #expect(cols.contains("hash"))
    #expect(cols.contains("name"))
  }

  @Test("Column names for unknown table throws")
  func unknownTable() async throws {
    let db = try makeDB()
    await #expect(throws: DatabaseError.self) {
      try await db.columnNames(table: "nonexistent")
    }
  }

  @Test("Row count")
  func rowCount() async throws {
    let db = try makeDB()
    _ = try await db.insertObject(hash: sampleHash(1), name: "a")
    _ = try await db.insertObject(hash: sampleHash(2), name: "b")

    let count = try await db.rowCount(table: "objects")
    #expect(count == 2)
  }

  @Test("Fetch rows with limit and offset")
  func fetchRows() async throws {
    let db = try makeDB()
    _ = try await db.insertObject(hash: sampleHash(1), name: "a")
    _ = try await db.insertObject(hash: sampleHash(2), name: "b")
    _ = try await db.insertObject(hash: sampleHash(3), name: "c")

    let rows = try await db.fetchRows(table: "objects", limit: 2, offset: 0)
    #expect(rows.count == 2)

    let nextRows = try await db.fetchRows(table: "objects", limit: 2, offset: 2)
    #expect(nextRows.count == 1)
  }
}
