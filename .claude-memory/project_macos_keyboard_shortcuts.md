---
name: macOS keyboard shortcut handling
description: macOS menu system intercepts Cmd+key before event monitors and SwiftUI onKeyPress — recurring pattern requiring menu commands or CommandGroup workarounds
type: project
---

On macOS, the menu system processes key equivalents before
`NSEvent.addLocalMonitorForEvents` and before SwiftUI's `.onKeyPress`.
This has caused repeated debugging cycles in this project:

- **Cmd+F** was intercepted by Edit > Find, causing NSTableView to
  attempt showing a Find bar and beep.
- **Cmd+T** was intercepted by Format > Font > Show Fonts, preventing
  the bulk tag editor from opening.

Additionally, **Cmd+key combinations never reach SwiftUI's
`.onKeyPress` handlers at all** (e.g. Cmd+Backspace for move-to-trash
had to use an NSEvent monitor with keyCode 51).

**Why:** Each instance required multiple debugging rounds before the
root cause (menu interception or SwiftUI limitation) was identified.

**How to apply:** When adding any keyboard shortcut:

1. If it uses Cmd+key, do NOT use `.onKeyPress` or event monitors.
   Use a SwiftUI `.commands { Button }` with `.keyboardShortcut`
   instead, communicating with views via `@FocusedValue`.
2. If a system menu already claims the key equivalent, remove it
   with `CommandGroup(replacing: ...)` before adding the custom one.
3. Non-Cmd shortcuts (Escape, arrows, Space) can use event monitors
   or `.onKeyPress` since no menu claims them.
4. Always use `event.charactersIgnoringModifiers` (not keyCodes) for
   character keys, due to non-US keyboard layout (see user_keyboard.md).
