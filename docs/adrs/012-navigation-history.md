# ADR 012: Unified Navigation Model and History

## Status

Proposed

## Context

Filechute has three filtering mechanisms that currently operate independently:

1. **Sidebar** -- selects between All Items, individual folders, and Trash
   (`NavigationSection` in `SidebarView`).
2. **Column browser** -- progressively narrows the visible objects by selecting
   tags across columns (`ColumnBrowserView`, `BrowserColumn`).
3. **Search** -- full-text search via the `SearchField` in the toolbar
   (`searchText` / `searchResults`).

These three axes do not compose today. In `ContentView.displayedObjects`, the
precedence is `searchResults ?? folderObjects ?? filteredObjects ??
storeManager.objects` -- each axis overrides rather than intersecting with the
others. Concretely:

- Selecting a folder shows that folder's objects, but the column browser still
  shows all tags across the entire store (via `storeManager.allTags`). Selecting
  a tag then replaces the folder view entirely instead of narrowing within it.
- Searching always queries the full store. A user who navigates to a folder and
  then types a query sees results from all folders, losing their context.
- Navigating to a different folder does not reset the column browser, so stale
  tag selections from a previous folder can linger.

Additionally, there is no way to return to a previous navigation state. Users
who drill into a tag intersection and then switch folders lose their place. In
Finder, Mail, and most macOS document browsers, forward/back buttons provide
this affordance.

This ADR addresses both problems together because fixing the interaction model
requires lifting navigation state into `ContentView`, which is also the
prerequisite for history tracking.

## Decision

### Part 1: Unified filtering model

#### Filtering as intersection

The three axes compose as a pipeline. At each stage, the result set can only
narrow:

```
all objects in store
    → scoped by folder (if a folder is selected)
    → scoped by tags (if any tags are selected in the column browser)
    → scoped by search query (if the search field is non-empty)
```

The final result is the intersection of all active constraints. When no folder
is selected (All Items), the folder stage is a pass-through. When no tags are
selected, the tag stage is a pass-through. When the search field is empty, the
search stage is a pass-through.

#### Folder selection resets the column browser

Changing `sidebarSelection` clears all column browser tag selections. The
rationale: tags are contextual to the objects visible in the current folder. A
tag selection made in "All Items" is not meaningful when the user switches to a
specific folder, because the tag may not even apply to any objects there.

#### Column browser scoped to folder

The column browser's root column currently shows `storeManager.allTags`. After
this change, it shows only tags that appear on objects within the selected
folder (and its subfolders). When "All Items" is selected, this is all tags
as before.

Similarly, when the user selects tags to produce refinement columns, the
`reachableTags` computation is scoped to the current folder. This requires
extending the `Database` query methods:

```swift
public func reachableTags(
    from tagIds: [Int64],
    inFolder folderId: Int64? = nil
) throws -> [TagCount]

public func objects(
    withAllTagIds tagIds: [Int64],
    inFolder folderId: Int64? = nil
) throws -> [StoredObject]
```

When `folderId` is non-nil, these methods add a join through `folder_items`
(and the recursive folder CTE for subfolders) to restrict results to objects
in that subtree.

#### Search scoped to current navigation state

The `Database.search()` method gains optional folder and tag parameters:

```swift
public func search(
    _ queryText: String,
    inFolder folderId: Int64? = nil,
    withAllTagIds tagIds: [Int64] = [],
    limit: Int = 100
) throws -> [StoredObject]
```

When `folderId` is provided, the FTS query joins through `folder_items` (with
recursive subtree expansion) to restrict matches. When `tagIds` is non-empty,
it adds the existing tagging joins. The FTS `MATCH` and `bm25()` ranking
operate on this pre-narrowed set.

In `ContentView`, `performSearch` passes the current `sidebarSelection`
folder ID and the current tag selections to `search()`, so results are always
scoped to what the user is looking at.

#### Contextual empty states

When the intersection of all active constraints yields zero results, the empty
state should tell the user *why* the list is empty and *where* matching items
exist, if any. The exact subtitle depends on which constraints are excluding
results.

**Computing hidden-item counts.** When the displayed result set is empty and a
search query is active, run up to two additional count-only queries to
determine where matches would appear if constraints were relaxed:

```swift
public func searchCount(
    _ queryText: String,
    inFolder folderId: Int64? = nil,
    withAllTagIds tagIds: [Int64] = []
) throws -> Int
```

This is a `SELECT COUNT(*)` variant of the existing `search()` query --
cheaper than fetching full result rows since we only need the number.

Given the current constraints (folder F, tags T, query Q) produced zero
results, compute:

- `relaxFolder` = `searchCount(Q, folderId: nil, tagIds: T)` -- matches if
  we drop the folder constraint.
- `relaxTags` = `searchCount(Q, folderId: F, tagIds: [])` -- matches if we
  drop the tag constraint.
- `relaxBoth` = `searchCount(Q, folderId: nil, tagIds: [])` -- matches if
  we drop both.

These are only needed when both a folder and tags are active. When only one
constraint is active, a single relaxed query suffices.

**Empty state messages by scenario:**

| Folder active | Tags active | Search active | Condition | Title | Subtitle |
|---|---|---|---|---|---|
| any | any | no | folder is empty | No Items | -- |
| any | any | yes | `relaxBoth == 0` | No Results | Check the spelling or try a new search |
| yes | no | yes | `relaxFolder > 0` | No Results | Not showing N items in other folders |
| no | yes | yes | `relaxTags > 0` | No Results | Not showing N items with other tags |
| yes | yes | yes | `relaxFolder > 0 && relaxTags == 0` | No Results | Not showing N items in other folders |
| yes | yes | yes | `relaxFolder == 0 && relaxTags > 0` | No Results | Not showing N items with other tags |
| yes | yes | yes | `relaxFolder > 0 && relaxTags > 0` | No Results | Not showing N items in other folders or with other tags |

In the last row, N = `relaxBoth` (the total number of matches anywhere in the
store). In all other rows showing N, N is the value from the single relaxed
query that was non-zero.

**Performance.** The count queries are only issued when the primary search
returns zero results, which is the uncommon path. The `COUNT(*)` variant
avoids materializing result rows. FTS5 count queries over a pre-narrowed
set should be sub-millisecond for typical store sizes.

**Non-search empty states.** When no search query is active and the list is
empty (e.g. an empty folder with no tag selection), the existing empty state
("No Items" or the drop-files prompt for a completely empty store) is
sufficient. No hidden-item hint is shown because the user has not expressed a
query that could match elsewhere -- the folder is simply empty.

#### Replacing the three-variable model

The current `ContentView` state:

```swift
@State private var filteredObjects: [StoredObject]?   // from column browser
@State private var folderObjects: [StoredObject]?     // from folder selection
@State private var searchResults: [StoredObject]?     // from search
```

is replaced by a single computed pipeline. `ContentView` owns the navigation
state (sidebar selection + tag selections) and computes `displayedObjects` by
querying the database with all active constraints. Search results overlay
this only when the search field is non-empty, and the search itself is
scoped to the same constraints.

The column browser's `columns` state is lifted from `@State` in
`ColumnBrowserView` to a binding owned by `ContentView`, so that
`ContentView` can clear it on folder changes and read it for history
snapshots.

### Part 2: Navigation history

#### Navigation state

A value type that captures what gets saved on the history stack:

```swift
struct NavigationState: Equatable {
    var sidebarSelection: NavigationSection?
    var columnSelections: [Set<Int64>]
}
```

`columnSelections` is an ordered list of the tag ID sets selected at each
column browser level (i.e. `columns.map { $0.selectedTagIds }`). An empty
array means no tags are selected.

Search text is deliberately excluded -- see "What does not push" below.

#### History stack

A struct that maintains a linear history with a cursor, modelled after a web
browser's session history:

```swift
struct NavigationHistory {
    private var entries: [NavigationState]
    private var cursor: Int

    var canGoBack: Bool
    var canGoForward: Bool

    mutating func push(_ state: NavigationState)
    mutating func goBack() -> NavigationState
    mutating func goForward() -> NavigationState
}
```

- `push()` appends a new entry after the cursor and discards any forward
  entries beyond it (same as clicking a link after pressing back in a browser).
- `goBack()` / `goForward()` move the cursor and return the entry at the new
  position.
- The stack is initialized with a single entry representing the initial state
  (All Items, no tag selections).

#### What pushes onto the stack

- **Selecting tags in the column browser.** Each call to `selectTags` that
  results in a non-empty tag selection pushes the new navigation state.
  Deselecting all tags (clicking "All") also pushes, since it represents a
  meaningful navigation to a different view.
- **Clicking a folder (or All Items / Trash) in the sidebar.** Changing
  `sidebarSelection` pushes the new state. Because folder changes reset the
  column browser, the pushed state always has an empty `columnSelections`.

#### What does not push

- **Changing the search query.** Search is a transient filter overlaid on the
  current navigation state, not a destination in its own right. Clearing the
  search returns to the same navigation state that was active before the
  search, without polluting the history stack. This matches Finder's behavior,
  where typing in the search field does not create back/forward entries.
- **Changing sort order or view mode.** Display preferences, not navigation.
- **Resizing columns or toggling the inspector.** Layout state, not navigation.

#### Coalescing

Rapid successive changes to the same navigation axis (e.g. clicking through
several tags quickly, or arrowing through sidebar items) should not flood the
stack with intermediate states. Debounce pushes: if a new state arrives within
a short window (e.g. 300ms) of the last push, replace the top entry instead
of pushing a new one.

#### UI

Add back and forward buttons to the toolbar, positioned at the leading edge
(left of the existing toolbar items), following macOS convention:

```swift
ToolbarItem(placement: .navigation) {
    HStack(spacing: 2) {
        Button(action: goBack) {
            Image(systemName: "chevron.backward")
        }
        .disabled(!history.canGoBack)
        .accessibilityIdentifier("nav-back")
        .accessibilityLabel("Back")

        Button(action: goForward) {
            Image(systemName: "chevron.forward")
        }
        .disabled(!history.canGoForward)
        .accessibilityIdentifier("nav-forward")
        .accessibilityLabel("Forward")
    }
}
```

Keyboard shortcuts: Cmd+[ for back, Cmd+] for forward. These are the standard
macOS navigation shortcuts (used by Finder, Safari, Xcode). Add them as menu
commands so the menu system handles the key events (per ADR / project
knowledge about macOS keyboard shortcut routing).

#### Restoring state on back/forward

When the user navigates back or forward, `ContentView` receives the
`NavigationState` from the history stack and applies it:

1. Set `sidebarSelection` to the stored value. If the sidebar selection
   changed, the existing `onChange(of: sidebarSelection)` handler fires, but
   it must not clear the column selections (which would normally happen on
   folder change) because the history entry has specific tag selections to
   restore.
2. Restore the column browser's tag selections from `columnSelections`.
   Because column state is now a binding owned by `ContentView`, this is a
   direct assignment.
3. A `restoringFromHistory` flag suppresses both the column-browser reset
   (from step 1) and the push of a new history entry (to avoid the restored
   state being pushed back onto the stack as a new navigation).

#### Search interaction with back/forward

Navigating back/forward clears the search field. The user returns to the
navigation state as it was before any search was active. This avoids the
ambiguity of restoring a navigation state while a search query is still
filtering the results.

### Architecture

All new types live in `Sources/FilechuteCore/` where they can be unit tested:

- **`NavigationState`** -- the value type.
- **`NavigationHistory`** -- the stack with push/back/forward/coalescing logic.

`ContentView` owns a `@State private var history: NavigationHistory` instance
and wires up the toolbar buttons and state restoration.

### New files

- `Sources/FilechuteCore/NavigationHistory.swift` -- `NavigationState` and
  `NavigationHistory`.

### Modified files

- `Sources/FilechuteCore/Database.swift` -- extend `reachableTags`,
  `objects(withAllTagIds:)`, and `search()` with optional `folderId` and
  `tagIds` parameters.
- `Sources/FilechuteCore/StoreManager.swift` -- extend `search()` to accept
  and forward folder and tag constraints.
- `Sources/Filechute/ContentView.swift` -- replace three-variable filtering
  model with unified pipeline; own column browser state; add history state,
  toolbar buttons, push calls on navigation changes, restoration logic.
- `Sources/Filechute/ColumnBrowserView.swift` -- accept folder-scoped tag
  data and column state as bindings instead of querying and owning them
  internally.
- `Sources/Filechute/FilechuteCommands.swift` -- add Back/Forward menu
  commands with Cmd+[/Cmd+] shortcuts.

## Consequences

- Folder, tag, and search filters compose as intersections. Users see
  consistent, narrowing results regardless of which combination of filters
  they apply.
- The column browser becomes contextual to the selected folder, showing only
  relevant tags. This reduces noise in large stores with many tags.
- Search is always scoped to the current view. Users who navigate to a folder
  and search within it get results from that folder, matching the mental model
  of "search here".
- Navigating to a new folder resets tag selections. This prevents stale tag
  state from a previous context leaking into the new one.
- Users can navigate back and forward through their browsing history within a
  window, matching the affordance provided by Finder and other macOS apps.
- Lifting column browser state and scoping database queries adds complexity to
  both `ContentView` and the `Database` layer, but consolidates navigation
  state in one place, which simplifies reasoning about what the user sees.
- The `Database` query methods gain optional parameters but remain
  backward-compatible (defaults preserve current behavior for callers that
  don't pass folder/tag constraints).
- The coalescing window prevents the history stack from growing excessively
  during rapid navigation, at the cost of occasionally swallowing an
  intermediate state the user might have wanted to return to.
- When a search yields no results, the empty state tells the user whether
  matches exist in other folders, with other tags, or both. This helps users
  understand that the intersection model is narrowing their results, and
  guides them toward broadening the right constraint. The count queries add
  negligible cost since they only run on the empty-result path.
- Search remaining outside the history stack means users cannot "go back" to a
  previous search query. This is intentional: search is a filter, not a
  destination.

## Alternatives Considered

- **Keep the three axes independent and only add history**: Would allow
  back/forward navigation but the underlying interaction model would remain
  broken -- the column browser would still show global tags when a folder is
  selected, and search would still ignore folder/tag context. History on top
  of a broken model would preserve and restore broken states.
- **Include search in the history stack**: Would let users navigate back to
  previous searches, but creates ambiguity about what "back" means when a
  search is active (back to the previous search? back to the pre-search
  navigation state?). Keeping search separate avoids this and matches Finder's
  model.
- **Per-axis history (separate stacks for sidebar and column browser)**: Would
  allow independent back/forward for each axis, but two sets of back/forward
  buttons would be confusing. A single unified stack that captures the combined
  state is simpler to understand and use.
- **Client-side filtering instead of database-level scoping**: Rather than
  extending the SQL queries, filter `reachableTags` and search results in
  Swift by intersecting with `folderObjects`. Simpler to implement but does
  not scale -- it requires loading all folder objects into memory to filter
  against, and FTS ranking would be computed before filtering, potentially
  returning irrelevant results within the limit.
- **SwiftUI `NavigationStack` with `NavigationPath`**: The built-in navigation
  stack is designed for push/pop drill-down navigation, not for the two-axis
  (sidebar + column browser) model Filechute uses. A custom history stack is a
  better fit.
- **No coalescing (push every change)**: Simpler implementation but the stack
  would accumulate many entries during normal tag browsing, making back/forward
  tedious. Coalescing trades a small amount of fidelity for a much more usable
  history.
