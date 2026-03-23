# ADR 005: Multi-Store Support

## Status

Accepted

## Context

Filechute currently has a single hardcoded store at
`~/Library/Application Support/dev.wincent.Filechute/stores/default`. There is
no way to create additional stores, open stores from arbitrary locations, or
treat stores as first-class Finder objects. Multi-store support is also a
prerequisite for running high-level acceptance tests against isolated stores.

## Decision

### Store format

Rename stores to use the `.filechute` extension (e.g. `Default Store.filechute`).
Register a custom UTType (`dev.wincent.filechute.store`) conforming to
`com.apple.package` so that Finder treats each store directory as an opaque
bundle. Double-clicking a `.filechute` bundle in Finder opens it in Filechute.

### Window model

Switch from a bare `WindowGroup` to `WindowGroup(for: URL.self)` so each window
is keyed by a store URL. `nil` means the default store. State restoration
preserves which stores were open across relaunches (URL is `Codable`).

Keyboard shortcuts:

| Shortcut    | Action                                    |
| ----------- | ----------------------------------------- |
| Cmd+N       | New window for the focused window's store |
| Shift+Cmd+N | Create a new store (name prompt sheet)    |
| Cmd+O       | Open an existing `.filechute` store       |

### File menu additions

- **New Store...** (Shift+Cmd+N) -- presents a sheet with a text field
  pre-filled with a unique placeholder name like "New Filechute Store 1".
- **Open Store...** (Cmd+O) -- shows an `NSOpenPanel` starting at the stores
  directory, filtering for `.filechute` bundles. Users can navigate elsewhere.
- **Open Recent** -- submenu tracking recently opened stores, backed by
  `UserDefaults`. Includes a "Clear Menu" item.

### Sidebar

The first item in the sidebar becomes the store name (derived from the bundle
name minus the `.filechute` extension). It is functionally equivalent to the
existing "All Items" view for now; the two may merge in the future.

Right-clicking the store item shows a context menu with a **Rename** action.
Rename validates that:

- The name does not contain `/`.
- No sibling directory with the target name already exists.

On success the directory is renamed on disk and the `StoreManager` is
re-initialized at the new path.

### Architecture components

**`StoreCoordinator`** -- `@Observable @MainActor` singleton. Owns the stores
directory URL, manages the recent-stores list, and generates unique placeholder
names for new stores.

**`StoreManager` changes** -- exposes `storeRoot: URL` (stored) and a
`storeName: String` computed property (directory name minus extension).

**`AppDelegate`** -- `NSApplicationDelegateAdaptor` handles
`application(_:open:)` for Finder-initiated opens of `.filechute` bundles.

**Focused values** -- `storeURL` and `showNewStoreSheet` propagate from the
focused window to menu commands via `@FocusedValue`.

### Info.plist changes

- `UTExportedTypeDeclarations` declaring `dev.wincent.filechute.store`
  conforming to `com.apple.package` with extension `filechute`.
- `CFBundleDocumentTypes` registering the app as the owner/editor of
  `.filechute` bundles.

## Consequences

- Each window carries its own `StoreManager`; no shared mutable state between
  windows viewing different stores.
- If a store is renamed while a second window views the same store, the second
  window retains valid file descriptors but has a stale path. It will need to be
  closed and reopened. Acceptable for an initial implementation.
- The `.filechute` bundle registration requires the app to be launched at least
  once (or `lsregister`-ed) before Finder recognizes the type.
- Acceptance tests can create throwaway `.filechute` stores in a temp directory.

## Alternatives Considered

- **`DocumentGroup` / `ReferenceFileDocument`**: SwiftUI's document-based
  architecture. Rejected because stores are long-lived stateful directories, not
  single-file documents, and DocumentGroup imposes UI constraints (title bar
  editing, save dialogs) that do not match the intended UX.
- **Single global store with "collections"**: Simpler but does not provide
  filesystem-level isolation needed for acceptance tests or portable stores.
- **NSDocument subclass via AppKit**: More control but loses SwiftUI scene
  management benefits and adds significant bridging complexity.
