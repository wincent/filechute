# ADR 008: Database Browser

## Status

Proposed

## Context

Filechute stores all metadata in a per-store SQLite database (`filechute.db`).
During development and troubleshooting it is useful to inspect the raw database
contents -- verifying that tags were written correctly, checking foreign key
relationships, or confirming migration state. Today this requires an external
tool such as the `sqlite3` CLI or a third-party GUI, and the developer must
locate the correct `.db` file on disk.

The existing Debug menu already provides a log window. A database browser would
complement it by exposing the data layer with the same zero-friction access.

## Decision

### Menu item

Add a "Databases" item to the existing `CommandMenu("Debug")` in
`FilechuteCommands`. No keyboard shortcut. The item opens a new `Window` scene
(`id: "database-browser"`).

The window is available in all builds (not gated behind `#if DEBUG`) so that it
can also be used to diagnose issues in release builds.

### Window layout

The window uses a custom toolbar-style `HStack` at the top (matching the
pattern established by `LogWindowView`) containing two pickers:

1. **Store picker** -- a `Picker` listing every currently open store by its
   display name. Selection determines which `Database` instance is queried. When
   only one store is open the picker is still shown but has a single entry. If
   no stores are open (all windows closed) the content area shows an empty-state
   message.

2. **Table picker** -- a `Picker` listing the tables in the selected database.
   The table list is obtained dynamically at selection time by querying
   `sqlite_master` (`SELECT name FROM sqlite_master WHERE type='table' ORDER BY
   name`), so that it reflects any future schema additions or migrations without
   code changes.

Below the toolbar is the table content area.

### Table view

Display the selected table's rows in a SwiftUI `Table` (macOS 13+). Columns are
determined dynamically from `PRAGMA table_info(<table>)` so the view adapts to
any table without per-table column definitions.

**Virtual scrolling**: Use `Table` with `LazyVStack`-backed scrolling (SwiftUI's
`Table` already uses lazy row loading). For tables that may be large (e.g.
`objects`, `metadata`) rows are loaded in pages via `LIMIT`/`OFFSET` queries,
fetching the next page as the user scrolls near the bottom. Page size: 200 rows.
Total row count is displayed in a footer bar (e.g. "Showing 400 of 1,234
rows").

**Column formatting**: Known columns that store Unix timestamps (`created_at`,
`modified_at`, `last_opened_at`, `renamed_at`, `deleted_at`) are formatted as
human-readable dates using the user's locale. A tooltip on each formatted cell
shows the raw integer value. All other columns display their raw SQLite value as
a string.

**Read-only**: The table view is not editable. No insert, update, or delete
operations are exposed.

### Accessing open stores

The window needs a reference to every currently open `StoreManager` to get
database handles. Add a registry to `StoreCoordinator` that tracks open
`StoreManager` instances:

```swift
private(set) var openStores: [URL: StoreManager] = [:]
```

`StoreManager` instances register themselves on init and deregister on
`deinit` (or when the window closes), using the store root URL as key.
`StoreCoordinator` is already an `@Observable @MainActor` singleton so the
database browser view can observe it directly.

### Generic query helper

Add a public method to `Database` for the browser's use:

```swift
public func tableNames() async throws -> [String]
public func columnInfo(table: String) async throws -> [(name: String, type: String)]
public func fetchRows(
    table: String,
    limit: Int,
    offset: Int
) async throws -> (columns: [String], rows: [[String?]])
public func rowCount(table: String) async throws -> Int
```

Table and column names are validated against `sqlite_master` /
`PRAGMA table_info` results before being interpolated into SQL, preventing
injection via crafted table names (which is not a realistic attack vector here,
but is good hygiene).

### New files

- `Sources/Filechute/DatabaseBrowserView.swift` -- the window content view
  including toolbar pickers, table display, and paging logic.

### Modified files

- `Sources/Filechute/FilechuteApp.swift` -- add `Window("Databases",
  id: "database-browser")` scene and the menu item in `FilechuteCommands`.
- `Sources/Filechute/StoreCoordinator.swift` -- add `openStores` registry.
- `Sources/Filechute/StoreManager.swift` -- register/deregister with
  `StoreCoordinator.openStores` on init/deinit.
- `Sources/FilechuteCore/Database.swift` -- add the generic query helpers.
- `Filechute.xcodeproj/project.pbxproj` -- add `DatabaseBrowserView.swift`.

## Consequences

- Developers and users can inspect any table in any open store without leaving
  the app or locating the database file on disk.
- The dynamic column/table discovery means no code changes are needed when the
  schema evolves.
- Paged loading keeps memory bounded even for stores with tens of thousands of
  objects.
- Timestamp formatting with raw-value tooltips balances readability with
  precision for debugging.
- The generic query helpers on `Database` are public but narrowly scoped
  (read-only, table-name-validated); they do not expose arbitrary SQL execution.

## Alternatives Considered

- **Embed a full SQL REPL**: More powerful but introduces risk of accidental
  writes to the database. A read-only table browser covers the inspection use
  case without that risk. A query input could be added later if needed.
- **Use an external tool (DB Browser for SQLite, sqlite3 CLI)**: Already
  possible today but requires the user to find the database file path and switch
  context. In-app access is faster and more discoverable.
- **Load all rows at once**: Simpler implementation but risks high memory usage
  and UI stalls for large stores. Paged loading adds modest complexity for
  significantly better scalability.
- **Hardcoded column definitions per table**: Would allow richer formatting but
  requires maintenance whenever the schema changes. Dynamic discovery from
  `sqlite_master` and `PRAGMA table_info` is self-maintaining.
- **Debug-only (`#if DEBUG`)**: Would reduce the surface area of release builds
  but would prevent using the browser to diagnose issues in production. The log
  window sets the precedent of shipping debug tools in all builds.
