---
name: explain-before-approve
description: Use whenever you are about to run a tool call that will trigger a permission prompt (editing files, running shell commands that change things, installing, deleting, network calls, git operations). Before the call, write a short plain-language explanation of what is about to happen, why, what changes, and whether it can be undone, so the human can approve with understanding instead of clicking through.
---

# Explain Before Approve

In manual-approval mode, people see a command they may not understand and a button. Juniors especially learn to click "accept" without knowing what they accepted. Your job is to make the decision informed, in everyday language, right above the prompt.

## The rule

Immediately **before** any tool call that will ask for permission, write a short explanation using this shape:

```
**What:** <what I'm about to do, in everyday words>
**Why:** <how it moves the task forward>
**Changes:** <what is touched: which files / systems, and whether anything leaves this computer>
**Undo:** <easy to undo / hard to undo / cannot be undone / read-only, changes nothing>
```

Keep it to 3-4 short lines. No jargon without a translation. Say "delete the `build` folder", not "rm -rf build". If you must show the command, put it after the plain version.

## Three levels, so it does not become noise

Over-explaining trains people to skip the explanations too. Match the effort to the risk.

| Level | Actions | What to write |
|---|---|---|
| **Quiet** | Read-only: listing files, reading, searching, `git status`, `git diff` | One line at most, or nothing |
| **Standard** | Editing project files, running tests, building, creating files | The four-line shape |
| **Careful** | Deleting, installing packages, database or migration changes, network calls, `git push`, `git reset`, force flags, anything outside the project folder, anything with credentials | The four-line shape **plus** a "Check this" line |

For **Careful** actions add:

```
**Check this:** <the one thing a human should verify before approving, e.g. "the path is inside your project", "this targets the test database, not production">
```

## Honesty requirements

- Describe the real effect, not a reassuring one. If you are not sure what a command will do, say so and prefer a safer read-only command first (for example, run with `--dry-run`, or list what would be deleted before deleting).
- Never describe a risky action in softer words than it deserves. "Overwrites the shared history on the server and cannot be undone" is the correct sentence for a force push.
- If the action goes beyond what the human asked for, say that explicitly and ask whether they want it.
- If the plan changed since the last approval, say what changed and why.

## Translating common actions

| Instead of | Write |
|---|---|
| `rm -rf node_modules` | "Delete the downloaded libraries folder. It is re-created by the install command, so this is easy to undo." |
| `npm install lodash` | "Download the `lodash` helper library and add it to your project's dependency list (changes `package.json` and the lock file)." |
| `git push --force` | "Overwrite the branch on the server with your local version. Teammates' work on it can be lost. Cannot be undone." |
| `chmod +x run.sh` | "Allow this file to be run as a program. Changes only this file's permissions." |
| `curl ... \| sh` | "Download a script from the internet and run it immediately. I cannot see what it does first. Careful." (Prefer to download, read, then run.) |
| Edit of `config.json` | "Change the port from 3000 to 4000 in `config.json`, so it does not clash with another app. Easy to undo." |

## Batching

If several similar low-risk edits are coming (for example, renaming one function across five files), explain once for the group ("I'll update 5 files that call the old name"), then list the files. Do not repeat the full shape five times.

## Pairing

This skill works best after `plan-every-corner`: the approved plan gives each later prompt a reason ("step 3 of the plan"), so the explanation can point back to something the human already understands.
