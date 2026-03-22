---
name: macOS menu system intercepts Cmd+F
description: The default Edit > Find menu intercepts Cmd+F before event monitors — must remove it via CommandGroup(replacing: .textEditing) for custom handling
type: project
---

On macOS, the menu system processes key equivalents before
`NSEvent.addLocalMonitorForEvents` sees them. The default SwiftUI Edit
menu includes a Find submenu with Cmd+F. When the SwiftUI Table view
(backed by NSTableView) receives `performTextFinderAction:`, it tries
to show a Find bar, fails, and beeps.

**Why:** Multiple approaches failed (event monitor, `.commands` button,
`performKeyEquivalent:` override, app delegate, `.onCommand`) until we
determined the NSTableView was handling the action.

**How to apply:** The working solution is:
1. `CommandGroup(replacing: .textEditing) {}` in the app to remove the
   Find menu entirely
2. Handle Cmd+F in the event monitor using
   `event.charactersIgnoringModifiers` (not keyCodes)
3. Focus the search field via `NSSearchField.selectText(nil)`
