# ADR 004: On-Disk Metadata Files

## Status

Accepted

## Context

Filechute stores objects as content-addressed directories (see ADR 002):

```
objects/3f/67d7ba85c7ce6600a325cb292e01ef7a01c65263d72688c67d12b177b21947/
  data.bin
  thumbnail.png
```

If the Filechute application is unavailable, a person browsing the object store
on disk sees opaque `data.bin` files with no indication of what they are, where
they came from, or when they were stored. All metadata lives in the SQLite
database, which requires the application (or at least SQLite tooling) to query.

A human-readable metadata file alongside each object would make the store
self-describing: a user with nothing more than a file browser or `cat` can
understand what each object is.

## Decision

### File format: JSON

JSON is chosen over the alternatives because it satisfies all three criteria:

1. **Human-readable**: Indented JSON is easy to read in any text editor, on the
   command line (`cat`, `jq`), or in a file browser's Quick Look preview.
2. **Zero dependency cost**: Foundation provides `JSONEncoder` with
   `.prettyPrinted` and `.sortedKeys` output formatting. No third-party library
   is needed.
3. **Universally understood**: JSON is the most widely recognized structured
   data format. No special knowledge is needed to interpret it.

### File name

`info.json`, stored alongside `data.bin` and `thumbnail.png`:

```
objects/3f/67d7ba85c7ce6600a325cb292e01ef7a01c65263d72688c67d12b177b21947/
  data.bin
  info.json
  thumbnail.png
```

### Contents

The file contains only immutable properties -- values that are fixed at
ingestion time and never change. This avoids the need to keep the file in sync
with mutable database state.

```json
{
  "content_hash": "sha256:3f67d7ba85c7ce6600a325cb292e01ef7a01c65263d72688c67d12b177b21947",
  "import_date": "2026-03-22T14:30:00Z",
  "mime_type": "image/jpeg",
  "original_name": "vacation-photo.jpg",
  "size_bytes": 2456789
}
```

Fields:

- **`original_name`** (`String`): The file's name (with extension) as it was
  when imported. The display name in the database can be renamed later, but this
  records the original. This is the single most useful piece of information for
  a human trying to identify an opaque `data.bin` file.
- **`import_date`** (`String`, ISO 8601 with timezone): When the object was
  ingested into Filechute. Encoded with `JSONEncoder.DateEncodingStrategy.iso8601`.
- **`content_hash`** (`String`, `sha256:` prefix): The SHA-256 content hash
  that serves as the object's identity in the store. Prefixed with the
  algorithm name so the value is self-describing. A human can verify integrity
  with `shasum -a 256 data.bin` and compare.
- **`size_bytes`** (`Int`): The size of `data.bin` in bytes. Lets a human
  quickly gauge file size without running `ls -l` or `stat`.
- **`mime_type`** (`String`): The MIME type derived from the file extension at
  import time (e.g. `image/jpeg`, `application/pdf`). Tells a human what kind
  of data `data.bin` contains.

Keys are sorted alphabetically (`sortedKeys`) for stable, predictable output.

### What is excluded and why

Mutable state is deliberately omitted:

- **Display name**: Can be renamed after import; `original_name` is the
  immutable counterpart.
- **Tags**: Can be added and removed at any time.
- **Notes**: User-editable text.
- **Deleted/modified/last-opened dates**: Change during the object's lifetime.

These remain queryable from the SQLite database, which is the authoritative
source for mutable metadata.

### Write timing

`info.json` is written once during ingestion, immediately after `data.bin` is
stored and before thumbnail generation. It is never updated. If the file
already exists (e.g. re-ingestion of identical content), it is not overwritten.

### ObjectStore API additions

- New `infoURL(for:)` returns `directory/info.json`.
- New `storeInfo(data:for:)` writes the JSON data.
- New `infoExists(for:)` checks for the file's existence.
- `remove(_:)` already deletes the entire directory, so `info.json` is cleaned
  up with no additional work.

### Encoding

A `Codable` struct (e.g. `ObjectInfo`) with `snake_case` key encoding
(`JSONEncoder.KeyEncodingStrategy.convertToSnakeCase`) keeps the Swift property
names idiomatic while producing the underscore-separated JSON keys shown above.

## Consequences

- Each object directory gains one small JSON file (typically under 300 bytes).
- The object store becomes self-describing: a human can browse and understand it
  without the application or database.
- Because the file is write-once and never read at runtime, there is no
  performance impact on normal operation and no risk of stale data.
- `IntegrityChecker` does not verify `info.json` -- it is derived,
  informational data, not part of the content-addressable identity.

## Alternatives Considered

- **XML property list**: Foundation supports `PropertyListEncoder`, but XML
  plists are verbose (`<key>`, `<string>` tags) and less immediately readable
  than JSON for this use case.
- **YAML**: More compact than JSON for simple structures, but Swift has no
  built-in YAML encoder. Adding a third-party dependency for a write-only
  informational file is not justified.
- **Plain text (key: value)**: Maximum readability, but no standard format means
  ad-hoc parsing if the data is ever consumed programmatically. JSON is nearly
  as readable and universally parseable.
- **Include mutable fields and keep in sync**: Would make the file more
  informative, but adds ongoing maintenance burden, risk of staleness, and
  performance cost of writes on every rename, tag change, or note edit. The
  write-once constraint eliminates an entire class of bugs.
