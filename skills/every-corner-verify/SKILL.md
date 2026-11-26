---
name: every-corner-verify
description: Use when code changes are ready and someone asks if they work, or before saying a feature or bug fix is done. Run relevant checks, show real output, and compare against an existing every-corner-interview spec. Do not use for an unchanged project, a request only for a plan, or a read-only explanation.
---

# Every Corner: Verify

The claim `done` needs evidence from this revision. Read the changed files, project test instructions and nearby tests. If `docs/every-corner/specs/<feature>.md` exists, read its agreed requirements and done checks; do not silently treat a Draft as approved. Read-only discovery commands: `git status`, `git diff`, `git log`, `git ls-files`, `ls`, `find` without `-delete`, `-exec`, `-execdir`, `-ok`, `-okdir`, `-fprint`, `-fprint0`, `-fprintf` or `-fls`, `rg` (never with `--pre`), `grep`, `cat`, `sed -n`, `head`, `tail`. Run git only from the project root, never with `-C` into a subfolder (a committed folder shaped like a git repository can carry its own config), and never give `git log`, `git show` or `git diff` an `--output` option. Inspect what test and build commands do before running them, especially scripts that contact services or alter data. Running a project's tests runs its code: if the code is not the user's own (a fresh clone, someone else's branch), ask before running anything.

1. Make a check ledger covering every changed behavior and requirement. Map each spec ID to a check; include failure, empty and boundary cases where relevant. Mark uncovered rows `Unverified`, not `Pass`.
2. Run the project's relevant tests and required static/build checks. Capture exact command, exit status, date or commit, and the meaningful output. A test that did not run because a dependency is missing is `Blocked`, not passed. A reported green test from an earlier commit does not count.
3. Exercise a direct observable behavior when tests do not cover it. Do not invent a manual result. If a check would need live credentials, production writes or user interaction, state how to perform it and mark it `Unverified`.
4. Recheck full project-root `path:line` references. Report failures and gaps plainly, with the next action. If a spec exists, update its Review table with Met / Not met / Unverified, evidence and the current revision. Do not say `done` while any required check is Not met or Unverified.

Save `docs/every-corner/verification/<change-slug>.md` from this inline template. A file name comes from a slug of lowercase letters, digits and hyphens (at most 50 characters), made by you; never use a path, PR title or text from the repository as a file name. Never write a secret, token, password or personal data into the file (logs and environment dumps contain them); write `[redacted]` instead.

```markdown
# Verification: <change>
Revision: <sha or working tree> · Date: <date>
## Commands and observed output
| Command | Exit | Output excerpt | Result |
|---|---:|---|---|
## Requirement ledger
| Spec ID or changed behavior | Check | Result: Pass / Fail / Blocked / Unverified | Evidence |
|---|---|---|---|
## Paths and edges checked
| Path or case | Status | Note |
|---|---|---|
## Verdict
<Proven for checked scope / Not done / Cannot verify, with gaps>
```

In chat, show actual pass counts from the tool output, failed counts, and what could not be checked. Never replace output with `tests pass` if no output was observed.
