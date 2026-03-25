import Foundation
import SQLite3

// swift-format-ignore: AlwaysUseLowerCamelCase
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public actor Database {
  nonisolated(unsafe) private let db: OpaquePointer

  public init(path: String) throws {
    var dbPointer: OpaquePointer?
    let result = sqlite3_open(path, &dbPointer)
    guard result == SQLITE_OK, let opened = dbPointer else {
      let msg = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
      sqlite3_close(dbPointer)
      throw DatabaseError.openFailed(msg)
    }
    self.db = opened
    try Self.initSchema(db: opened)
    Log.info("Opened database at \(path)", category: .database)
  }

  deinit {
    sqlite3_close(db)
  }

  // MARK: - Schema

  private static let schemaDDL: [String] = [
    "PRAGMA foreign_keys = ON",
    "PRAGMA journal_mode = WAL",
    """
    CREATE TABLE IF NOT EXISTS objects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        hash TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER,
        modified_at INTEGER,
        last_opened_at INTEGER,
        file_extension TEXT NOT NULL DEFAULT ''
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS taggings (
        object_id INTEGER NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
        tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (object_id, tag_id)
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_taggings_tag ON taggings(tag_id)",
    """
    CREATE TABLE IF NOT EXISTS metadata (
        object_id INTEGER NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
        key TEXT NOT NULL,
        value TEXT,
        PRIMARY KEY (object_id, key)
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_metadata_key_value ON metadata(key, value)",
    """
    CREATE TABLE IF NOT EXISTS versions (
        object_id INTEGER NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
        previous_object_id INTEGER NOT NULL REFERENCES objects(id),
        created_at INTEGER NOT NULL,
        PRIMARY KEY (object_id, previous_object_id)
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_versions_previous ON versions(previous_object_id)",
    """
    CREATE TABLE IF NOT EXISTS rename_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        object_id INTEGER NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
        old_name TEXT NOT NULL,
        new_name TEXT NOT NULL,
        renamed_at INTEGER NOT NULL
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_rename_history_object ON rename_history(object_id)",
  ]

  private static let migrations: [String] = [
    "ALTER TABLE objects ADD COLUMN modified_at INTEGER",
    "ALTER TABLE objects ADD COLUMN last_opened_at INTEGER",
    "ALTER TABLE objects ADD COLUMN file_extension TEXT NOT NULL DEFAULT ''",
    """
    UPDATE objects SET file_extension = COALESCE(
        (SELECT value FROM metadata WHERE metadata.object_id = objects.id AND metadata.key = 'extension'),
        ''
    ) WHERE file_extension = ''
    """,
    "ALTER TABLE objects ADD COLUMN notes TEXT",
    "ALTER TABLE objects ADD COLUMN content_text TEXT",
    """
    CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
        name,
        tags,
        notes,
        content_text,
        tokenize='porter unicode61'
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        parent_id INTEGER REFERENCES folders(id),
        position REAL NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS folder_items (
        folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
        object_id INTEGER NOT NULL REFERENCES objects(id) ON DELETE CASCADE,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (folder_id, object_id)
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_folder_items_object ON folder_items(object_id)",
    "CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders(parent_id)",
  ]

  private static func initSchema(db: OpaquePointer) throws {
    for sql in schemaDDL {
      var error: UnsafeMutablePointer<CChar>?
      let result = sqlite3_exec(db, sql, nil, nil, &error)
      if result != SQLITE_OK {
        let msg = error.map { String(cString: $0) } ?? "unknown error"
        sqlite3_free(error)
        throw DatabaseError.executionFailed(msg)
      }
    }
    for sql in migrations {
      var error: UnsafeMutablePointer<CChar>?
      // Ignore failures (column already exists).
      sqlite3_exec(db, sql, nil, nil, &error)
      sqlite3_free(error)
    }
  }

  // MARK: - Objects

  public func insertObject(
    hash: ContentHash, name: String, fileExtension: String = "", contentText: String? = nil
  ) throws -> Int64 {
    let now = Int64(Date().timeIntervalSince1970)
    let id = try insert(
      "INSERT INTO objects (hash, name, created_at, modified_at, file_extension, content_text) VALUES (?, ?, ?, ?, ?, ?)",
      bind: { stmt in
        sqlite3_bind_text(stmt, 1, hash.hexString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, now)
        sqlite3_bind_int64(stmt, 4, now)
        sqlite3_bind_text(stmt, 5, fileExtension, -1, SQLITE_TRANSIENT)
        if let contentText {
          sqlite3_bind_text(stmt, 6, contentText, -1, SQLITE_TRANSIENT)
        } else {
          sqlite3_bind_null(stmt, 6)
        }
      }
    )
    try insertSearchIndex(objectId: id, name: name, tags: "", notes: nil, contentText: contentText)
    Log.debug("Inserted object \(name) (\(hash.hexString.prefix(8)))", category: .database)
    return id
  }

  public func getObject(byId id: Int64) throws -> StoredObject? {
    try query(
      "SELECT id, hash, name, created_at, deleted_at, modified_at, last_opened_at, file_extension, notes FROM objects WHERE id = ?",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, id) },
      read: readObject
    ).first
  }

  public func getObject(byHash hash: ContentHash) throws -> StoredObject? {
    try query(
      "SELECT id, hash, name, created_at, deleted_at, modified_at, last_opened_at, file_extension, notes FROM objects WHERE hash = ?",
      bind: { stmt in sqlite3_bind_text(stmt, 1, hash.hexString, -1, SQLITE_TRANSIENT) },
      read: readObject
    ).first
  }

  public func allObjects(includeDeleted: Bool = false) throws -> [StoredObject] {
    let sql =
      includeDeleted
      ? "SELECT id, hash, name, created_at, deleted_at, modified_at, last_opened_at, file_extension, notes FROM objects ORDER BY name"
      : "SELECT id, hash, name, created_at, deleted_at, modified_at, last_opened_at, file_extension, notes FROM objects WHERE deleted_at IS NULL ORDER BY name"
    return try query(sql, read: readObject)
  }

  public func renameObject(id: Int64, newName: String) throws {
    let now = Int64(Date().timeIntervalSince1970)
    if let existing = try getObject(byId: id) {
      try insert(
        "INSERT INTO rename_history (object_id, old_name, new_name, renamed_at) VALUES (?, ?, ?, ?)",
        bind: { stmt in
          sqlite3_bind_int64(stmt, 1, id)
          sqlite3_bind_text(stmt, 2, existing.name, -1, SQLITE_TRANSIENT)
          sqlite3_bind_text(stmt, 3, newName, -1, SQLITE_TRANSIENT)
          sqlite3_bind_int64(stmt, 4, now)
        }
      )
    }
    try update(
      "UPDATE objects SET name = ?, modified_at = ? WHERE id = ?",
      bind: { stmt in
        sqlite3_bind_text(stmt, 1, newName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, now)
        sqlite3_bind_int64(stmt, 3, id)
      }
    )
    try updateSearchIndex(objectId: id)
  }

  public func renameHistory(for objectId: Int64) throws -> [(
    oldName: String, newName: String, date: Date
  )] {
    try query(
      "SELECT old_name, new_name, renamed_at FROM rename_history WHERE object_id = ? ORDER BY id DESC",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, objectId) },
      read: { stmt in
        (
          oldName: String(cString: sqlite3_column_text(stmt, 0)),
          newName: String(cString: sqlite3_column_text(stmt, 1)),
          date: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))
        )
      }
    )
  }

  public func touchModified(id: Int64) throws {
    try update(
      "UPDATE objects SET modified_at = ? WHERE id = ?",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 2, id)
      }
    )
  }

  public func touchLastOpened(id: Int64) throws {
    try update(
      "UPDATE objects SET last_opened_at = ? WHERE id = ?",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 2, id)
      }
    )
  }

  public func updateNotes(id: Int64, notes: String?) throws {
    try update(
      "UPDATE objects SET notes = ?, modified_at = ? WHERE id = ?",
      bind: { stmt in
        if let notes {
          sqlite3_bind_text(stmt, 1, notes, -1, SQLITE_TRANSIENT)
        } else {
          sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_int64(stmt, 2, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 3, id)
      }
    )
    try updateSearchIndex(objectId: id)
  }

  public func softDeleteObject(id: Int64) throws {
    try update(
      "UPDATE objects SET deleted_at = ? WHERE id = ?",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 2, id)
      }
    )
    try deleteSearchIndex(objectId: id)
    Log.debug("Soft-deleted object \(id)", category: .database)
  }

  public func restoreObject(id: Int64) throws {
    try update(
      "UPDATE objects SET deleted_at = NULL WHERE id = ?",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, id) }
    )
    try updateSearchIndex(objectId: id)
    Log.debug("Restored object \(id)", category: .database)
  }

  public func permanentlyDeleteObject(id: Int64) throws {
    try deleteSearchIndex(objectId: id)
    try update(
      "DELETE FROM objects WHERE id = ?",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, id) }
    )
    Log.debug("Permanently deleted object \(id)", category: .database)
  }

  // MARK: - Tags

  public func createTag(name: String) throws -> Int64 {
    let id = try insert(
      "INSERT INTO tags (name) VALUES (?)",
      bind: { stmt in sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT) }
    )
    Log.debug("Created tag '\(name)' (\(id))", category: .database)
    return id
  }

  public func getTag(byId id: Int64) throws -> Tag? {
    try query(
      "SELECT id, name FROM tags WHERE id = ?",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, id) },
      read: readTag
    ).first
  }

  public func getTag(byName name: String) throws -> Tag? {
    try query(
      "SELECT id, name FROM tags WHERE name = ?",
      bind: { stmt in sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT) },
      read: readTag
    ).first
  }

  public func getOrCreateTag(name: String) throws -> Tag {
    if let existing = try getTag(byName: name) {
      return existing
    }
    let id = try createTag(name: name)
    return Tag(id: id, name: name)
  }

  public func allTags() throws -> [Tag] {
    try query("SELECT id, name FROM tags ORDER BY name", read: readTag)
  }

  public func allTagsWithCounts() throws -> [TagCount] {
    try query(
      """
      SELECT t.id, t.name, COUNT(o.id) as count
      FROM tags t
      LEFT JOIN taggings tg ON tg.tag_id = t.id
      LEFT JOIN objects o ON o.id = tg.object_id AND o.deleted_at IS NULL
      GROUP BY t.id
      ORDER BY t.name
      """,
      read: { stmt in
        TagCount(
          tag: Tag(id: self.columnInt64(stmt, 0), name: self.columnText(stmt, 1)!),
          count: Int(self.columnInt64(stmt, 2))
        )
      }
    )
  }

  public func deleteTag(id: Int64) throws {
    try update(
      "DELETE FROM tags WHERE id = ?",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, id) }
    )
  }

  // MARK: - Taggings

  public func addTag(_ tagId: Int64, toObject objectId: Int64) throws {
    try insert(
      "INSERT OR IGNORE INTO taggings (object_id, tag_id, created_at) VALUES (?, ?, ?)",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, objectId)
        sqlite3_bind_int64(stmt, 2, tagId)
        sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
      }
    )
    try updateSearchIndex(objectId: objectId)
    Log.debug("Added tag \(tagId) to object \(objectId)", category: .database)
  }

  public func removeTag(_ tagId: Int64, fromObject objectId: Int64) throws {
    try update(
      "DELETE FROM taggings WHERE object_id = ? AND tag_id = ?",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, objectId)
        sqlite3_bind_int64(stmt, 2, tagId)
      }
    )
    try updateSearchIndex(objectId: objectId)
    Log.debug("Removed tag \(tagId) from object \(objectId)", category: .database)
  }

  public func tags(forObject objectId: Int64) throws -> [Tag] {
    try query(
      """
      SELECT t.id, t.name FROM tags t
      JOIN taggings tg ON tg.tag_id = t.id
      WHERE tg.object_id = ?
      ORDER BY t.name
      """,
      bind: { stmt in sqlite3_bind_int64(stmt, 1, objectId) },
      read: readTag
    )
  }

  public func allTagNamesByObject() throws -> [Int64: [String]] {
    let rows: [(Int64, String)] = try query(
      """
      SELECT tg.object_id, t.name FROM tags t
      JOIN taggings tg ON tg.tag_id = t.id
      ORDER BY tg.object_id, t.name
      """,
      read: { stmt in
        (sqlite3_column_int64(stmt, 0), String(cString: sqlite3_column_text(stmt, 1)))
      }
    )
    var result: [Int64: [String]] = [:]
    for (objectId, name) in rows {
      result[objectId, default: []].append(name)
    }
    return result
  }

  // MARK: - Full-Text Search

  private func insertSearchIndex(
    objectId: Int64, name: String, tags: String, notes: String?, contentText: String?
  ) throws {
    try insert(
      "INSERT INTO search_index (rowid, name, tags, notes, content_text) VALUES (?, ?, ?, ?, ?)",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, objectId)
        sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, tags, -1, SQLITE_TRANSIENT)
        if let notes {
          sqlite3_bind_text(stmt, 4, notes, -1, SQLITE_TRANSIENT)
        } else {
          sqlite3_bind_null(stmt, 4)
        }
        if let contentText {
          sqlite3_bind_text(stmt, 5, contentText, -1, SQLITE_TRANSIENT)
        } else {
          sqlite3_bind_null(stmt, 5)
        }
      }
    )
  }

  private func updateSearchIndex(objectId: Int64) throws {
    guard let obj = try getObject(byId: objectId) else { return }
    let tagNames = try tags(forObject: objectId).map(\.name).joined(separator: " ")
    try deleteSearchIndex(objectId: objectId)
    try insertSearchIndex(
      objectId: objectId,
      name: obj.name,
      tags: tagNames,
      notes: obj.notes,
      contentText: contentText(forObject: objectId)
    )
  }

  private func deleteSearchIndex(objectId: Int64) throws {
    try update(
      "DELETE FROM search_index WHERE rowid = ?",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, objectId) }
    )
  }

  private func contentText(forObject objectId: Int64) throws -> String? {
    try query(
      "SELECT content_text FROM objects WHERE id = ?",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, objectId) },
      read: { stmt in self.columnText(stmt, 0) }
    ).first ?? nil
  }

  public func search(_ queryText: String, limit: Int = 100) throws -> [StoredObject] {
    let sanitized = sanitizeFTS5Query(queryText)
    guard !sanitized.isEmpty else { return [] }
    return try query(
      """
      SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at, o.modified_at,
             o.last_opened_at, o.file_extension, o.notes
      FROM search_index si
      JOIN objects o ON o.id = si.rowid
      WHERE search_index MATCH ? AND o.deleted_at IS NULL
      ORDER BY bm25(search_index, 10.0, 5.0, 3.0, 1.0)
      LIMIT ?
      """,
      bind: { stmt in
        sqlite3_bind_text(stmt, 1, sanitized, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))
      },
      read: readObject
    )
  }

  private func sanitizeFTS5Query(_ query: String) -> String {
    let tokens: [String] =
      query
      .split(separator: " ", omittingEmptySubsequences: true)
      .compactMap { token in
        var t = String(token)
        t = t.replacingOccurrences(of: "\"", with: "")
        t = t.replacingOccurrences(of: "'", with: "")
        guard !t.isEmpty else { return nil }
        return "\"\(t)\"*"
      }
    return tokens.joined(separator: " ")
  }

  // MARK: - Tag-Based Search

  public func objects(withTagId tagId: Int64) throws -> [StoredObject] {
    try query(
      """
      SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at, o.modified_at, o.last_opened_at, o.file_extension, o.notes
      FROM objects o
      JOIN taggings tg ON tg.object_id = o.id
      WHERE tg.tag_id = ? AND o.deleted_at IS NULL
      ORDER BY o.name
      """,
      bind: { stmt in sqlite3_bind_int64(stmt, 1, tagId) },
      read: readObject
    )
  }

  public func objects(withAllTagIds tagIds: [Int64]) throws -> [StoredObject] {
    guard !tagIds.isEmpty else {
      return try allObjects()
    }

    if tagIds.count == 1 {
      return try objects(withTagId: tagIds[0])
    }

    var joins = ""
    var conditions = "WHERE o.deleted_at IS NULL"
    for (i, tagId) in tagIds.enumerated() {
      let alias = "t\(i + 1)"
      joins += " JOIN taggings \(alias) ON \(alias).object_id = o.id"
      conditions += " AND \(alias).tag_id = \(tagId)"
    }

    let sql = """
          SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at, o.modified_at, o.last_opened_at, o.file_extension, o.notes
          FROM objects o\(joins)
          \(conditions)
          ORDER BY o.name
      """

    return try query(sql, read: readObject)
  }

  public func reachableTags(from tagIds: [Int64]) throws -> [TagCount] {
    guard !tagIds.isEmpty else {
      return try allTagsWithCounts()
    }

    var joins = ""
    var conditions = "WHERE o.deleted_at IS NULL"

    for (i, tagId) in tagIds.enumerated() {
      let alias = "t\(i + 1)"
      joins += " JOIN taggings \(alias) ON \(alias).object_id = o.id"
      conditions += " AND \(alias).tag_id = \(tagId)"
    }

    joins += " JOIN taggings tn ON tn.object_id = o.id"

    let excludeList = tagIds.map(String.init).joined(separator: ", ")
    conditions += " AND tn.tag_id NOT IN (\(excludeList))"

    let sql = """
          SELECT tags.id, tags.name, COUNT(*) as count
          FROM objects o\(joins)
          JOIN tags ON tags.id = tn.tag_id
          \(conditions)
          GROUP BY tags.id
          ORDER BY tags.name
      """

    return try query(
      sql,
      read: { stmt in
        TagCount(
          tag: Tag(id: self.columnInt64(stmt, 0), name: self.columnText(stmt, 1)!),
          count: Int(self.columnInt64(stmt, 2))
        )
      })
  }

  // MARK: - Metadata

  public func setMetadata(objectId: Int64, key: String, value: String?) throws {
    try insert(
      "INSERT OR REPLACE INTO metadata (object_id, key, value) VALUES (?, ?, ?)",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, objectId)
        sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
        if let value {
          sqlite3_bind_text(stmt, 3, value, -1, SQLITE_TRANSIENT)
        } else {
          sqlite3_bind_null(stmt, 3)
        }
      }
    )
  }

  public func allSizes() throws -> [Int64: UInt64] {
    let rows: [(Int64, UInt64)] = try query(
      "SELECT object_id, value FROM metadata WHERE key = 'size_bytes' AND value IS NOT NULL",
      read: { stmt in
        let objectId = sqlite3_column_int64(stmt, 0)
        let value = String(cString: sqlite3_column_text(stmt, 1))
        return (objectId, UInt64(value) ?? 0)
      }
    )
    return Dictionary(rows, uniquingKeysWith: { _, last in last })
  }

  public func allExtensions() throws -> [Int64: String] {
    let rows: [(Int64, String)] = try query(
      "SELECT object_id, value FROM metadata WHERE key = 'extension' AND value IS NOT NULL",
      read: { stmt in
        (sqlite3_column_int64(stmt, 0), String(cString: sqlite3_column_text(stmt, 1)))
      }
    )
    return Dictionary(rows, uniquingKeysWith: { _, last in last })
  }

  public func getMetadata(objectId: Int64, key: String) throws -> String? {
    try query(
      "SELECT value FROM metadata WHERE object_id = ? AND key = ?",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, objectId)
        sqlite3_bind_text(stmt, 2, key, -1, SQLITE_TRANSIENT)
      },
      read: { stmt in self.columnText(stmt, 0) }
    ).first ?? nil
  }

  public func allMetadata(for objectId: Int64) throws -> [ObjectMetadata] {
    try query(
      "SELECT object_id, key, value FROM metadata WHERE object_id = ? ORDER BY key",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, objectId) },
      read: { stmt in
        ObjectMetadata(
          objectId: self.columnInt64(stmt, 0),
          key: self.columnText(stmt, 1)!,
          value: self.columnText(stmt, 2)
        )
      }
    )
  }

  // MARK: - Versions

  public func addVersion(objectId: Int64, previousObjectId: Int64) throws {
    try insert(
      "INSERT INTO versions (object_id, previous_object_id, created_at) VALUES (?, ?, ?)",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, objectId)
        sqlite3_bind_int64(stmt, 2, previousObjectId)
        sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
      }
    )
  }

  public func versionHistory(for objectId: Int64) throws -> [StoredObject] {
    var history: [StoredObject] = []
    var currentId = objectId

    while true {
      let predecessors = try query(
        """
        SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at, o.modified_at, o.last_opened_at, o.file_extension, o.notes
        FROM objects o
        JOIN versions v ON v.previous_object_id = o.id
        WHERE v.object_id = ?
        """,
        bind: { stmt in sqlite3_bind_int64(stmt, 1, currentId) },
        read: readObject
      )

      guard let predecessor = predecessors.first else { break }
      history.append(predecessor)
      currentId = predecessor.id
    }

    return history
  }

  public func latestVersion(of objectId: Int64) throws -> StoredObject? {
    var currentId = objectId

    while true {
      let successors = try query(
        """
        SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at, o.modified_at, o.last_opened_at, o.file_extension, o.notes
        FROM objects o
        JOIN versions v ON v.object_id = o.id
        WHERE v.previous_object_id = ?
        """,
        bind: { stmt in sqlite3_bind_int64(stmt, 1, currentId) },
        read: readObject
      )

      guard let successor = successors.first else { break }
      currentId = successor.id
    }

    if currentId == objectId {
      return nil
    }
    return try getObject(byId: currentId)
  }

  // MARK: - Folders

  public func createFolder(name: String, parentId: Int64? = nil, position: Double = 0) throws
    -> Folder
  {
    let now = Int64(Date().timeIntervalSince1970)
    let id = try insert(
      "INSERT INTO folders (name, parent_id, position, created_at) VALUES (?, ?, ?, ?)",
      bind: { stmt in
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        if let parentId {
          sqlite3_bind_int64(stmt, 2, parentId)
        } else {
          sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_double(stmt, 3, position)
        sqlite3_bind_int64(stmt, 4, now)
      }
    )
    Log.debug(
      "Created folder '\(name)' (id=\(id), parent=\(parentId.map(String.init) ?? "root"), position=\(position))",
      category: .folders
    )
    return Folder(
      id: id,
      name: name,
      parentId: parentId,
      position: position,
      createdAt: Date(timeIntervalSince1970: TimeInterval(now))
    )
  }

  public func renameFolder(id: Int64, name: String) throws {
    let oldName =
      try query(
        "SELECT name FROM folders WHERE id = ?",
        bind: { stmt in sqlite3_bind_int64(stmt, 1, id) },
        read: { stmt in self.columnText(stmt, 0)! }
      ).first ?? ""
    try update(
      "UPDATE folders SET name = ? WHERE id = ?",
      bind: { stmt in
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, id)
      }
    )
    Log.debug("Renamed folder \(id): '\(oldName)' -> '\(name)'", category: .folders)
  }

  public func moveFolder(id: Int64, parentId: Int64?, position: Double) throws {
    try update(
      "UPDATE folders SET parent_id = ?, position = ? WHERE id = ?",
      bind: { stmt in
        if let parentId {
          sqlite3_bind_int64(stmt, 1, parentId)
        } else {
          sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_double(stmt, 2, position)
        sqlite3_bind_int64(stmt, 3, id)
      }
    )
    Log.debug(
      "Moved folder \(id) to parent=\(parentId.map(String.init) ?? "root"), position=\(position)",
      category: .folders
    )
  }

  public func softDeleteFolder(id: Int64) throws {
    let now = Int64(Date().timeIntervalSince1970)
    let descendantIds = try allDescendantFolderIds(of: id)
    let allIds = [id] + descendantIds
    let placeholders = allIds.map { _ in "?" }.joined(separator: ", ")
    try update(
      "UPDATE folders SET deleted_at = ? WHERE id IN (\(placeholders)) AND deleted_at IS NULL",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, now)
        for (i, folderId) in allIds.enumerated() {
          sqlite3_bind_int64(stmt, Int32(i + 2), folderId)
        }
      }
    )
    Log.debug(
      "Soft-deleted folder \(id) (subtree size: \(allIds.count))",
      category: .folders
    )
  }

  public func restoreFolder(id: Int64) throws {
    let descendantIds = try allDescendantFolderIds(of: id, includeDeleted: true)
    let allIds = [id] + descendantIds
    let placeholders = allIds.map { _ in "?" }.joined(separator: ", ")
    try update(
      "UPDATE folders SET deleted_at = NULL WHERE id IN (\(placeholders))",
      bind: { stmt in
        for (i, folderId) in allIds.enumerated() {
          sqlite3_bind_int64(stmt, Int32(i + 1), folderId)
        }
      }
    )
    Log.debug(
      "Restored folder \(id) (subtree size: \(allIds.count))",
      category: .folders
    )
  }

  public func allFolders() throws -> [Folder] {
    try query(
      "SELECT id, name, parent_id, position, created_at, deleted_at FROM folders WHERE deleted_at IS NULL ORDER BY position",
      read: readFolder
    )
  }

  public func getFolder(byId id: Int64) throws -> Folder? {
    try query(
      "SELECT id, name, parent_id, position, created_at, deleted_at FROM folders WHERE id = ?",
      bind: { stmt in sqlite3_bind_int64(stmt, 1, id) },
      read: readFolder
    ).first
  }

  public func addItemToFolder(objectId: Int64, folderId: Int64) throws {
    try insert(
      "INSERT OR IGNORE INTO folder_items (folder_id, object_id, created_at) VALUES (?, ?, ?)",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, folderId)
        sqlite3_bind_int64(stmt, 2, objectId)
        sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
      }
    )
    Log.debug("Added object \(objectId) to folder \(folderId)", category: .folders)
  }

  public func removeItemFromFolder(objectId: Int64, folderId: Int64) throws {
    try update(
      "DELETE FROM folder_items WHERE folder_id = ? AND object_id = ?",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, folderId)
        sqlite3_bind_int64(stmt, 2, objectId)
      }
    )
    Log.debug("Removed object \(objectId) from folder \(folderId)", category: .folders)
  }

  public func items(inFolder folderId: Int64, recursive: Bool = false) throws -> [StoredObject] {
    if recursive {
      let descendantIds = try allDescendantFolderIds(of: folderId)
      let allFolderIds = [folderId] + descendantIds
      let placeholders = allFolderIds.map { _ in "?" }.joined(separator: ", ")
      return try query(
        """
        SELECT DISTINCT o.id, o.hash, o.name, o.created_at, o.deleted_at, o.modified_at, o.last_opened_at, o.file_extension, o.notes
        FROM objects o
        JOIN folder_items fi ON fi.object_id = o.id
        WHERE fi.folder_id IN (\(placeholders)) AND o.deleted_at IS NULL
        ORDER BY o.name
        """,
        bind: { stmt in
          for (i, id) in allFolderIds.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), id)
          }
        },
        read: readObject
      )
    }
    return try query(
      """
      SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at, o.modified_at, o.last_opened_at, o.file_extension, o.notes
      FROM objects o
      JOIN folder_items fi ON fi.object_id = o.id
      WHERE fi.folder_id = ? AND o.deleted_at IS NULL
      ORDER BY o.name
      """,
      bind: { stmt in sqlite3_bind_int64(stmt, 1, folderId) },
      read: readObject
    )
  }

  public func folders(containingObject objectId: Int64) throws -> [Folder] {
    try query(
      """
      SELECT f.id, f.name, f.parent_id, f.position, f.created_at, f.deleted_at
      FROM folders f
      JOIN folder_items fi ON fi.folder_id = f.id
      WHERE fi.object_id = ? AND f.deleted_at IS NULL
      ORDER BY f.name
      """,
      bind: { stmt in sqlite3_bind_int64(stmt, 1, objectId) },
      read: readFolder
    )
  }

  public func directFolderIdForObject(_ objectId: Int64, inSubtreeOf rootFolderId: Int64) throws
    -> Int64?
  {
    let descendantIds = try allDescendantFolderIds(of: rootFolderId)
    let allFolderIds = [rootFolderId] + descendantIds
    let placeholders = allFolderIds.map { _ in "?" }.joined(separator: ", ")
    return try query(
      "SELECT folder_id FROM folder_items WHERE object_id = ? AND folder_id IN (\(placeholders)) LIMIT 1",
      bind: { stmt in
        sqlite3_bind_int64(stmt, 1, objectId)
        for (i, id) in allFolderIds.enumerated() {
          sqlite3_bind_int64(stmt, Int32(i + 2), id)
        }
      },
      read: { stmt in sqlite3_column_int64(stmt, 0) }
    ).first
  }

  public func maxFolderPosition(parentId: Int64?) throws -> Double {
    let result: [Double]
    if let parentId {
      result = try query(
        "SELECT MAX(position) FROM folders WHERE parent_id = ? AND deleted_at IS NULL",
        bind: { stmt in sqlite3_bind_int64(stmt, 1, parentId) },
        read: { stmt in
          sqlite3_column_type(stmt, 0) == SQLITE_NULL ? 0 : sqlite3_column_double(stmt, 0)
        }
      )
    } else {
      result = try query(
        "SELECT MAX(position) FROM folders WHERE parent_id IS NULL AND deleted_at IS NULL",
        read: { stmt in
          sqlite3_column_type(stmt, 0) == SQLITE_NULL ? 0 : sqlite3_column_double(stmt, 0)
        }
      )
    }
    return result.first ?? 0
  }

  public func renumberFolderPositions(parentId: Int64?) throws {
    let folders: [Folder]
    if let parentId {
      folders = try query(
        "SELECT id, name, parent_id, position, created_at, deleted_at FROM folders WHERE parent_id = ? AND deleted_at IS NULL ORDER BY position",
        bind: { stmt in sqlite3_bind_int64(stmt, 1, parentId) },
        read: readFolder
      )
    } else {
      folders = try query(
        "SELECT id, name, parent_id, position, created_at, deleted_at FROM folders WHERE parent_id IS NULL AND deleted_at IS NULL ORDER BY position",
        read: readFolder
      )
    }
    for (i, folder) in folders.enumerated() {
      let newPosition = Double(i + 1)
      try update(
        "UPDATE folders SET position = ? WHERE id = ?",
        bind: { stmt in
          sqlite3_bind_double(stmt, 1, newPosition)
          sqlite3_bind_int64(stmt, 2, folder.id)
        }
      )
    }
    Log.debug(
      "Renumbered \(folders.count) folder positions under parent=\(parentId.map(String.init) ?? "root")",
      category: .folders
    )
  }

  private func allDescendantFolderIds(of folderId: Int64, includeDeleted: Bool = false) throws
    -> [Int64]
  {
    var result: [Int64] = []
    var queue: [Int64] = [folderId]
    while !queue.isEmpty {
      let current = queue.removeFirst()
      let deletedClause = includeDeleted ? "" : " AND deleted_at IS NULL"
      let children: [Int64] = try query(
        "SELECT id FROM folders WHERE parent_id = ?\(deletedClause)",
        bind: { stmt in sqlite3_bind_int64(stmt, 1, current) },
        read: { stmt in sqlite3_column_int64(stmt, 0) }
      )
      result.append(contentsOf: children)
      queue.append(contentsOf: children)
    }
    return result
  }

  private func readFolder(_ stmt: OpaquePointer) -> Folder {
    Folder(
      id: columnInt64(stmt, 0),
      name: columnText(stmt, 1)!,
      parentId: sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : columnInt64(stmt, 2),
      position: sqlite3_column_double(stmt, 3),
      createdAt: columnDate(stmt, 4),
      deletedAt: columnOptionalDate(stmt, 5)
    )
  }

  // MARK: - Browser

  public func tableNames() throws -> [String] {
    try query(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    ) { stmt in
      columnText(stmt, 0)!
    }
  }

  public func columnNames(table: String) throws -> [String] {
    guard try tableNames().contains(table) else {
      throw DatabaseError.executionFailed("Unknown table: \(table)")
    }
    return try query("PRAGMA table_info(\"\(table)\")") { stmt in
      columnText(stmt, 1)!
    }
  }

  public func rowCount(table: String) throws -> Int {
    guard try tableNames().contains(table) else {
      throw DatabaseError.executionFailed("Unknown table: \(table)")
    }
    let counts = try query("SELECT COUNT(*) FROM \"\(table)\"") { stmt in
      columnInt64(stmt, 0)
    }
    return Int(counts.first ?? 0)
  }

  public func fetchRows(
    table: String,
    limit: Int,
    offset: Int,
    orderBy: String? = nil,
    ascending: Bool = true
  ) throws -> [[String?]] {
    let cols = try columnNames(table: table)
    let colCount = Int32(cols.count)
    var sql = "SELECT * FROM \"\(table)\""
    if let orderBy, cols.contains(orderBy) {
      sql += " ORDER BY \"\(orderBy)\" \(ascending ? "ASC" : "DESC")"
    }
    sql += " LIMIT \(limit) OFFSET \(offset)"
    return try query(sql) { stmt in
      (0..<colCount).map { i in
        columnText(stmt, i)
      }
    }
  }

  // MARK: - Internal helpers

  private func execute(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(db, sql, nil, nil, &error)
    if result != SQLITE_OK {
      let msg = error.map { String(cString: $0) } ?? "unknown error"
      sqlite3_free(error)
      throw DatabaseError.executionFailed(msg)
    }
  }

  @discardableResult
  private func insert(
    _ sql: String,
    bind: (OpaquePointer) -> Void
  ) throws -> Int64 {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
      throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }

    bind(stmt)

    let result = sqlite3_step(stmt)
    guard result == SQLITE_DONE else {
      throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
    }
    return sqlite3_last_insert_rowid(db)
  }

  private func query<T>(
    _ sql: String,
    read: (OpaquePointer) -> T
  ) throws -> [T] {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
      throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }

    var results: [T] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      results.append(read(stmt))
    }
    return results
  }

  private func query<T>(
    _ sql: String,
    bind: (OpaquePointer) -> Void,
    read: (OpaquePointer) -> T
  ) throws -> [T] {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
      throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }

    bind(stmt)

    var results: [T] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
      results.append(read(stmt))
    }
    return results
  }

  @discardableResult
  private func update(
    _ sql: String,
    bind: (OpaquePointer) -> Void
  ) throws -> Int32 {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
      throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
    }
    defer { sqlite3_finalize(stmt) }

    bind(stmt)

    let result = sqlite3_step(stmt)
    guard result == SQLITE_DONE else {
      throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
    }
    return sqlite3_changes(db)
  }

  private func readObject(_ stmt: OpaquePointer) -> StoredObject {
    StoredObject(
      id: columnInt64(stmt, 0),
      hash: ContentHash(hexString: columnText(stmt, 1)!),
      name: columnText(stmt, 2)!,
      createdAt: columnDate(stmt, 3),
      deletedAt: columnOptionalDate(stmt, 4),
      modifiedAt: columnOptionalDate(stmt, 5),
      lastOpenedAt: columnOptionalDate(stmt, 6),
      fileExtension: columnText(stmt, 7) ?? "",
      notes: columnText(stmt, 8)
    )
  }

  private func readTag(_ stmt: OpaquePointer) -> Tag {
    Tag(id: columnInt64(stmt, 0), name: columnText(stmt, 1)!)
  }

  private nonisolated func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
    guard let cString = sqlite3_column_text(stmt, index) else { return nil }
    return String(cString: cString)
  }

  private nonisolated func columnInt64(_ stmt: OpaquePointer, _ index: Int32) -> Int64 {
    sqlite3_column_int64(stmt, index)
  }

  private nonisolated func columnDate(_ stmt: OpaquePointer, _ index: Int32) -> Date {
    let timestamp = sqlite3_column_int64(stmt, index)
    return Date(timeIntervalSince1970: TimeInterval(timestamp))
  }

  private nonisolated func columnOptionalDate(_ stmt: OpaquePointer, _ index: Int32) -> Date? {
    if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
    return columnDate(stmt, index)
  }
}
