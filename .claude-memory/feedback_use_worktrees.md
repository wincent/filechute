---
name: feedback_use_worktrees
description: Use git worktrees instead of checkout when testing old revisions
type: feedback
---

Don't check out old revisions in the main working tree. Use a git worktree instead.

**Why:** Checking out old revisions disrupts the user's working directory state, unstaged changes, and workflow.

**How to apply:** When needing to build/test an old revision, use `git worktree add` to create a temporary worktree, or use the Agent tool with `isolation: "worktree"`.
