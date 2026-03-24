# ADR 007: Application Settings

## Status

Proposed

## Context

Filechute has no application-level preferences. View-state values such as column
visibility and thumbnail size are persisted with `@SceneStorage`, and the recent
stores list lives in `UserDefaults`, but there is no user-facing settings
interface and no mechanism for behaviour-level configuration.

The first concrete need is an "ignored file patterns" list. When importing a
directory tree, macOS housekeeping files such as `.DS_Store` are swept up along
with the intended content. Users have no way to exclude them, and they inflate
the progress count.

The design should accommodate additional settings in the future without
requiring architectural changes.

## Decision

### Settings window

Add a SwiftUI `Settings` scene to `FilechuteApp.body`. This gives Cmd+,
handling and the standard macOS preferences window lifecycle for free.

Use a `TabView` (or, on macOS 15+, the settings-specific tab style) so that
future categories can be added as tabs. The initial implementation has a single
**Import** tab.

### Storage

Store all settings in `UserDefaults` via `@AppStorage`. Settings are global --
they apply to every store, not per-store. The app already uses `UserDefaults`
for recent stores and last-active store, so this is consistent.

Key: `ignoredFilePatterns`, type: `[String]`, default value: `[".DS_Store"]`.

Because `@AppStorage` does not natively support `[String]`, store the value as
JSON-encoded `Data` with a lightweight property wrapper or `RawRepresentable`
conformance.

### Ignored file patterns -- UI

The Import tab contains:

- A `List` showing current patterns, each with a remove button.
- A text field and "Add" button for new entries.
- Validation: reject empty strings and strings containing `/` or `:` (patterns
  match filenames only, not paths).

### Ignored file patterns -- matching

Patterns support a single wildcard character `*` meaning "zero or more of any
character". No other glob operators (`?`, `[...]`, `**`) are required.

Matching is implemented with `fnmatch(3)` (passing `FNM_NOESCAPE` so that
backslash is literal). `fnmatch` is available in Darwin's C library, requires
no dependencies, and already implements `*` semantics. A filename is ignored if
it matches any pattern in the list.

### Import filtering

Add a helper function that checks a filename against the current ignore list:

```swift
func shouldIgnoreFile(named name: String) -> Bool
```

Apply it in two places in `StoreManager`:

1. **`countFiles(at:visitedPaths:)`** -- skip ignored filenames so the progress
   total reflects only the files that will actually be imported.
2. **`ingestDirectoryRecursive(at:parentFolderId:visitedPaths:)`** -- skip
   ignored files so they are never stored.

Single-file imports via `ingest(urls:)` are **not** filtered. When a user
explicitly selects files (via the file picker or drag-and-drop), the selection
is respected regardless of the ignore list. The ignore list targets automatic
directory traversal only.

Directory traversal continues to recurse into all subdirectories; the ignore
list applies to leaf files, not to directory names.

### Progress dialog

`countFiles()` already excludes directories from the count (only the non-directory
branch increments). After adding ignore-list filtering the progress total will
accurately reflect importable files.

## Consequences

- Users get a standard Cmd+, settings window from day one, even though there
  is only one setting initially. Adding future tabs is a one-line change.
- `.DS_Store` files are excluded by default. Users who import from Windows
  volumes can add `Thumbs.db`, `desktop.ini`, etc.
- Glob patterns (`*.tmp`, `.*`) give power users flexibility without requiring
  regex knowledge.
- Settings are global. If per-store overrides are needed later, the ignore list
  can be moved to the store database while keeping the global list as a default.
- `fnmatch(3)` is case-sensitive on APFS. This is intentional -- macOS
  filenames preserve case, and `.DS_Store` is always capitalised that way. If
  case-insensitive matching is needed later, `FNM_CASEFOLD` can be added.

## Alternatives Considered

- **Per-store ignore lists in the database**: More flexible but adds schema
  changes and UI complexity for a setting that is almost always the same across
  stores. Global-first with optional per-store overrides later is simpler.
- **Regex patterns**: More powerful but harder for non-technical users to write
  correctly. `fnmatch`-style globs cover the practical use cases.
- **Hardcoded ignore list with no UI**: Quickest to implement but not
  extensible and gives users no control.
- **Filtering single-file imports too**: Considered but rejected. If a user
  explicitly selects a file, they presumably want it imported regardless of its
  name.
