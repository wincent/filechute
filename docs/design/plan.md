# Filechute: Implementation Plan (Draft)

## Overview

Filechute is a native macOS application for tag-based file organization. Files are stored using content-addressable storage (like Git), organized by tags rather than hierarchical folders, and surfaced through an iTunes-style column browser UI. Phase 1 delegates synchronization to an external tool (Resilio Sync, Dropbox, etc.); Phase 2 adds native sync via encrypted cloud storage.

This plan covers Phase 1 only.

## Technology choices

- **Language**: Swift
- **UI framework**: SwiftUI (custom column browser built from scratch; AppKit interop where needed)
- **Storage backend**: SQLite (via raw C API) for the index/metadata database
- **Object store**: Flat files on the local filesystem, content-addressed by hash
- **Hash function**: SHA-256
- **Minimum deployment target**: macOS 26

## Architecture

```
┌─────────────────────────────────────────────┐
│                  SwiftUI UI                 │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Column   │  │ Item     │  │ Detail /  │  │
│  │ Browser  │  │ List     │  │ Preview   │  │
│  └──────────┘  └──────────┘  └───────────┘  │
├─────────────────────────────────────────────┤
│               ViewModel layer               │
├─────────────────────────────────────────────┤
│               Domain / Services             │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Ingestion│  │ Tag      │  │ Search    │  │
│  │ Service  │  │ Service  │  │ Service   │  │
│  └──────────┘  └──────────┘  └───────────┘  │
├─────────────────────────────────────────────┤
│               Persistence layer             │
│  ┌──────────────────┐  ┌─────────────────┐  │
│  │ SQLite Index     │  │ Object Store    │  │
│  │ (tags, metadata) │  │ (content blobs) │  │
│  └──────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────┘
```

## Data model

### Object store

Files stored at: `<store-root>/objects/<first-2-hex>/<remaining-hex>`

Example: a file hashing to `a79065aca746c25342a83183d5e9a56262d1d826` is stored at `objects/a7/9065aca746c25342a83183d5e9a56262d1d826`.

Objects are immutable once written.

### SQLite schema (initial)

```sql
CREATE TABLE objects (
    id INTEGER PRIMARY KEY,
    hash TEXT NOT NULL UNIQUE,
    created_at INTEGER NOT NULL  -- unix timestamp
);

CREATE TABLE tags (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE
);

CREATE TABLE taggings (
    object_id INTEGER NOT NULL REFERENCES objects(id),
    tag_id INTEGER NOT NULL REFERENCES tags(id),
    created_at INTEGER NOT NULL,
    PRIMARY KEY (object_id, tag_id)
);
CREATE INDEX idx_taggings_tag ON taggings(tag_id);

CREATE TABLE metadata (
    object_id INTEGER NOT NULL REFERENCES objects(id),
    key TEXT NOT NULL,
    value TEXT,
    PRIMARY KEY (object_id, key)
);
CREATE INDEX idx_metadata_key_value ON metadata(key, value);

-- Tracks version history: when an object is edited, a new object is
-- created and the old one is linked as a predecessor.
CREATE TABLE versions (
    object_id INTEGER NOT NULL REFERENCES objects(id),
    previous_object_id INTEGER NOT NULL REFERENCES objects(id),
    created_at INTEGER NOT NULL,
    PRIMARY KEY (object_id, previous_object_id)
);
CREATE INDEX idx_versions_previous ON versions(previous_object_id);
```

Standard metadata keys: `name`, `extension`, `mime_type`, `size_bytes`, `added_at`, `deleted_at` (tombstone).

Tags are case-insensitive and flat (no namespaces or hierarchies).

## Implementation sequence

### Milestone 1: Object store and database

**Goal**: Can ingest files, store them content-addressed, and record metadata/tags in SQLite.

- Set up Xcode project with Swift Package Manager
- Implement `ObjectStore` — hashing (SHA-256), writing blobs to `objects/XX/YY...`, deduplication
- Implement `Database` — SQLite wrapper, schema creation/migration, CRUD for objects, tags, taggings, metadata
- Implement `IngestionService` — given a file URL, hash it, write the blob, create the object record, extract default metadata (original filename, extension, size, timestamps)
- Unit tests for all of the above

### Milestone 2: Minimal UI shell

**Goal**: A window with the basic layout — column browser (top), item list (bottom), and a way to add files.

- Main window layout: split view with column browser on top, item list on bottom
- Drag-and-drop target for ingesting files (onto the window or a dock icon)
- Item list showing objects with name, tags, date added
- Basic tag assignment: select an item, type tag names to add them
- Wire up to the store/database from Milestone 1

### Milestone 3: Column browser and search

**Goal**: The core UX — drilling down through tags via the column browser, plus text search.

- Column browser: leftmost column shows all tags (with counts)
- Clicking a tag populates the next column with tags that co-occur (the self-JOIN query)
- Multiple selection within a column for OR semantics
- Item list filters in response to column browser selections
- Search field: type tag names separated by spaces, AND semantics, live filtering
- Sorting the item list by name, date, etc.

### Milestone 4: Opening and editing files

**Goal**: Can open files from the store in external applications, and re-ingest edited copies.

- Double-click / Cmd-O to open: write a temporary copy with proper filename/extension, open with default app
- "Open with..." context menu
- Watch the temporary file for changes; offer to update the store when modifications are detected
- Version history: editing a file creates a new object linked to the old one via the `versions` table; tags and metadata carry forward; UI to browse and restore previous versions
- Deletion: soft-delete via `deleted_at` tombstone in metadata; hide from default views; provide "trash" view
- GC mechanism to purge tombstoned objects (respects version chains — does not collect objects reachable from live versions)

### Milestone 5: Smart tagging and polish

**Goal**: Reduce friction of tagging to near-zero.

- Auto-suggest tags based on simple heuristics: file extension/type, existing tags in the store, filename tokens (OCR and LLM-based suggestions are a future goal, not Phase 1)
- Tag autocomplete when typing
- Batch tagging (select multiple items, apply tags)
- Quick Look preview in a detail pane or popover
- Keyboard navigation throughout the column browser and item list (arrow keys, tab between columns, type-ahead)
- Menu bar, toolbar, standard macOS keyboard shortcuts
- VoiceOver accessibility throughout: labels on all interactive elements, proper focus management, rotor support in the column browser and item list

### Milestone 6: Robustness

**Goal**: Trustworthy enough for real use.

- `fsck` command: walk the object store, verify hashes match contents, check for orphaned objects or dangling references in the index
- Database integrity checks
- Backup/export of the store
- Handle edge cases: zero-byte files, very large files, files with no extension, Unicode filenames

## Store location

Store root is **not user-configurable** (to keep Mac App Store sandboxing simple). The app manages stores within its own container.

Default store: `~/Library/Application Support/dev.wincent.Filechute/stores/<store-id>/`

Each store has the structure:

```
<store-id>/
├── objects/
│   ├── 00/
│   ├── 01/
│   │   └── 3fa8b...
│   ├── ...
│   └── ff/
├── filechute.db          # SQLite database
└── tmp/                  # Temporary copies for opening/editing
```

A top-level `stores.json` (or similar) in the Application Support directory tracks the list of stores with their display names.

Multiple stores are supported from the start — e.g., a user might have separate stores for "Personal" and "Work" documents.

## Testing strategy

Testing is a first-class concern. The codebase will be developed with an AI coding agent, making comprehensive test coverage essential for confidence in correctness.

### Layers

1. **Unit tests (Swift Testing framework)** — the bulk of coverage.
   - `ObjectStore`: hashing, writing, deduplication, reading back, handling of zero-byte files, large files, Unicode filenames.
   - `Database`: schema creation, all CRUD operations, the self-JOIN tag drill-down query, metadata queries, version chain traversal, tombstoning and GC. Use in-memory SQLite (`:memory:`) for speed.
   - `IngestionService`: end-to-end ingest of files into a temporary store, metadata extraction, tag suggestion heuristics.
   - `SearchService`: tag intersection, tag union, text search, sorting.
   - All services use protocol-based dependencies so they can be tested with in-memory or temporary-directory backends.

2. **Integration tests** — verify that the layers work together.
   - Ingest a file, tag it, search for it, open it, edit it, verify the version chain.
   - Multi-store scenarios.
   - `fsck` on a known-good store, and on a deliberately corrupted one.

3. **UI tests (XCTest UI testing)** — cover the critical user flows.
   - Drag-and-drop ingestion.
   - Column browser navigation: click a tag, verify next column populates, verify item list filters.
   - Search field: type tags, verify results.
   - Open a file, verify it launches.
   - Accessibility audit: verify VoiceOver labels are present on all interactive elements.

4. **Accessibility tests** — use `accessibilityIdentifier` on all interactive views; write assertions that key elements are reachable and labeled.

### Conventions

- Every public type and method in the persistence and service layers has corresponding tests.
- Tests use temporary directories (cleaned up in teardown) for any on-disk state.
- Tests are fast: no network, no sleeps, in-memory SQLite where possible.
- The Swift Testing framework (`import Testing`, `@Test`, `#expect`) is preferred over XCTest for unit and integration tests. XCTest is used only for UI tests (where it is required).

## Resolved decisions

For reference, the following decisions were made during planning:

1. **Column browser**: Custom SwiftUI implementation built from scratch (not NSBrowser).
2. **SQLite**: Raw C API, no third-party wrapper.
3. **Store location**: Not user-configurable (for App Store sandboxing compatibility). Multiple named stores supported.
4. **Tag semantics**: Case-insensitive, flat (no namespaces or hierarchies).
5. **Sync conflicts**: Deferred to Phase 2.
6. **Smart tagging**: Simple heuristics in Phase 1 (filename tokens, extension, existing tags). OCR and LLM-based suggestions planned for later.
7. **File size**: No limits.
8. **Bulk import**: Not in scope for Phase 1.
9. **Versioning**: Old versions are preserved. Users can browse history and restore previous versions.
10. **Distribution**: Both Mac App Store and direct download (notarized). Design for sandboxing from the start.
11. **Accessibility**: Full VoiceOver support from the start.
12. **Testing**: Comprehensive coverage across unit, integration, and UI layers (see above).
