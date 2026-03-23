# ADR 006: Virtual Folders in Sidebar

## Status

Proposed

## Context

Filechute's sidebar currently has three fixed sections: the store name, All
Items, and Trash. There is no way to organize items into groups beyond tagging.
Users who manage large libraries need a way to create arbitrary groupings of
items without moving files on disk. Folders provide a familiar, hierarchical
organizational metaphor that complements the existing flat tag-based system.

## Decision

### Terminology

"Folders" are virtual containers that exist only in the SQLite database. They do
not correspond to directories on disk. An item's membership in a folder has no
effect on its storage location.

### Database schema

Two new tables:

**`folders`**

| Column     | Type    | Notes                                   |
| ---------- | ------- | --------------------------------------- |
| id         | INTEGER | Primary key, autoincrement              |
| name       | TEXT    | Not unique (siblings may share names)   |
| parent_id  | INTEGER | FK to `folders.id`, NULL for root-level |
| position   | REAL    | Sort order among siblings               |
| created_at | TEXT    | ISO 8601                                |
| deleted_at | TEXT    | NULL = active; non-NULL = tombstoned    |

**`folder_items`**

| Column     | Type    | Notes              |
| ---------- | ------- | ------------------ |
| folder_id  | INTEGER | FK to `folders.id` |
| object_id  | INTEGER | FK to `objects.id` |
| created_at | TEXT    | ISO 8601           |

Primary key on `(folder_id, object_id)`. Index on `object_id` for reverse
lookups.

`position` is a REAL to allow inserting between two items without rewriting
all sibling positions (e.g. inserting between 1.0 and 2.0 gets position 1.5).
See "Position renumbering" below for how convergence is handled.

Foreign key `parent_id` references `folders.id`. Queries for visible folders
filter `WHERE deleted_at IS NULL`. Deleting a folder tombstones the entire
subtree (the folder and all descendants) so that undo restores the complete
hierarchy.

### Sidebar UI

A new **Folders** section appears in the sidebar below All Items and above
Trash:

```
Store Name
All Items
Folders            [+]
  |-- Work
  |   |-- Receipts
  |   |-- Contracts
  |-- Personal
Trash (3)
```

The `[+]` button creates a new root-level folder named "New Folder" (with a
numeric suffix if needed to avoid ambiguity) and immediately enters rename mode.

Folders with children render as disclosure groups. Clicking a folder filters the
main view to show items that are members of that folder or any of its
descendants, recursively. This means selecting a parent folder gives a complete
view of everything organized under it.

### Folder operations

| Action                   | Trigger                                         |
| ------------------------ | ----------------------------------------------- |
| Create root folder       | Click `[+]` button in Folders header            |
| Create nested folder     | Right-click folder > "New Folder"               |
| Rename folder            | Right-click folder > "Rename"                   |
| Delete folder            | Cmd+Backspace, or right-click > "Delete Folder" |
| Undo delete              | Cmd+Z                                           |
| Reorder / re-nest folder | Drag folder within sidebar                      |

Rename uses the same inline text-field pattern as store renaming in
`SidebarView`. No filesystem validation needed since folders are virtual.

### Drag-and-drop

**Items onto folders:**

- Dragging item(s) from the main list/grid onto a folder in the sidebar adds
  them to that folder. Items may belong to multiple folders, so this is always
  additive.
- Dragging file(s) from Finder onto a folder in the sidebar imports them via
  `IngestionService` and then adds the resulting objects to the folder.

**Removing items from folders:**

- When viewing a folder's contents, right-clicking an item shows a
  "Remove from \"Folder Name\"" context menu option (using the actual folder
  name). This removes the `folder_items` row but does not delete the item from
  the library. If the item appears because it belongs to a descendant folder
  rather than the currently selected folder, the menu item reflects the
  descendant folder name.

**Folders in the sidebar:**

- Dragging a folder reorders it among its siblings.
- Dragging a folder onto another folder nests it inside.
- Dragging a nested folder to the root level un-nests it.
- Drop targets provide visual feedback (highlight, insertion line) to
  distinguish between reordering and nesting.

**Dropping a directory from Finder:**

When a directory (not a `.filechute` bundle) is dropped onto the main view or a
folder, Filechute recursively traverses the directory structure:

1. Import each regular file via `IngestionService`.
2. Create virtual folder(s) mirroring the directory hierarchy.
3. Add imported objects to the corresponding virtual folders.
4. Track visited real paths (via `FileManager.attributesOfItem` /
   `realpath`) to detect and break symlink cycles. Skip any path that
   resolves to an already-visited real path.

If the drop target is a folder, the recreated structure nests inside it.

### Undo support

Folder deletion uses the existing `NSUndoManager` pattern. The `deleted_at`
tombstone approach means undo simply clears the timestamp on the folder and all
its descendants. `folder_items` rows are never deleted when a folder is
tombstoned, so associations survive the round-trip.

Action names: "Delete Folder" / "Restore Folder".

### Database operations

New methods on `Database`:

- `createFolder(name:parentId:position:) -> Folder`
- `renameFolder(id:name:)`
- `moveFolder(id:parentId:position:)`
- `softDeleteFolder(id:)` -- tombstones the folder and all descendants
- `restoreFolder(id:)` -- clears tombstones on the folder and all descendants
- `allFolders() -> [Folder]` -- returns non-deleted folders
- `addItemToFolder(objectId:folderId:)`
- `removeItemFromFolder(objectId:folderId:)`
- `items(inFolder:recursive:) -> [DatabaseObject]` -- when `recursive` is true,
  returns items from the folder and all descendant folders
- `folders(containingObject:) -> [Folder]`

New model: `Folder` (struct, `Identifiable`, `Sendable`, `Hashable`) with
fields matching the table columns.

### StoreManager integration

`StoreManager` gains:

- `@Published`-equivalent `folders: [Folder]` property (refreshed alongside
  existing data in `refresh()`).
- Methods mirroring the `Database` folder operations, following the same pattern
  as existing tag and object management.

### Position renumbering

After each insertion, check whether the gap between the new position and its
nearest neighbor is below a threshold of 1e-6. If so, renumber all siblings
under that parent in a single transaction, assigning positions 1.0, 2.0, 3.0,
etc. in their current sort order. This is O(n) in the number of siblings but
only triggers after many repeated insertions into the same gap (roughly 40+
insertions between two adjacent items before IEEE 754 double precision becomes
problematic). Renumbering is logged at debug level (see "Logging" below).

### Logging

All folder operations are logged via the existing `Log` facade at debug level
with a new `LogCategory.folders` case:

- Folder created (name, parent, position)
- Folder renamed (old name, new name)
- Folder moved (new parent, new position)
- Folder soft-deleted / restored (id, subtree size)
- Item added to / removed from folder (object id, folder id)
- Directory import structure (folder count, item count, any skipped symlinks)
- Position renumbering triggered (parent id, sibling count)

### Migration

A new migration step creates the `folders` and `folder_items` tables. Follows
the existing `applyMigrations()` pattern in `Database`.

## Consequences

- The sidebar grows a dynamic section that scales with user organization needs.
- The many-to-many relationship between items and folders means items are never
  "moved" -- only associated. This avoids confusion about where an item "lives".
- Tombstone-based deletion means the `folders` table grows monotonically. This
  is acceptable for the expected scale (hundreds, not millions, of folders).
  `GarbageCollector` could optionally purge old tombstoned folders in the future.
- Symlink cycle detection during directory import adds a small overhead per
  directory traversal but prevents infinite loops.
- The `position` REAL column is simple but may accumulate floating-point
  precision issues after many insertions. Automatic renumbering when the gap
  drops below 1e-6 keeps positions healthy without manual intervention.

## Alternatives Considered

- **Folders as filesystem directories**: Rejected because it would require
  moving files on disk, breaking content-addressed storage and complicating
  deduplication.
- **Reusing tags as folders**: Tags are flat and unordered. Trying to overload
  them with hierarchy and ordering would complicate the tag system without
  providing a good folder UX.
- **Integer positions with gap strategy**: Using integers spaced by 1000 and
  renumbering when gaps close. Works but REAL positions are simpler to implement
  and the renumbering logic is the same.
- **Hard delete with separate undo journal**: More complex than tombstoning and
  requires careful transaction management to restore folder-item associations.
