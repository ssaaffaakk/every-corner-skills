# The safety-net hook

`explain-risky-commands.sh` checks every shell command Claude wants to run and sorts it into four risk levels:

| Level | Examples | What happens |
|---|---|---|
| 1. Read-only | `ls`, `git status` | Passes silently |
| 2. Easy to undo | `git push`, `npm test`, `rm file.txt`, `git rm file.txt` | Passes silently |
| 3. Hard to undo | `sudo`, `chmod 777`, `git branch -D`, `git rm -f`, `--no-verify` | Asks you, with a `⚠️ HARD TO UNDO` warning |
| 4. Cannot be undone | `rm -r` / `rm -rf` / `rm --recursive`, `git push --force` / `-uf` / `origin +main`, deleting a remote branch (`git push origin :old`, `--delete`), `git reset --hard`, `DROP TABLE`, `npm publish`, `curl \| sh` | Asks you, with a `⛔ CANNOT BE UNDONE` warning and a safer option |

Only levels 3 and 4 interrupt you, because warnings shown on every command stop being read. The hook never blocks anything by itself. The skills work without it.

**No extra tools needed.** The hook reads the command with `jq` if it is installed, otherwise with a built-in `sed` fallback, so it never switches itself off for lack of a tool. It runs no Python and nothing from your project folder. It adds roughly 10-40 ms to a normal command and stays under a second even for a 300 KB command on macOS and Linux, far below its 10-second timeout.

**Installed the plugin?** You already have the hook, switched on. Turn it off with `/plugin configure every-corner@every-corner-skills`. The steps below are only for manual installs.

**Headless runs (`claude -p`, CI):** nobody can answer the hook's prompt there, so Claude Code **denies** the risky command instead of asking. If an unattended job legitimately needs `rm -rf` or `npm publish`, turn the hook off for that run.

**Who can turn it off:** the off switch is the environment variable `CLAUDE_PLUGIN_OPTION_SAFETYNET`. Any settings file that sets environment variables for a session can set it, including a project's `.claude/settings.json`. If you open a project you don't trust, check its settings for that variable. (`EVERY_CORNER_HOOK_PARSER` is for the tests only: `raw` forces the no-`jq` fallback, and any other value is ignored.)

**What it errs toward:** it searches the whole command text, heredoc bodies included, so a dangerous command is found wherever it sits (after `VAR=x`, inside `if`/`for`, `( )`, `$( )`, `bash -c`, `ssh host '...'`, or a heredoc). The price is an occasional extra warning when a command only *mentions* one, for example in an `echo`, a commit message or a file written with `cat <<EOF`.

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

1. In `explain-risky-commands.sh`, add a check in the right section (level 4 or level 3): `if has "<regex>"; then raise 4 "<what it does>" "<safer option>"; fi`. Build the regex from `B` (start of a command word), `A` (other arguments) and `E` (end of a word), like the rules around it. If the rule needs an exception that must sit in the same command segment (like `--cached` or `--dry-run`), use `seg_has <match> <must-match> <must-not-match>` (three regexes, checked one command segment at a time), and build the exception with `after <command> <flags>` so it only counts flags that follow that command. Write the warning in plain English and say what is lost.
2. Add one dangerous example and one similar-looking safe example to `test-hook.sh`.
3. Run `./hooks/test-hook.sh` and open a pull request.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the wording rules.

> **A safety net, not a security boundary.** Pattern matching can be evaded, and the hook will miss things. For a stronger guard, combine it with a dedicated tool such as [dcg](https://github.com/Dicklesworthstone/destructive_command_guard), and use Claude Code's permission rules.

---

# The style guard hook

`require-style-study.sh` makes sure `every-corner-matchcodebase` runs before code is written in a project that already has code. A skill description alone did not start the skill for small requests (2 of 2 test runs skipped it), and a hook runs every time.

It watches `Edit`, `Write` and `MultiEdit`. It blocks **once per session**, and only when both are true:

- the file being written is a source file (`.py`, `.js`, `.ts`, `.go`, `.rs` and similar) inside the project Claude is working in (a scratch script in a temp folder does not count);
- the project already contains other source files (code in `node_modules`, `vendor` and virtual environments does not count).

The agent is told to run the skill and then repeat the edit. Without `docs/every-corner/STYLE.md` the skill studies the project; with it, the skill reuses the notes and re-checks only files changed since, which is cheap. (Without this nudge a later session never opened `STYLE.md`.) It never blocks twice in a session, not at all once the skill has run in that session, never in an empty project, and never for docs or config files. If it cannot save its once-per-session mark (an unwritable folder), it does not block at all. `.vue` and `.svelte` files are not watched. Tests: `./hooks/test-style-guard.sh` (57 checks, each case with and without `jq`; also run in CI).

**Headless runs:** the block is a message, not a question, so `claude -p` keeps going: the agent runs the skill and then edits. That costs a few extra turns in every new session (in a test, a 3-line rename took $0.55 and 55 s with the study against $0.25 and 23 s without). Switch the option off for unattended runs if that matters.

**You need:** nothing extra; `jq` is used when present and a built-in fallback otherwise. **Installed the plugin?** It is on by default; turn it off with `/plugin configure every-corner@every-corner-skills` (option "Style guard hook"). For a manual install, copy the script like the safety net above and register it with the matcher `Edit|Write|MultiEdit|Skill` (the `Skill` part lets it notice that the skill already ran).
