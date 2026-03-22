# Formatting

Before committing, run `bin/check-format` and fix any issues with `bin/format`.

# Testing

When fixing a bug, add a regression test that fails without the fix. Run tests with `make test`.

# Xcode project

When adding, removing, or renaming Swift files under `Sources/Filechute/`, update `Filechute.xcodeproj/project.pbxproj` to include the new references. The SPM build (`make build`) discovers files automatically, but the Xcode project (used by `make uitest`) requires explicit file entries in PBXFileReference, PBXBuildFile, PBXGroup, and PBXSourcesBuildPhase sections.
