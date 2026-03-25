# ADR 010: Full-Text Search

## Status

Proposed

## Context

Filechute's current search (in `ContentView` and `TrashView`) is an in-memory
filter over already-loaded objects. It splits the query into whitespace-delimited
terms and checks whether every term appears as a substring in the object's name,
tag names, or notes. This has several limitations:

1. **No content search.** A user who stores a PDF of a tax return cannot find it
   by searching for "1099" unless the filename or a tag happens to contain that
   string. The actual text content of stored files is never consulted.
2. **No ranking.** Results are returned in whatever sort order is active (name,
   date, etc.), with no notion of relevance. A query that matches in the title
   should rank higher than one that matches in a note.
3. **Scaling.** The current approach loads all objects into memory and filters
   client-side. This is fine for hundreds or low thousands of objects but will
   degrade as libraries grow.
4. **No fuzzy or linguistic matching.** The substring check is case-insensitive
   but otherwise exact: no stemming, no prefix matching, no typo tolerance.

Adding full-text search would let users find objects by the text content of their
files, in addition to the metadata fields already searched today.

## Decision

### Use SQLite FTS5

SQLite ships an FTS5 extension that provides full-text indexing with relevance
ranking, prefix queries, phrase matching, and column weighting. Since the app
already uses SQLite (via the C API) as its primary database, FTS5 adds no new
dependencies.

FTS5 is compiled into the system SQLite on macOS and is available without
additional build flags.

### Schema

Add an FTS5 virtual table alongside the existing schema:

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
    name,
    tags,
    notes,
    content_text,
    tokenize='porter unicode61'
);
```

Column descriptions:

- **`name`**: The object's display name.
- **`tags`**: Space-separated tag names for the object (denormalized from the
  taggings/tags join).
- **`notes`**: The user's notes field.
- **`content_text`**: Extracted text content from the file itself (see "Text
  extraction" below).

This is a regular (content-storing) FTS5 table rather than an external content
table. An external content table (`content=objects`) would avoid duplicating
name/notes data, but the `tags` column is computed from a join across
`taggings` and `tags` and does not exist on the `objects` table. A regular
FTS5 table avoids this mismatch at the cost of modest storage duplication.

The `porter unicode61` tokenizer applies Porter stemming (so "invoices" matches
"invoice") and Unicode-aware tokenization.

### Text extraction

Extracting searchable text from stored files at ingestion time, using
platform-provided frameworks:

| File type                                                 | Extraction method                                       |
| --------------------------------------------------------- | ------------------------------------------------------- |
| PDF                                                       | `PDFDocument` (PDFKit) `.string` property               |
| Plain text (`.txt`, `.md`, `.csv`, `.json`, `.xml`, etc.) | Read as UTF-8 string                                    |
| RTF / RTFD                                                | `NSAttributedString(url:documentAttributes:)` `.string` |
| Word (`.docx`)                                            | `NSAttributedString(url:documentAttributes:)`           |
| Images                                                    | No text extraction (future: OCR via Vision framework)   |
| Audio / Video                                             | No text extraction                                      |
| Other                                                     | No text extraction; rely on name/tag/notes matching     |

Extracted text is stored in a new column on the `objects` table:

```sql
ALTER TABLE objects ADD COLUMN content_text TEXT
```

This column is populated during ingestion and is not user-visible. It serves
only as the backing data for the FTS index. Text is truncated to a reasonable
limit (e.g. 100 KB) to avoid unbounded storage for very large documents.

If ADR 003 (LLM auto-tagging) is implemented, its `TextExtractor` component
should be shared with this feature to avoid duplicating extraction logic.

### Indexing

**At ingestion time**: After `data.bin` is written and before thumbnail
generation completes, `IngestionService` extracts text content and writes it to
the `content_text` column. A corresponding FTS index insert is performed in the
same transaction.

**Keeping the index in sync**: The FTS index must be updated whenever searchable
fields change:

- Object renamed -> update `name` in FTS.
- Tag added/removed -> update `tags` in FTS.
- Notes edited -> update `notes` in FTS.
- Object deleted -> remove from FTS.

These updates are handled by adding FTS maintenance calls to the existing
`Database` methods (`renameObject`, `addTag`, `removeTag`, `updateNotes`,
`softDeleteObject`, etc.). Each method already writes to `objects`/`taggings`;
the FTS update is an additional statement in the same logical operation.

No backfill migration is needed. Existing stores will be recreated from
scratch, so every object passes through the ingestion pipeline and gets indexed
on import.

### Query API

A new `Database` method:

```swift
public func search(_ query: String, limit: Int = 100) throws -> [StoredObject]
```

This issues an FTS5 `MATCH` query with `bm25()` ranking:

```sql
SELECT o.id, o.hash, o.name, o.created_at, o.deleted_at, o.modified_at,
       o.last_opened_at, o.file_extension, o.notes
FROM search_index si
JOIN objects o ON o.id = si.rowid
WHERE search_index MATCH ? AND o.deleted_at IS NULL
ORDER BY bm25(search_index, 10.0, 5.0, 3.0, 1.0)
LIMIT ?
```

The `bm25()` weights (name=10, tags=5, notes=3, content_text=1) bias results
toward metadata matches, with content matches as a fallback. These weights are
tunable.

The query string is sanitized to escape FTS5 special characters. Users can type
natural queries ("tax return 2024") and the tokenizer handles the rest. Advanced
FTS5 syntax (phrase queries with `"..."`, column filters with `name:`, prefix
with `*`) could be exposed later but is not required initially.

### UI integration

The existing `SearchField` and `searchText` binding remain. The change is in how
results are computed:

- **Empty query**: Behavior is unchanged (show all objects in the current view,
  sorted by the active sort order).
- **Non-empty query**: Instead of the current in-memory filter, call
  `Database.search()` and display results ranked by relevance. The active sort
  order is overridden to "relevance" while a search is active, matching the
  convention in Finder, Mail, and other macOS apps.

Search is debounced (e.g. 150ms after the last keystroke) to avoid issuing a
query on every character.

### Architecture

One new component, plus modifications to existing code:

**`TextExtractorService`** (`Sources/FilechuteCore/TextExtractorService.swift`)
-- extracts text from files based on their UTType. Returns an optional `String`
(nil for unsupported types). Stateless, so it can be a struct with static
methods.

**`Database`** -- new migration to add `content_text` column and
`search_index` FTS table. New `search()` method. FTS sync calls added to
existing mutation methods.

**`IngestionService`** -- calls `TextExtractorService` during ingestion to
populate `content_text`.

**`ContentView` / `TrashView`** -- switch from in-memory filtering to
`Database.search()` when `searchText` is non-empty.

### Expected performance

FTS5's inverted index is a B-tree. Query cost is proportional to the number of
matching posting lists (i.e. the number of search terms), not the total corpus
size.

**Query latency**:

- Up to ~1M rows with short indexed text (names, tags, notes): sub-5ms queries.
- Up to ~100K rows with the 100 KB `content_text` cap (~10 GB raw indexed
  text): sub-10ms queries.
- These are conservative; benchmarks regularly show FTS5 handling several
  million rows before queries cross 50ms.

For a personal document store that is unlikely to exceed tens of thousands of
objects, FTS5 queries will be effectively instant.

**Where degradation begins**:

- `bm25()` ranking visits every matching row to score it, so a very common term
  in a very large corpus can be slow. In practice users search for specific
  terms, not stop words, and the `LIMIT` clause bounds result-set construction.
- Insert/update throughput is the more likely bottleneck: each FTS insert
  tokenizes the full text and updates the inverted index, adding tens of
  milliseconds per large document during ingestion. This cost is paid at import
  time, not query time.

**Index size on disk**: Typically 10-30% of the raw indexed text. With 100K
objects at the 100 KB cap (10 GB raw text), the FTS index would be ~1-3 GB.
SQLite handles this without issue, but it contributes to overall database file
size.

**Tuning levers if needed**: Reduce the `content_text` cap, adjust FTS5's
`automerge` parameter to control index segment management, or drop
`content_text` weighting to zero in `bm25()` to skip content scoring entirely
while still matching on it.

## Consequences

- Search now covers file content, not just metadata. Users can find documents by
  what they contain.
- The FTS index adds modest storage overhead (typically 10-30% of the indexed
  text size for the inverted index).
- The `content_text` column stores extracted text, adding storage proportional to
  the text content of the library. The 100 KB per-object cap bounds worst-case
  growth.
- Ingestion becomes slightly slower due to text extraction (negligible for most
  files; PDFs with many pages may take tens of milliseconds).
- The `porter unicode61` tokenizer provides stemming for English. For
  multilingual libraries, the `unicode61` component handles tokenization
  correctly, but stemming is English-only. This is a reasonable starting point;
  ICU tokenization could be added later if needed.
- Images and media files remain unsearchable by content. OCR (via the Vision
  framework's `VNRecognizeTextRequest`) could be added as a future enhancement,
  reusing the same `content_text` column and FTS infrastructure.

## Alternatives Considered

- **Keep in-memory filtering, add text content to the model**: Loads extracted
  text into memory for every object and filters with `String.contains`. Simple
  to implement but does not scale, provides no ranking, and wastes memory
  holding text content that is rarely needed.
- **Spotlight integration (`CSSearchableIndex`)**: Lets the system index
  Filechute content and surface it in Spotlight. Appealing for system-wide
  search, but gives the app little control over ranking, UI, or query semantics.
  Spotlight integration could complement FTS5 (for system-wide discoverability)
  but should not replace in-app search.
- **Standalone search library (e.g., Tantivy via Swift bindings)**: More
  powerful than FTS5 (better ranking, faceting, custom analyzers), but adds a
  non-trivial dependency and a second storage engine. The marginal benefit over
  FTS5 does not justify the complexity for this use case.
- **FTS5 with external content (`content=objects`)**: Would avoid storing a
  second copy of name/notes in the FTS table, but the `tags` column is computed
  from a join and does not exist on `objects`. A regular FTS5 table is simpler
  and the storage overhead from duplicating name/notes is negligible.
- **Server-side search (e.g., Meilisearch, Typesense)**: Filechute is a
  local-first desktop app. Running a search server process contradicts that
  model and adds deployment complexity for no benefit.
