# The safety-net hook

`explain-risky-commands.sh` adds a plain-language warning to dangerous shell commands. It is optional. The skills work without it.

**What you need:** `jq` (`brew install jq` on macOS, `sudo apt install jq` on Linux).

## Install

**1. Copy the script and make it executable**

```bash
mkdir -p ~/.claude/hooks
cp hooks/explain-risky-commands.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/explain-risky-commands.sh
```

**2. Register it in `~/.claude/settings.json`**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/explain-risky-commands.sh" }
        ]
      }
    ]
  }
}
```

If you already have a `hooks` section, add this entry to it instead of replacing it.

**3. Start a new Claude Code session.**

## Try it without Claude

```bash
./hooks/test-hook.sh
```

This runs a list of safe and dangerous example commands and checks that the right ones are flagged.

## Add a new pattern

1. Add a new `elif match '...'` branch with a short, plain-language `reason` in `explain-risky-commands.sh`.
2. Add one dangerous example and one similar-looking safe example to `test-hook.sh`.
3. Run `./hooks/test-hook.sh` and open a pull request.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the style rules on warning messages.

> This hook is a safety net, not a security boundary. It cannot catch everything.
