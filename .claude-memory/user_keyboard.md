---
name: Non-US keyboard layout
description: User has a non-US keyboard layout where character keys have different hardware keyCodes than ANSI — must use charactersIgnoringModifiers for keyboard shortcuts, not keyCodes
type: user
---

The user has a non-US keyboard layout. The physical key for 'f' produces
keyCode 14 (which is the 'e' position on US ANSI). When handling keyboard
shortcuts for character keys, always use `event.charactersIgnoringModifiers`
instead of `event.keyCode`. Hardware keyCodes are only reliable for
non-character keys (Return=36, Escape=53, arrows=125/126, etc.).
