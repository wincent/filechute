# ADR 002: Thumbnail Generation and Preview Mode

## Status

Accepted

## Context

Filechute currently displays stored objects in a table view showing name, type,
and dates. For visual file types (images, PDFs, videos), users cannot see what a
file contains without opening it or using QuickLook. A thumbnail grid view would
let users visually browse their files.

The object store currently uses a flat file layout where each content-addressable
object is a single file:

```
objects/3f/67d7ba85c7ce6600a325cb292e01ef7a01c65263d72688c67d12b177b21947
```

Thumbnails need to live alongside their source data without disrupting content
hashing or deduplication.

## Decision

### Storage layout change

Convert each object path from a file to a directory containing:

```
objects/3f/67d7ba85c7ce6600a325cb292e01ef7a01c65263d72688c67d12b177b21947/
  data.bin         # the original file content (unchanged bytes)
  thumbnail.png    # generated thumbnail (optional)
```

The content hash continues to be computed from the bytes in `data.bin` only. The
thumbnail is derived data and is not part of the content-addressable identity.

### Thumbnail generation

A new `ThumbnailService` in `FilechuteCore` generates thumbnails using Apple's
`QuickLookThumbnailing` framework (`QLThumbnailGenerator`). This framework
handles images, PDFs, videos, and many document types natively.

Parameters:

- **Max size**: 1024 pixels on the longest side, preserving aspect ratio. Large
  enough for crisp rendering on Retina displays and zoom-in scenarios; bounded
  to keep disk and memory usage reasonable.
- **Format**: PNG. Lossless, supports transparency, and `QLThumbnailGenerator`
  can produce `CGImage` output that `NSBitmapImageRep` writes as PNG.
- **When generated**: At ingestion time. `IngestionService.ingest` calls
  `ThumbnailService.generateThumbnail(for:hash:)` after storing the object data.
  Generation failures are logged but do not fail ingestion -- not all file types
  produce thumbnails.
- **Backfill**: On launch, a background task scans for objects that have
  `data.bin` but no `thumbnail.png` and generates missing thumbnails. This
  covers objects ingested before the feature existed and file types that gain
  QuickLook support in future OS updates.

### ObjectStore API changes

- `url(for:)` returns the directory URL (currently returns the file URL).
- New `dataURL(for:)` returns `directory/data.bin`.
- New `thumbnailURL(for:)` returns `directory/thumbnail.png`.
- `read(_:)` reads from `dataURL(for:)`.
- `store(fileAt:)` and `store(data:)` write to `data.bin` inside the directory.
- `exists(_:)` checks for the directory's existence.
- `remove(_:)` removes the entire directory.
- New `storeThumbnail(data:for:)` writes `thumbnail.png`.
- New `thumbnailExists(for:)` and `readThumbnail(for:)` accessors.

`FileAccessService`, `GarbageCollector`, `IntegrityChecker`, and
`IngestionService` consume the updated API. `GarbageCollector.remove` already
calls `objectStore.remove(_:)`, which will delete the directory and its contents.

### UI: view mode toggle

A new toolbar item switches between table mode and preview (thumbnail grid)
mode. The state is persisted via `@SceneStorage`.

- **Table mode**: The existing `Table` view, unchanged.
- **Preview mode**: A `LazyVGrid` of thumbnail images loaded from
  `thumbnailURL(for:)`. Each cell shows the thumbnail (or a file-type icon
  placeholder if no thumbnail exists) with the object name below it. Selection,
  context menus, drag-and-drop, and QuickLook all work identically to table
  mode.

Thumbnails are loaded from disk as `NSImage` using an in-memory `NSCache` keyed
by `ContentHash` to avoid redundant I/O. The cache is bounded and evicts
automatically under memory pressure.

### Toolbar item

A segmented control or paired buttons in the toolbar (using
`systemImage: "list.bullet"` and `systemImage: "square.grid.2x2"`) allows
switching between modes. Keyboard shortcut: Cmd+1 for table, Cmd+2 for preview.

## Consequences

- The on-disk layout changes from a file per object to a directory per object.
  All code that constructs object paths must use the new API; direct path
  construction outside `ObjectStore` is already absent in the codebase.
- Thumbnail generation adds a dependency on `QuickLookThumbnailing` (system
  framework, no external dependency).
- Disk usage increases per object (one PNG file, typically 30-200 KB at up to
  1024px).
- The backfill task runs on a background queue and does not block the UI.
- Files without QuickLook support show a generic icon placeholder, which is the
  same behavior as Finder.

## Alternatives Considered

- **Store thumbnails in a separate directory tree**: Keeps the object store flat
  but requires parallel directory management, complicates garbage collection
  (must delete from two locations), and loses the locality benefit of having
  thumbnail and data adjacent on disk.
- **Store thumbnails in the database as BLOBs**: SQLite handles small BLOBs
  well, but 256x256 PNGs are 5-30 KB each and would inflate the database file,
  slow backups, and complicate streaming reads. File-based storage is simpler.
- **Generate thumbnails on demand only (no persistence)**: Avoids disk usage but
  makes grid scrolling slow, especially for PDFs and videos where
  `QLThumbnailGenerator` has non-trivial latency.
- **Use JPEG instead of PNG**: Smaller files but loses transparency. PNG avoids
  visual artifacts on screenshots and icons.
- **Smaller thumbnails (256x256)**: Lower disk usage, but looks soft on Retina
  displays and limits future UI flexibility (e.g. zoom slider, larger grid
  cells).
