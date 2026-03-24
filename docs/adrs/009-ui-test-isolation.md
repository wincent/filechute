# ADR 009: UI Test Isolation

## Status

Accepted

## Context

UI tests (`make uitest`) launch the real Filechute app via `XCUIApplication`.
The app currently reads persistent state from three sources:

| Layer      | Mechanism               | Keys                                                                                                |
| ---------- | ----------------------- | --------------------------------------------------------------------------------------------------- |
| App-wide   | `UserDefaults.standard` | `lastActiveStoreURL`, `recentStoreURLs`, `ignoredFilePatterns`                                      |
| Per-window | `@SceneStorage`         | `tableColumnCustomization`, `columnBrowserHeight`, `viewMode`, `thumbnailSize`, `expandedFolderIds` |
| Stores     | Filesystem + SQLite     | `~/Library/Application Support/Filechute/stores/*.filechute`                                        |

Because the tests launch the app with no special configuration, the app
inherits the developer's real state: last-opened store, recent stores list,
view mode, column widths, etc. This makes tests sensitive to user-specific
state, and test runs can also mutate the developer's real preferences and
store data.

## Decision

### Two launch arguments

The app accepts two optional launch arguments that, when present, redirect
persistent state to isolated locations:

1. **`-StoreBaseDirectory <path>`** -- `StoreCoordinator` uses this path
   instead of `~/Library/Application Support/Filechute/stores/`. The path
   must already exist; the app does not create it.

2. **`-UserDefaultsSuite <name>`** -- the app uses
   `UserDefaults(suiteName: name)` instead of `UserDefaults.standard` for all
   app-managed keys (`lastActiveStoreURL`, `recentStoreURLs`,
   `ignoredFilePatterns`). A fresh suite is empty, giving deterministic
   defaults.

These are independent, general-purpose flags rather than a single `-UITesting`
boolean. They can be combined or used individually, and the Makefile (or any
other caller) controls the concrete paths and names.

### Makefile responsibilities

The `uitest` target handles setup before running:

```makefile
UITEST_DIR = /tmp/filechute-uitest
UITEST_SUITE = dev.wincent.Filechute.UITesting

uitest:
	rm -rf $(UITEST_DIR)
	mkdir -p $(UITEST_DIR)
	defaults delete $(UITEST_SUITE) 2>/dev/null || true
	xcodebuild ... -only-testing:FilechuteUITests
```

The `rm -rf` + `mkdir -p` ensures a clean store directory. The
`defaults delete` clears any leftover suite from a previous run, ensuring a
pristine UserDefaults domain. Cleanup happens before -- not after -- each run,
so that state from a failed run is available for debugging and is cleaned up
by the next run.

### UI test setup

The test passes the arguments through `XCUIApplication.launchArguments`,
using deterministic values that match the Makefile:

```swift
override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = [
        "-StoreBaseDirectory", "/tmp/filechute-uitest",
        "-UserDefaultsSuite", "dev.wincent.Filechute.UITesting",
    ]
    app.launch()
}
```

Environment variables were considered for passing these values dynamically,
but xcodebuild's test orchestrator does not reliably propagate environment
variables to the test runner process. Hardcoded deterministic values are
simpler and avoid this propagation issue.

### App-side changes

**`StoreCoordinator`**: In `init()`, check `CommandLine.arguments` for
`-StoreBaseDirectory`. If present, use the following argument as the stores
directory instead of the default Application Support path.

**UserDefaults access**: An `AppDefaults` enum provides a `shared` property
that checks `CommandLine.arguments` for `-UserDefaultsSuite`. If present, it
returns `UserDefaults(suiteName: name)`; otherwise `UserDefaults.standard`.
All call sites in `StoreCoordinator`, `StoreManager`, and `SettingsView` use
`AppDefaults.shared` instead of `UserDefaults.standard`.

### What this does not cover

**`@SceneStorage`**: SwiftUI manages scene storage internally and does not
expose an API to redirect or reset it. In practice, scene storage keys all
have sensible defaults (`"table"`, `180`, `128`, etc.), so a fresh app launch
with empty UserDefaults and an empty store is unlikely to hit scene-storage
sensitivity. If this becomes a problem in the future, the affected values
could be migrated from `@SceneStorage` to `@AppStorage` backed by the custom
suite.

## Consequences

- UI tests run against an empty store with default settings every time,
  regardless of developer machine state.
- Test runs never mutate the developer's real preferences or store data.
- The two flags are reusable beyond testing -- they could serve sandboxed
  demo environments, CI, or scripted automation.
- Existing non-test launch behaviour is unchanged (flags are opt-in).
- A small amount of indirection is added to UserDefaults access, but it is
  confined to a single accessor (`AppDefaults.shared`).

## Alternatives Considered

- **Single `-UITesting` flag**: Simpler, but embeds test-specific knowledge
  (temp paths, suite names) in the app rather than leaving it to the caller.
  Less composable.
- **Environment variables from Makefile to test runner**: Would avoid
  duplicating paths, but xcodebuild's test orchestrator does not reliably
  propagate shell environment variables to the XCTest runner process.
- **`mktemp -d` for unique paths**: More robust against parallel runs, but
  requires a propagation mechanism (env vars or temp files) to communicate
  the path from the Makefile to the test. Deterministic paths are simpler
  and parallel UI test runs on the same machine are not a practical concern.
- **Separate test target / app configuration**: Heavyweight. A UI test that
  does not exercise the real app binary has limited value.
- **Resetting state in `tearDown`**: Fragile -- if a test crashes, cleanup
  is skipped. Doing setup (not teardown) in the Makefile is more robust.
