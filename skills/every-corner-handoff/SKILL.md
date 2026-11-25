---
name: every-corner-handoff
description: Use when a long coding session is ending or the user asks to hand work to the next session. Write a short, evidence-checked record of done, partial, next actions and how to run it. Do not use for an ordinary short answer, a new task, or a request to continue working now.
---

# Every Corner: Handoff

Leave the next person a short note they can act on without replaying the chat. Read the current branch, `git status`, relevant diff, specs and verification notes first. Distinguish committed work from working tree edits. Do not claim a test passed from memory. Read-only commands: `git status`, `git diff`, `git log`, `git show`, `git ls-files`, `rg`, `grep`, `ls`, `find` without `-delete`, `cat`, `sed`, `head`, `tail`. This skill does not run builds or tests.

Save `docs/every-corner/HANDOFF.md` from this inline template:

```markdown
# Handoff: <task>
Date: <date> · Branch: <name> · Commit: <sha> · Working tree: <clean or paths>
## Done
- <outcome and verified full project-root path:line>
## Half-done or blocked
- <exact state, why, and file:line; or none>
## Next steps
1. <first concrete action; file or command>
## How to run and check
| Command from project docs/config | Last observed result or Not run | Source |
|---|---|---|
## Decisions and open questions
- <decision with spec link, or question only the user can answer>
## Coverage ledger
| Workstream or requirement | Done / Partial / Unstarted / Unknown | Evidence |
|---|---|---|
```

Keep it short enough to scan. Recheck every cited line; use full project-root paths. A command found in docs is `Not run` unless its output was actually observed in this session or a cited verification report at the same revision. If the tree contains changes you did not make, describe their status without assigning ownership. In chat, give the first next step and the saved path.
