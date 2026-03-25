# Formatting

Before committing, run `bin/check-format` and fix any issues with `bin/format`.

# Architecture

Prefer putting logic in `Sources/FilechuteCore/` where it can be covered by fast unit tests (`make test`). Keep `Sources/Filechute/` as a thin UI layer — UI tests (`make uitest`) are slow and brittle, so minimize the amount of behavior that can only be verified through them.

# Testing

When fixing a bug, add a regression test that fails without the fix. Run tests with `make test`.

# Accessibility

Add `.accessibilityIdentifier()` to UI elements so they can be targeted reliably in UI tests. This avoids fragile queries based on element indices or display text. Use `.accessibilityLabel()` on interactive elements for VoiceOver support — labels should be concise, human-readable descriptions of what the element does.

# Database

When creating or modifying database tables, consider the query patterns that will be used against them and add appropriate indices for good performance. Every `WHERE`, `JOIN`, and `ORDER BY` pattern that runs frequently should be backed by an index.

# Xcode project

When adding, removing, or renaming Swift files under `Sources/Filechute/`, update `Filechute.xcodeproj/project.pbxproj` to include the new references. The SPM build (`make build`) discovers files automatically, but the Xcode project (used by `make uitest`) requires explicit file entries in PBXFileReference, PBXBuildFile, PBXGroup, and PBXSourcesBuildPhase sections.
