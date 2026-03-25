---
name: Investigate differences before fixing
description: When a bug appears only in one state but not another, investigate what differs between the two states before attempting fixes
type: feedback
---

When a layout bug only manifests in one app state (e.g., empty store) but works correctly in another (e.g., store with items), investigate what code path differs between the two states rather than repeatedly modifying the affected component. The root cause is likely in the differing code path, not in the component itself.

**Why:** Spent many attempts modifying ColumnBrowserView/ScrollView internals when the real issue was a missing `.frame(maxWidth: .infinity, maxHeight: .infinity)` on the sibling `emptyStateView` in ContentView — a one-line fix in a completely different view.

**How to apply:** When debugging layout issues, first ask "when does this work vs. not work?" and diff the code paths. Look at siblings and parent containers, not just the affected component.
