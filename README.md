# Filechute

A macOS app for tag-based file organization.

## Build and run

```
make run
```

## Tests

```
make test
```

## Formatting

```
bin/check-format   # lint
bin/format         # auto-fix
```

## Debug logging

The app logs to both an in-app log window and the macOS unified log.

**In-app:** Debug > Show Log (Cmd+Option+L)

**Terminal:** Stream logs in real time:

```
log stream --predicate 'subsystem == "dev.wincent.Filechute"' --level debug
```

**Console.app:** Open Console, then filter by the subsystem `dev.wincent.Filechute`.
Set the "Action" menu to "Include Debug Messages" to see debug-level entries.

## Claude Code memory

To keep Claude Code memory files tracked in the repo:

```
ln -s "$(pwd)/.claude-memory" ~/.claude/projects/${MANGLED-PROJECT-PATH}/memory
```
