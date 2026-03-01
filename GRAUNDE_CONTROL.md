# graunde

Ground Control for Claude Code. CLAUDE.md is advisory — graunde is the gate.

## Problem

Claude Code ignores CLAUDE.md instructions. You tell it "use `make test`", it runs `go test` without build tags, tests fail, and it starts "fixing" code that was never broken. You tell it "don't use `sed`", it uses `sed` with GNU syntax on macOS. The list never ends.

The only enforcement that works is at the tool level — a PreToolUse hook that intercepts commands before they execute. Not a suggestion. A gate.

## How it works

Runs as a Claude Code `PreToolUse` hook on `Bash`. Reads JSON from stdin, extracts the command, checks it against controls compiled into the binary. Three possible outcomes:

- **arg** — amend the command with missing arguments, allow execution (always works)
- **deny** — block the command with a reason on stderr (always works)
- **allow** — no match, pass through silently

Controls are D source, evaluated at compile time via CTFE. No runtime config, no file I/O, no dependencies. The binary is the config.

## Language

D. Compiled with LDC. Chosen for:
- Rich stdlib: `std.json`, `std.algorithm` — no external dependencies
- Native binary, instant startup
- CTFE — controls are parsed at compile time, baked into the binary
- `unittest` as a language keyword — tests live next to code

## Controls

Controls are defined in `source/controls.d`. A control has:
- `name` — identifier slug
- `cmd` — substring to match against the command
- `arg` — arguments to insert after the matched command

```d
enum allControls = [
    control("go-test-args", cmd("go test"), arg(`-tags "rustsqlite,qntxwasm" -short`)),
];
```

Commands are split on `|`, `;`, `&&` — each segment is checked independently.

## Hook protocol

**Input** (JSON on stdin):
```json
{
  "tool_input": {
    "command": "go test ./..."
  }
}
```

**Output** (arg amendment):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": {
      "command": "go test -tags \"rustsqlite,qntxwasm\" -short ./..."
    }
  }
}
```

**Output** (no match): exit 0, no output.

**Output** (deny): exit 2, reason on stderr.

## Hook registration

In `~/.claude/settings.json`:
```json
"hooks": {
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "/path/to/graunde"
        }
      ]
    }
  ]
}
```

## Countdown

### Ten — core engine ✓
Stdin JSON parsing, control matching, arg amendment, pipe splitting, unit tests. One control (`go-test-args`) end to end.

### Nine — betterC
Drop the D runtime. No GC, no `std.json`, no exceptions. Hand-rolled JSON parsing for the one field we need.

### Eight — omit
Strip unwanted flags from commands. `omit("--no-verify")` removes the flag, lets the command through. First control: `no-skip-hooks`.

### Seven — QNTX controls
Full set of controls for the QNTX project: `sed`, `--no-verify`, `rm`, `kill`, force-push, `gh pr create`.

### Six — `--debug` flag
Print loaded controls, match attempts, and decisions to stderr.

### Five — hook registration
Wire graunde into Claude Code. Document installation.

### Four — commencing countdown, engines on

### Three

### Two — check ignition

### One — and may God's love

### Liftoff — be with you
