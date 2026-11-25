# The safety-net hook

`explain-risky-commands.sh` checks every shell command Claude wants to run and sorts it into four risk levels:

| Level | Examples | What happens |
|---|---|---|
| 1. Read-only | `ls`, `git status` | Passes silently |
| 2. Easy to undo | `git push`, `npm test`, `rm file.txt`, `git rm file.txt` | Passes silently |
| 3. Hard to undo | `sudo`, `chmod 777`, `git branch -D`, `git rm -f`, `--no-verify` | Asks you, with a `⚠️ HARD TO UNDO` warning |
| 4. Cannot be undone | `rm -r` / `rm -rf` / `rm --recursive`, `git push --force` / `-uf` / `origin +main`, deleting a remote branch (`git push origin :old`, `--delete`), `git reset --hard`, `DROP TABLE`, `npm publish`, `curl \| sh` | Asks you, with a `⛔ CANNOT BE UNDONE` warning and a safer option |

Only levels 3 and 4 interrupt you, because warnings shown on every command stop being read. The hook never blocks anything by itself. The skills work without it.

**No extra tools needed.** The hook reads the command with `jq` if it is installed, otherwise with a built-in plain-text fallback, so it never switches itself off silently. It runs no Python and nothing from your project folder, and adds about 10 ms to each command.

**Installed the plugin?** You already have the hook, switched on. Turn it off with `/plugin configure every-corner@every-corner-skills`. The steps below are only for manual installs.

**Headless runs (`claude -p`, CI):** nobody can answer the hook's prompt there, so Claude Code **denies** the risky command instead of asking. If an unattended job legitimately needs `rm -rf` or `npm publish`, turn the hook off for that run.

**Who can turn it off:** the off switch is the environment variable `CLAUDE_PLUGIN_OPTION_SAFETYNET`. Any settings file that sets environment variables for a session can set it, including a project's `.claude/settings.json`. If you open a project you don't trust, check its settings for that variable.

## Install manually

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

This runs every example command twice (with `jq` and with the no-`jq` fallback) and checks that each lands at the right level. It also checks that the hook never runs code from the project folder.

## Add a new pattern

1. Add an `elif` branch to `explain-risky-commands.sh` in the right section. Use `cannot "<what it does>" "<safer option>"` for level 4 or `hard "<what it does>" "<safer option>"` for level 3. Write the warning in plain English and say what is lost.
2. Add one dangerous example and one similar-looking safe example to `test-hook.sh`.
3. Run `./hooks/test-hook.sh` and open a pull request.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the wording rules.

> **A safety net, not a security boundary.** Pattern matching can be evaded, and the hook will miss things. For a stronger guard, combine it with a dedicated tool such as [dcg](https://github.com/Dicklesworthstone/destructive_command_guard), and use Claude Code's permission rules.
