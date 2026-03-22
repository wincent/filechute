# ADR 001: Debug Logging with In-App Log Window

## Status

Accepted

## Context

Filechute has no logging. Errors are silently caught (`try?`) or shown to the
user, but there is no way to observe what the app is doing internally. This
makes debugging difficult during development and when investigating user-reported
issues.

## Decision

Add debug logging that writes to two destinations:

1. **Apple's unified logging system** (`os.Logger`) for access via Console.app
   and `log stream` CLI.
2. **An in-memory ring buffer** (`LogStore`) that drives an in-app log window,
   accessible from a Debug menu.

### Architecture

Three new components, plus instrumentation of existing code:

**`LogStore`** (`Sources/FilechuteCore/LogStore.swift`) -- An `@Observable
@MainActor` singleton holding a capped ring buffer of `LogEntry` values. Lives
in `FilechuteCore` so all core services can log. Follows the same
`@Observable @MainActor` pattern as `StoreManager`.

Supporting types:

- `LogEntry` (struct, `Identifiable`, `Sendable`): `id`, `timestamp`, `level`,
  `category`, `message`.
- `LogLevel` (enum): `debug`, `info`, `error`.
- `LogCategory` (enum): `database`, `objectStore`, `ingestion`, `fileAccess`,
  `garbageCollector`, `integrity`, `ui`, `general`.

**`Log`** (`Sources/FilechuteCore/Log.swift`) -- A static facade with
`debug(_:category:)`, `info(_:category:)`, `error(_:category:)` methods. Each
method writes to `os.Logger` synchronously (thread-safe) and dispatches to
`LogStore.shared` via `Task { @MainActor in }`. Subsystem is
`"dev.wincent.Filechute"`, category derived from `LogCategory.rawValue`. Uses
`privacy: .public` since these are developer debug logs.

**`LogWindowView`** (`Sources/Filechute/LogWindow.swift`) -- A SwiftUI view
displayed in a dedicated `Window("Log", id: "log")` scene. Features filter
pickers for category and level, a clear button, and auto-scroll. Opened from a
Debug > Show Log menu item (Cmd+Option+L).

### Instrumentation targets

Log calls added to: `Database`, `ObjectStore`, `IngestionService`,
`FileAccessService`, `GarbageCollector`, `IntegrityChecker`, `StoreManager`,
`ContentView`.

## Consequences

- All internal operations become observable during development and debugging.
- The ring buffer is capped at 5000 entries to bound memory usage.
- `Task { @MainActor in }` dispatch means log entries may appear in the UI with
  slight delay and minor ordering jitter under high concurrency. Acceptable for
  debug logging.
- The `LogStore.shared` singleton is alive during tests but has no side effects
  beyond in-memory array appends.
- System log access remains available via
  `log stream --predicate 'subsystem == "dev.wincent.Filechute"' --level debug`.

## Alternatives Considered

- **`OSLogStore` for reading back system logs**: The read API cannot reliably
  access ephemeral debug-level messages, making it unsuitable for an in-app
  viewer.
- **In-app window only (no system log)**: Rejected because `os.Logger`
  integration is nearly free and provides Console.app / CLI access for cases
  where the app has already quit or crashed.
- **Third-party logging framework**: Adds an external dependency for something
  the platform provides natively.
- **Lock-based thread-safe store instead of MainActor dispatch**: Adds
  complexity (manual observation invalidation) for marginal ordering improvement
  that debug logging does not require.
