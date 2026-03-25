import Foundation
import Testing

@testable import FilechuteCore

private func withStoreManager<T>(_ body: (StoreManager) async throws -> T) async throws -> T {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("filechute-sm-test-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: dir) }

  let storeRoot = dir.appendingPathComponent("test.filechute")
  let manager = try await MainActor.run { try StoreManager(storeRoot: storeRoot) }
  return try await body(manager)
}

private func createTempFile(in dir: URL, name: String, contents: String) throws -> URL {
  let fileURL = dir.appendingPathComponent(name)
  try contents.write(to: fileURL, atomically: true, encoding: .utf8)
  return fileURL
}

private func makeTempDir() throws -> URL {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("filechute-sm-files-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

// MARK: - Basic CRUD

@Suite("StoreManager - Objects")
struct StoreManagerObjectTests {
  @Test("Ingest creates object and refreshes state")
  func ingestAndRefresh() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "hello world")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      #expect(objects.count == 1)
      #expect(objects[0].name == "doc")
    }
  }

  @Test("Ingest multiple files")
  func ingestMultiple() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let f1 = try createTempFile(in: dir, name: "a.txt", contents: "aaa")
      let f2 = try createTempFile(in: dir, name: "b.txt", contents: "bbb")
      let f3 = try createTempFile(in: dir, name: "c.txt", contents: "ccc")
      try await manager.ingest(urls: [f1, f2, f3])

      let objects = await manager.objects
      #expect(objects.count == 3)
    }
  }

  @Test("Delete object moves to trash")
  func deleteObject() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "content")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      try await manager.deleteObject(objects[0].id)

      let afterDelete = await manager.objects
      #expect(afterDelete.isEmpty)

      let deleted = await manager.deletedObjects
      #expect(deleted.count == 1)
    }
  }

  @Test("Restore object from trash")
  func restoreObject() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "content")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      let id = objects[0].id
      try await manager.deleteObject(id)
      try await manager.restoreObject(id)

      let restored = await manager.objects
      #expect(restored.count == 1)

      let deleted = await manager.deletedObjects
      #expect(deleted.isEmpty)
    }
  }

  @Test("Permanently delete removes blob")
  func permanentlyDelete() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "gone forever")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      let obj = objects[0]
      try await manager.permanentlyDelete(obj.id)

      let afterPerm = await manager.objects
      #expect(afterPerm.isEmpty)
      #expect(!manager.objectStore.exists(obj.hash))
    }
  }

  @Test("Rename object")
  func renameObject() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "old.txt", contents: "data")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      try await manager.renameObject(objects[0].id, to: "new name")

      let renamed = await manager.objects
      #expect(renamed[0].name == "new name")
    }
  }

  @Test("Update notes")
  func updateNotes() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "data")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      try await manager.updateNotes(objects[0].id, notes: "my notes")

      let obj = try await manager.database.getObject(byId: objects[0].id)
      #expect(obj?.notes == "my notes")
    }
  }

  @Test("Empty trash removes all deleted objects")
  func emptyTrash() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let f1 = try createTempFile(in: dir, name: "a.txt", contents: "aaa")
      let f2 = try createTempFile(in: dir, name: "b.txt", contents: "bbb")
      try await manager.ingest(urls: [f1, f2])

      let objects = await manager.objects
      for obj in objects {
        try await manager.deleteObject(obj.id)
      }

      try await manager.emptyTrash()

      let deleted = await manager.deletedObjects
      #expect(deleted.isEmpty)

      for obj in objects {
        #expect(!manager.objectStore.exists(obj.hash))
      }
    }
  }

  @Test("Version history returns previous versions")
  func versionHistory() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "version 1")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      let v1 = objects[0]

      let updatedFile = try createTempFile(in: dir, name: "doc-v2.txt", contents: "version 2")
      let v2 = try await manager.ingestionService.update(objectId: v1.id, withFileAt: updatedFile)

      let history = try await manager.versionHistory(for: v2.id)
      #expect(history.count == 1)
      #expect(history[0].id == v1.id)
    }
  }
}

// MARK: - Tags

@Suite("StoreManager - Tags")
struct StoreManagerTagTests {
  @Test("Add and remove tag")
  func addAndRemoveTag() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "data")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      let id = objects[0].id

      try await manager.addTag("invoice", to: id)
      var tags = try await manager.tags(for: id)
      #expect(tags.count == 1)
      #expect(tags[0].name == "invoice")

      let allTags = await manager.allTags
      #expect(allTags.count == 1)
      #expect(allTags[0].tag.name == "invoice")

      try await manager.removeTag(tags[0].id, from: id)
      tags = try await manager.tags(for: id)
      #expect(tags.isEmpty)
    }
  }

  @Test("Bulk add tag to multiple objects")
  func bulkAddTag() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let f1 = try createTempFile(in: dir, name: "a.txt", contents: "aaa")
      let f2 = try createTempFile(in: dir, name: "b.txt", contents: "bbb")
      try await manager.ingest(urls: [f1, f2])

      let objects = await manager.objects
      let ids = Set(objects.map(\.id))
      try await manager.addTagToObjects("shared-tag", objectIds: ids)

      for id in ids {
        let tags = try await manager.tags(for: id)
        #expect(tags.contains { $0.name == "shared-tag" })
      }
    }
  }

  @Test("Bulk remove tag from multiple objects")
  func bulkRemoveTag() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let f1 = try createTempFile(in: dir, name: "a.txt", contents: "aaa")
      let f2 = try createTempFile(in: dir, name: "b.txt", contents: "bbb")
      try await manager.ingest(urls: [f1, f2])

      let objects = await manager.objects
      let ids = Set(objects.map(\.id))
      try await manager.addTagToObjects("remove-me", objectIds: ids)

      let allTags = await manager.allTags
      let tagId = allTags.first { $0.tag.name == "remove-me" }!.tag.id
      try await manager.removeTagFromObjects(tagId, objectIds: ids)

      for id in ids {
        let tags = try await manager.tags(for: id)
        #expect(!tags.contains { $0.name == "remove-me" })
      }
    }
  }

  @Test("tagNamesByObject is populated after refresh")
  func tagNamesByObject() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "data")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      try await manager.addTag("alpha", to: objects[0].id)
      try await manager.addTag("beta", to: objects[0].id)

      let tagNames = await manager.tagNamesByObject[objects[0].id]
      #expect(tagNames?.count == 2)
      #expect(tagNames?.contains("alpha") == true)
      #expect(tagNames?.contains("beta") == true)
    }
  }
}

// MARK: - File extension

@Suite("StoreManager - File Extension")
struct StoreManagerFileExtensionTests {
  @Test("fileExtension returns metadata extension")
  func fromMetadata() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "photo.jpg", contents: "jpeg data")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      let ext = await manager.fileExtension(for: objects[0])
      #expect(ext == "jpg")
    }
  }

  @Test("fileExtension falls back to name when no metadata")
  func fromName() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "data")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      // Clear the metadata extension to test fallback
      try await manager.database.setMetadata(objectId: objects[0].id, key: "extension", value: "")

      // The name was stored as "doc" (without extension) so rename to include extension
      try await manager.renameObject(objects[0].id, to: "report.pdf")
      try await manager.refresh()

      let updated = await manager.objects
      let ext = await manager.fileExtension(for: updated[0])
      #expect(ext == "pdf")
    }
  }

  @Test("fileExtension returns nil for extensionless file")
  func noExtension() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "Makefile", contents: "all: build")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      // Clear metadata too
      try await manager.database.setMetadata(objectId: objects[0].id, key: "extension", value: "")

      let ext = await manager.fileExtension(for: objects[0])
      #expect(ext == nil)
    }
  }
}

// MARK: - Folders

@Suite("StoreManager - Folders")
struct StoreManagerFolderTests {
  @Test("Create folder and list")
  func createFolder() async throws {
    try await withStoreManager { manager in
      let folder = try await manager.createFolder(name: "Photos")

      let folders = await manager.folders
      #expect(folders.count == 1)
      #expect(folders[0].name == "Photos")
      #expect(folders[0].id == folder.id)
    }
  }

  @Test("Rename folder")
  func renameFolder() async throws {
    try await withStoreManager { manager in
      let folder = try await manager.createFolder(name: "Old Name")
      try await manager.renameFolder(folder.id, to: "New Name")

      let folders = await manager.folders
      #expect(folders[0].name == "New Name")
    }
  }

  @Test("Add and remove item from folder")
  func addRemoveItem() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "data")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      let folder = try await manager.createFolder(name: "Docs")

      try await manager.addItemToFolder(objectId: objects[0].id, folderId: folder.id)
      var items = try await manager.itemsInFolder(folder.id)
      #expect(items.count == 1)

      try await manager.removeItemFromFolder(objectId: objects[0].id, folderId: folder.id)
      items = try await manager.itemsInFolder(folder.id)
      #expect(items.isEmpty)
    }
  }

  @Test("Soft delete and restore folder")
  func softDeleteRestoreFolder() async throws {
    try await withStoreManager { manager in
      let folder = try await manager.createFolder(name: "Temp")
      try await manager.softDeleteFolder(folder.id)

      // allFolders() excludes deleted folders
      var folders = await manager.folders
      #expect(folders.isEmpty)

      try await manager.restoreFolder(folder.id)
      folders = await manager.folders
      #expect(folders.count == 1)
      #expect(folders[0].name == "Temp")
    }
  }

  @Test("foldersContaining returns correct folders")
  func foldersContaining() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "data")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      let folder1 = try await manager.createFolder(name: "A")
      let folder2 = try await manager.createFolder(name: "B")

      try await manager.addItemToFolder(objectId: objects[0].id, folderId: folder1.id)
      try await manager.addItemToFolder(objectId: objects[0].id, folderId: folder2.id)

      let containing = try await manager.foldersContaining(objectId: objects[0].id)
      #expect(containing.count == 2)
    }
  }

  @Test("Nested folder creation and items")
  func nestedFolders() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let parent = try await manager.createFolder(name: "Parent")
      let child = try await manager.createFolder(name: "Child", parentId: parent.id)

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "data")
      try await manager.ingest(urls: [file])
      let objects = await manager.objects

      try await manager.addItemToFolder(objectId: objects[0].id, folderId: child.id)

      // Recursive search from parent should find the item
      let items = try await manager.itemsInFolder(parent.id, recursive: true)
      #expect(items.count == 1)

      // Non-recursive from parent should not
      let directItems = try await manager.itemsInFolder(parent.id, recursive: false)
      #expect(directItems.isEmpty)
    }
  }

  @Test("itemsInFolder populates sizeBytes")
  func itemsInFolderPopulatesSize() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "some content here")
      try await manager.ingest(urls: [file])

      let objects = await manager.objects
      let folder = try await manager.createFolder(name: "F")
      try await manager.addItemToFolder(objectId: objects[0].id, folderId: folder.id)

      let items = try await manager.itemsInFolder(folder.id)
      #expect(items[0].sizeBytes > 0)
    }
  }
}

// MARK: - Directory Ingestion

@Suite("StoreManager - Directory Ingestion")
struct StoreManagerDirectoryIngestionTests {
  @Test("Ingest directory creates folder structure")
  func basicDirectoryIngestion() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let subdir = dir.appendingPathComponent("MyFolder")
      try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
      _ = try createTempFile(in: subdir, name: "a.txt", contents: "aaa")
      _ = try createTempFile(in: subdir, name: "b.txt", contents: "bbb")

      try await manager.ingestDirectory(at: subdir)

      let folders = await manager.folders
      #expect(folders.count == 1)
      #expect(folders[0].name == "MyFolder")

      let items = try await manager.itemsInFolder(folders[0].id)
      #expect(items.count == 2)
    }
  }

  @Test("Ingest nested directories creates nested folders")
  func nestedDirectoryIngestion() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let root = dir.appendingPathComponent("Root")
      let sub = root.appendingPathComponent("Sub")
      try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
      _ = try createTempFile(in: root, name: "top.txt", contents: "top")
      _ = try createTempFile(in: sub, name: "nested.txt", contents: "nested")

      try await manager.ingestDirectory(at: root)

      let folders = await manager.folders
      #expect(folders.count == 2)

      let rootFolder = folders.first { $0.name == "Root" }!
      let subFolder = folders.first { $0.name == "Sub" }!
      #expect(subFolder.parentId == rootFolder.id)

      let rootItems = try await manager.itemsInFolder(rootFolder.id, recursive: false)
      #expect(rootItems.count == 1)

      let subItems = try await manager.itemsInFolder(subFolder.id)
      #expect(subItems.count == 1)
    }
  }

  @Test("Ingest directory ignores .DS_Store")
  func ignoresDSStore() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let folder = dir.appendingPathComponent("Folder")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      _ = try createTempFile(in: folder, name: "good.txt", contents: "keep")
      _ = try createTempFile(in: folder, name: ".DS_Store", contents: "ignore me")

      try await manager.ingestDirectory(at: folder)

      let objects = await manager.objects
      #expect(objects.count == 1)
      #expect(objects[0].name == "good")
    }
  }

  @Test("Ingest directory skips .git directories")
  func skipsGitDirectory() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let folder = dir.appendingPathComponent("Folder")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      _ = try createTempFile(in: folder, name: "good.txt", contents: "keep")

      let gitDir = folder.appendingPathComponent(".git")
      try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
      _ = try createTempFile(in: gitDir, name: "HEAD", contents: "ref: refs/heads/main")

      try await manager.ingestDirectory(at: folder)

      let objects = await manager.objects
      #expect(objects.count == 1)
      #expect(objects[0].name == "good")

      let folders = await manager.folders
      #expect(folders.count == 1)
      #expect(folders[0].name == "Folder")
    }
  }

  @Test("Ingest directory tracks progress")
  func tracksProgress() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let folder = dir.appendingPathComponent("Folder")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      _ = try createTempFile(in: folder, name: "a.txt", contents: "aaa")
      _ = try createTempFile(in: folder, name: "b.txt", contents: "bbb")
      _ = try createTempFile(in: folder, name: "c.txt", contents: "ccc")

      try await manager.ingestDirectory(at: folder)

      // After completion, progress should be inactive
      let isActive = await manager.ingestionProgress.isActive
      #expect(!isActive)
    }
  }

  @Test("Ingest directory into parent folder")
  func ingestIntoParentFolder() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let parent = try await manager.createFolder(name: "Parent")

      let folder = dir.appendingPathComponent("Child")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      _ = try createTempFile(in: folder, name: "doc.txt", contents: "data")

      try await manager.ingestDirectory(at: folder, intoFolder: parent.id)

      let folders = await manager.folders
      let child = folders.first { $0.name == "Child" }!
      #expect(child.parentId == parent.id)
    }
  }
}

// MARK: - Refresh and sizes

@Suite("StoreManager - Refresh")
struct StoreManagerRefreshTests {
  @Test("Refresh populates sizesByObject")
  func populatesSizes() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let file = try createTempFile(in: dir, name: "doc.txt", contents: "hello world")
      try await manager.ingest(urls: [file])

      let sizes = await manager.sizesByObject
      #expect(!sizes.isEmpty)
      let objects = await manager.objects
      #expect(objects[0].sizeBytes > 0)
    }
  }

  @Test("Refresh separates active and deleted objects")
  func separatesActiveAndDeleted() async throws {
    try await withStoreManager { manager in
      let dir = try makeTempDir()
      defer { try? FileManager.default.removeItem(at: dir) }

      let f1 = try createTempFile(in: dir, name: "keep.txt", contents: "keep")
      let f2 = try createTempFile(in: dir, name: "trash.txt", contents: "trash")
      try await manager.ingest(urls: [f1, f2])

      let objects = await manager.objects
      let trashObj = objects.first { $0.name == "trash" }!
      try await manager.deleteObject(trashObj.id)

      let active = await manager.objects
      let deleted = await manager.deletedObjects
      #expect(active.count == 1)
      #expect(deleted.count == 1)
      #expect(active[0].name == "keep")
    }
  }
}

// MARK: - Store name

@Suite("StoreManager - Store Name")
struct StoreManagerStoreNameTests {
  @Test("storeName strips extension from storeRoot")
  func storeName() async throws {
    try await withStoreManager { manager in
      #expect(manager.storeName == "test")
    }
  }
}
