---
name: Bundle identifier uses dev.wincent
description: The user controls wincent.dev (not wincent.com) — bundle identifiers and app support paths use dev.wincent.Filechute
type: project
---

The user owns wincent.dev, not wincent.com. All reverse-DNS identifiers
must use `dev.wincent` (e.g. `dev.wincent.Filechute`).

**Why:** The user explicitly corrected `com.wincent` references because
they do not control the wincent.com domain.

**How to apply:** When creating new bundle identifiers, app support
paths, or any reverse-DNS identifiers, use `dev.wincent` as the prefix.
