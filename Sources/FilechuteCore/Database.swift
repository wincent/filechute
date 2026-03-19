import Foundation
import SQLite3

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
            deleted_at INTEGER
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
    }

    // MARK: - Objects

    public func insertObject(hash: ContentHash, name: String) throws -> Int64 {
        try insert(
            "INSERT INTO objects (hash, name, created_at) VALUES (?, ?, ?)",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, hash.hexString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
            }
        )
    }

    public func getObject(byId id: Int64) throws -> StoredObject? {
        try query(
            "SELECT id, hash, name, created_at, deleted_at FROM objects WHERE id = ?",
            bind: { stmt in sqlite3_bind_int64(stmt, 1, id) },
            read: readObject
        ).first
    }

    public func getObject(byHash hash: ContentHash) throws -> StoredObject? {
        try query(
            "SELECT id, hash, name, created_at, deleted_at FROM objects WHERE hash = ?",
            bind: { stmt in sqlite3_bind_text(stmt, 1, hash.hexString, -1, SQLITE_TRANSIENT) },
            read: readObject
        ).first
    }

    public func allObjects(includeDeleted: Bool = false) throws -> [StoredObject] {
        let sql = includeDeleted
            ? "SELECT id, hash, name, created_at, deleted_at FROM objects ORDER BY name"
            : "SELECT id, hash, name, created_at, deleted_at FROM objects WHERE deleted_at IS NULL ORDER BY name"
        return try query(sql, read: readObject)
    }

    public func renameObject(id: Int64, newName: String) throws {
        try update(
            "UPDATE objects SET name = ? WHERE id = ?",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, newName, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, id)
            }
        )
    }

    public func softDeleteObject(id: Int64) throws {
        try update(
            "UPDATE objects SET deleted_at = ? WHERE id = ?",
            bind: { stmt in
                sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
                sqlite3_bind_int64(stmt, 2, id)
            }
        )
    }

    public func restoreObject(id: Int64) throws {
        try update(
            "UPDATE objects SET deleted_at = NULL WHERE id = ?",
            bind: { stmt in sqlite3_bind_int64(stmt, 1, id) }
        )
    }

    public func permanentlyDeleteObject(id: Int64) throws {
        try update(
            "DELETE FROM objects WHERE id = ?",
            bind: { stmt in sqlite3_bind_int64(stmt, 1, id) }
        )
    }

    // MARK: - Tags

    public func createTag(name: String) throws -> Int64 {
        try insert(
            "INSERT INTO tags (name) VALUES (?)",
            bind: { stmt in sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT) }
        )
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
    }

    public func removeTag(_ tagId: Int64, fromObject objectId: Int64) throws {
        try update(
            "DELETE FROM taggings WHERE object_id = ? AND tag_id = ?",
            bind: { stmt in
                sqlite3_bind_int64(stmt, 1, objectId)
                sqlite3_bind_int64(stmt, 2, tagId)
            }
        )
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

    // MARK: - Search

    public func objects(withTagId tagId: Int64) throws -> [StoredObject] {
        try query(
            """
            SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at
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
            SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at
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

        return try query(sql, read: { stmt in
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
                SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at
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
                SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at
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
            deletedAt: columnOptionalDate(stmt, 4)
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
