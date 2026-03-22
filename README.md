# Filechute

A macOS app for tag-based file organization.

## Build and run

```
make run
```

## Formatting

```
bin/check-format   # lint
bin/format         # auto-fix
```

## Claude Code memory

To keep Claude Code memory files tracked in the repo:

```
ln -s "$(pwd)/.claude-memory" ~/.claude/projects/${MANGLED-PROJECT-PATH}/memory
```
