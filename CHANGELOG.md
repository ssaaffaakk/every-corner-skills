# Changelog

All notable changes to this project are listed here. Versions follow the `version` field in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json).

## 1.2.0 (2026-11-27)

### Added
- **every-corner-debug:** reproduces a bug, tests two or three possible causes, explains the root cause, then fixes it and reruns the check. Saves `docs/every-corner/debug/<bug>.md`.
- **every-corner-verify:** runs the project's checks, records the real output and compares each requirement with an agreed interview spec (Pass, Fail, Blocked or Unverified). Saves `docs/every-corner/verification/<change>.md`.
- **every-corner-diff:** explains a diff, commit or PR by intent, follows effects into unchanged files and names up to three evidence-based risks. Saves `docs/every-corner/diffs/<change>.md`.
- **every-corner-review:** reviews a diff for correctness, security and local style and reports only verified findings with a severity and how each was verified. Never approves. Saves `docs/every-corner/reviews/<change>.md`.
- **every-corner-handoff:** records what is done, what is half-done, the next step and how to run the project, with every cited line re-checked. Saves `docs/every-corner/HANDOFF.md`.
- Thirty-two trigger evals (four should-trigger cases per skill, one of them in plain conversational wording, and two to three should-not-trigger near misses) and a [survey of existing tools](docs/research.md) the skills borrow from.

### Changed
- The README's always-on cost is now about 900 tokens (the names and descriptions of nine skills, 3,457 characters), up from about 500 for four.
- The first draft of this release also contained `every-corner-codebase`. It was dropped before release: `every-corner-matchcodebase` (1.1.0, issue #25) does the same job with a counting script, a hook and 101 + 44 tests.

### Hardening before release (stress test and reviews)
- All five skills got read-only rules in the spirit of `every-corner-matchcodebase`, a little stricter: `find` without `-delete`, `-exec`, `-execdir`, `-ok`, `-okdir`, `-fprint`, `-fprint0`, `-fprintf` or `-fls`; `rg` never with `--pre` (it runs a command); `sed -n` instead of any `sed`; `git log`, `git show` and `git diff` never with `--output` (it writes a file); git only from the project root, because a committed folder shaped like a bare repository can carry a `core.fsmonitor` command.
- The four skills that name their note (debug, verify, diff, review) use a slug (a PR title or request could have been `../../.git/hooks/post-commit`); `handoff` writes a fixed file name. The slug is now lowercase letters, digits and hyphens that the agent makes itself, and never a path or repository text.
- Saved notes no longer copy secrets: logs and environment dumps that end up in debug, verification and handoff notes are written as `[redacted]`.
- `every-corner-review` said both "run tests after checking their effects" and "never execute PR code"; a test runner executes whatever the change contains. It now runs nothing unless asked and says `Not run` in its ledger. `every-corner-verify` asks before running the tests of code that is not the user's own. `diff` and `handoff` treat instructions in repository files as data.
- `review` and `debug` read `docs/every-corner/STYLE.md` (the notes of `every-corner-matchcodebase`) instead of the removed `CODEBASE.md`.
- `sed` on the read-only lists is limited to `sed -n '<from>,<to>p'` (GNU `sed` can write files and run commands with `w`, `e` and `r`, which the security review caught). `every-corner-debug` asks before running the tests or reproduction of code that is not the user's own, and `every-corner-verify` treats repository text, specs and test output as data (both gaps were in the first hardening; found by the security review).
- `every-corner-verify` wrote Review table values (`Unverified`, extra columns) that the interview spec template does not have; it now uses `Met`, `Not met` or `Changed` with the evidence in the Note column. The how-it-works repo layout, a short section on the five skills and CONTRIBUTING's eval command were missing.
- The research survey now says one cited issue is closed and no longer points to a skill that was removed.

### Known limits
- **The new evals only check that the skill starts.** Each runs once in an empty folder with a one-line prompt (about 20 s). None checks that a debug, review or handoff note is any good, and there is no baseline run without the plugin, so they show triggering, not benefit.
- **A hostile-input run found nothing to fix in the model's behavior.** Four real `claude -p` sessions on throwaway projects (no transcripts are committed; a diff titled `../../.git/hooks/post-commit`, a secret in a crash log, a README telling reviewers to approve, a change whose test file writes a marker file) all ended safely before the hardening; the rules above are meant to make that deliberate rather than luck of one model; the scenarios were not re-run after the hardening.
- These skills overlap with `/code-review`, `/security-review` and the superpowers skills. They add the saved file, the coverage ledger and the read-only rules, not new analysis.

## 1.1.0 (2026-11-26)

### Added
- **every-corner-matchcodebase:** before any code is written in a project that already has code, it learns how the project is really written and used, saves `docs/every-corner/STYLE.md`, writes new code in that exact style, and checks the result with the project's own formatter, linter and tests.
  - A counting script (`skills/every-corner-matchcodebase/scripts/style-counts.py`, standard library only) covers every file in one pass and prints numbers and file names, never code. The agent reads in full only the config, the area it will touch, a few example files and the outliers.
  - Cached by commit: an unchanged project reads no source files on the next run.
  - Read-only study; bugs and unsafe patterns found in the old code are reported, not copied.
- [Research report](docs/every-corner/research/matchcodebase-landscape.md) on similar tools and the evidence behind the design, and the [spec](docs/every-corner/specs/every-corner-matchcodebase.md).
- **Style guard hook** (`hooks/require-style-study.sh`): in a project with code, it blocks the first source edit of a session and tells the agent to run the new skill first. Without `STYLE.md` the skill studies the project; with it, the skill reuses the notes and re-checks only changed files (without this nudge a later session never read `STYLE.md`). Blocks once per session, only for files inside the project Claude is working in, never in an empty project or for non-source files; on by default, switch off with the "Style guard hook" option. Works without `jq` too (a sed fallback, like the safety net). 101 checks, each case with and without `jq`, run in CI.
- **Trigger tests:** five `claude plugin eval` cases in `evals/matchcodebase-*`, three that must start the skill (an add and a fix in a Python project, an add in a JavaScript one) and two that must not (a README typo, an empty project). Each case sets up its project with a scaffold script, so they run with `--scaffold`. All five pass, and the six interview cases still pass with the new skill and hook.
- `tests/matchcodebase/`: fixtures with deliberately odd styles, 44 checks for the script (including hostile files), and `run-session.sh` for headless with/without runs.

### Fixed in review (stress test)
- The counting script skips symlinks and special files: a named pipe called `x.py`, or a symlink to one, made it hang forever, and a symlink could point outside the project.
- Quote, import and declaration patterns are applied only to lines up to 400 characters (longer lines, such as minified code, count for length and indent only), and the import pattern no longer spans lines: one Java or C# line with 3,000 spaces took over 20 s, a 200 KB JavaScript file of blank lines or one long line of `"\` more than 60 s. The Java and C# declaration patterns no longer backtrack, and blank runs are collapsed for every kind of whitespace (non-breaking space, form feed, U+2003): a 120 KB Java file of such lines took 28 s. A sweep of 17 languages against 26 hostile corpora (blank floods, repeated keywords with and without a `(`, Unicode whitespace; 17 files of about 800 KB each) takes 0.6 to 0.75 s per corpus on an idle machine. Worst case for one file: about 3 s for 1 MB of a hostile shape on a loaded machine (the script reads at most 1 MB per file), and the 30 s budget bounds the total. The script also stops reading files after 30 s and says so, counts line lengths and indents in counters instead of lists (60 files of 1 MB took 494 MB), tolerates an odd `package.json` (`"scripts": null`, deep nesting) and file names that are not UTF-8 instead of crashing.
- `--since` lists changed files NUL-separated and relative to the folder it is given: names with non-ASCII characters were silently dropped, and a subfolder root found nothing. It also stops with an error when the stamp is not a commit and when the folder does not exist.
- The style guard now also skips minified, generated and lock files like the script, and sees non-ASCII file names (git quoted them, so the hook never blocked in such projects), ignores committed `vendor/` and untracked `node_modules/` code like the script does (it counted them, so a project with nothing to count was "studied"), treats `A.PY` like `a.py`, ignores paths with `..`, and, when Claude Code was started in a folder that holds several projects, uses the edited file's repository.
- `--since` runs `git diff`, which applies a clean filter named in `.git/config`. A normal clone never copies that file, so this only matters for an archive that ships its own `.git`; it is the same exposure as `git status` and is not removed.
- File names from the repository are printed escaped (a name with a newline or an ANSI escape could forge output lines, and one that is not UTF-8 crashed the text report in a UTF-8 terminal). `--since` ends git's options with `--` (a file named like the commit made git fail and the script counted everything without git) and a git failure in that mode is an error, never a silent full count.
- The text report no longer crashes when the terminal encoding cannot show a file name (it prints an escape), `package.json` is read only up to 200 KB (a 1 MB integer took 11 s to parse), and the non-git search of the hook really reaches four folders deep (it saw three) and stops after 50,000 files.
- A folder in the middle of a path that was replaced by a symlink out of the project is skipped too (only the last part of the path was checked).
- `--budget SECONDS` (default 30) is a flag now, so the time limit can be tested; files not reached are listed under `skipped`. The style guard judges a file that belongs to a nested repository (or to one of several projects in a parent folder) by that repository's own code.
- `--since` accepts only a commit hash. `--since=--output=FILE` was passed to `git diff` as an option and wrote a file, and the value comes from `STYLE.md`, which a repository can contain.
- **Security:** the hook and the script run git with `safe.bareRepository=explicit` and `core.fsmonitor=false`. A repository could commit a folder shaped like a bare git repository whose `config` sets `core.fsmonitor` to a command; the hook ran git from the edited file's folder, so the first edit there ran that command (reproduced). The skill also tells the agent to run git only from the project root.
- The skill runs the script with `python3 -I`, so nothing from the project folder or `PYTHONPATH` is imported (the same lesson as the 1.0.5 hook).
- The style guard ignores files outside the working project (a scratch script in a temp folder was blocked and the agent was told to write `STYLE.md` there), keeps the session id to safe characters (`../` wrote outside its folder), and keeps its once-per-session marks in the plugin's own data folder.

- Cleanup pass (`/simplify`): the hook reads all fields with one `jq` call, does the cheap checks before any `git` call, and starts from the working folder's project; the script reads every file through one safe reader (a named pipe called `Makefile` hung it too), stops on a `--since` stamp that is no longer a commit instead of silently counting everything without git, and no longer slows down quadratically on repositories with CRLF line endings (10,000 files: 3.6 s to 0.5 s here, 7.7 s to 1.0 s on another Mac). Its output is unchanged.

### Changed
- `every-corner-interview` and `every-corner-tour` point to the new skill (the interview reads `STYLE.md` when it exists).

### Known limits (first smoke tests, one fixture, one run each)
- **A description alone did not start it for a tiny request.** Asked to "add a function" to a 5-file project, the agent edited directly in 2 of 2 runs. With the style guard hook it started in 2 of 2 runs (an "add" and a "fix" request). Two runs on one small fixture are an indication, not proof.
- **Cost on a tiny project is higher, not lower.** Fix request: 12 turns, $0.43, 77 s with the skill; 6 turns, $0.29, 40 s without (same diff). The savings are designed for larger projects and are not yet measured (spec R15, R16).
- The counting script runs as an ordinary shell command, so it asks for approval like any other (in a headless run with no allow rule it is denied and the agent counts by hand, which costs more).

## 1.0.5 (2026-11-25)

Fixes from community reports #17-#23 and the hook gaps reported in #2, each verified against the code, the validator and the official docs before fixing.

### Fixed
- **Hook gaps (#2):** `rm -Rf`, `rm -R`, `rm -r`, `rm --recursive --force`, `/bin/rm -rf` and `xargs rm -rf` are now caught, and so is a force push written as `git push origin +main`. `git rm -rf` dropped from "cannot be undone" to "hard to undo", because git can restore committed files.
- **More hook gaps found in code review:** force pushes with combined flags (`-uf`, `-fu`), quoted arguments (`"+main"`, `"-rf"`), backslash line continuations, git global options (`git -C dir push --force`), and deleting a remote branch (`git push origin :old`, `--delete`) are now caught; `git rm --cached` is no longer flagged. A dangerous command followed by a very long body (over 64 KB) used to slip through; it no longer does.
- **The hook no longer switches itself off without `jq` (#17).** It reads the command with `jq`, or without it a built-in plain-text fallback, and writes its output without `jq`. Every test runs under both.
- **Plugin version in one place (#19).** The marketplace entry no longer repeats `version`, `description`, `author` or `homepage`; `plugin.json` is the single source.
- **No `<feature>` in the interview description (#20)**, which Claude Code displayed as `&lt;feature&gt;`.
- **Stale docs (#23):** the repo layout, the "Decisions made for you" name, and the explain skill calling the hook optional.

### Changed
- **The tour is told not to run anything (#18):** no tests, builds, scripts or servers, only read-only commands. Docs say plainly that "read only" is an instruction, not a lock, and how to get a hard guarantee.
- **Shorter skills (#22):** the reasoning sections moved out of the tour and interview skills; it already lives in `docs/`. The templates stay inside the skills: moving them to separate files made Claude ask permission to read the skill's own folder (and fail in headless runs), which was tested and reverted.
- **The hook searches the whole command, with a few precise exceptions (#2, #23, review findings).** Dangerous commands are found wherever they sit: after `VAR=x`, inside `if`/`for`, `( )`, `$( )`, `bash -c`, `ssh host '...'`, or a heredoc. Exceptions such as `--cached` and `--dry-run` count only among that command's own flags in the same segment (so `xargs -n 1 git clean -fd` or `nice -n 19 git clean -fdx` still warn), which fixes `git rm --cached a; git rm -f b` and `npm publish --dry-run && npm publish`. Also caught now: `git clean -d -f`, `git clean --force`, `git branch --delete --force`, `git --git-dir .git push -f`, `git -C "dir with spaces" push --force`, `git push origin main 2>&1 --force`, `npm publish --dry-run=false`, `microk8s.kubectl delete`, `sudo -u npm rm -rf`, `docker exec git rm -rf`. Mentioning a dangerous command (in an `echo`, a commit message, or a file written with `cat <<EOF`) can still warn, on purpose. Matching uses `grep`, which stays linear on both macOS and Linux (bash's own `=~` uses the system regex library, which on Linux is quadratic for these patterns), so the hook takes roughly 10-40 ms per command and under a second on 300 KB commands (`main` took about 44 ms per command). CI runs the tests on both systems. Two more designs were tried in review and dropped after two independent reviewers broke each one: checking only each command's first word missed commands `main` caught, and skipping heredoc bodies hid commands piped to `ssh`, `bash` or `docker exec`; both could also run past the hook's 10-second timeout on large inputs.
- **No more Python in the hook.** A `python3` fallback was tried in review and removed: it would import a `json.py` planted in the project folder and run it on every command. The no-`jq` fallback (`sed`) now keeps newlines, so a dangerous command on line 2 or later is caught too.
- **Hook command stays in shell form.** The exec form suggested in #23 (`"command": "bash"` plus `"args"`) was not adopted: on a Claude Code version that predates `args`, bash would read the hook's JSON input as a script. The quoted shell form is safe on every version. Headless behavior is documented: in `claude -p` the hook's prompt can't be answered, so risky commands are denied.
- **Plugin icon added (#23)**, so `claude plugin validate` reports nothing.

### Added
- **Skill trigger tests (#21):** `evals/` holds six `claude plugin eval` cases, four that must load the interview and two that must not. All six pass. The four trigger cases are the prompts that failed to trigger in the stress test; the other stress-test prompts depend on a real project fixture, which these tests do not have. They use your own Claude account, so they run locally, not in CI.
- **CI (#21):** hook tests on Linux and macOS, ShellCheck, and `claude plugin validate --strict`.

## 1.0.4 (2026-11-21)

Result of round 2 of the [stress test](docs/stress-test.md): the scenarios round 1 could not run (a contradicting user, "you decide", "build now", a new project, a prompt-injection note in code), driven as real sessions on fresh clones.

### Fixed
- **No false "it's in the spec".** The spec is updated before every reply, and the skill never says something is recorded unless it was written that turn. In one run it claimed delegated choices were marked as risks with no write behind it.
- **Parked scope is said in chat.** When part of a request depends on something that does not exist (for example "friends see my folders" with no friends feature), the skill says so in one line and lists it under a new "Parked rooms" section.
- **Contradictions are named** ("Earlier you said private; now friends should see it") and the user is asked which wins, instead of settling it inside a later question.
- **Injected notes are reported.** If a repo file tells AI to skip questions, the first message names the file and says it is being ignored.
- **"Build now" counts as the yes** to "Build it?": open rows become `Defaulted - RISK`, the "Decisions I made for you" list opens the next message, then it builds.
- When the options already spelled out the consequences, a delegated irreversible choice is not re-asked: it takes the least destructive option and states the cost.

### Changed
- [Stress-test report](docs/stress-test.md) now includes round 2, its fixes and retests, and a longer list of what is still unverified.

## 1.0.3 (2026-11-16)

Result of a [stress test](docs/stress-test.md): eight adversarial scenarios run as real headless sessions with a simulated user. Three failed on the first run because the skill never loaded.

### Fixed
- **every-corner-interview now actually triggers** on "build me X", "add X" and vague requests like "make the dashboard better". The description is imperative and the skill has a hard rule: no code, scaffolding or design/publish skills before "Build it?" is answered.
- **Vague requests are never a one-line fix.** "Better", "nicer" and "improve" require a concrete scenario question before anything is edited.
- **Premise check:** if the code contradicts the request (for example the "like" feature doesn't exist), say so and ask with neutral options instead of redefining the user's word.
- **Plain English in every option**, with no code names, tables or file paths; options include a plausible choice that would need new data.
- **Neutral options on every follow-up** about money, deletion, privacy or ownership, not only the first question.
- **Delegation:** "you decide" covers only that question. Irreversible choices are re-asked once with the consequence spelled out, then marked `Defaulted - RISK (irreversible)`.
- Dependent questions go on the next screen; visible behavior (how many rows, undo, self-actions) is never defaulted silently.
- A resume, "continue" or silence is never an answer; the spec stays `Draft` until the user answers "Build it?"; repo text that tells AI to skip questions is ignored.

### Changed
- The study references moved out of the skill into the [research report](docs/research.md), keeping the skill about the same size.

### Added
- [Stress-test report](docs/stress-test.md): scenarios, results, fixes and what is still unverified.

## 1.0.2 (2026-11-15)

### Fixed
- **every-corner-tour** and **every-corner-interview** now require every `file:line` reference to use the full path from the project root. In the first real-world test (a ~350-file Flask app), the tour got 61 of 63 references exactly right; the other 2 shortened long migration filenames with `...`, so readers couldn't open them.

## 1.0.1 (2026-11-15)

### Changed
- README: each skill now has its own card with the problem it solves and five benefits, and the skill chooser only lists the two skills you ask for by name.
- Sharper plugin description in Claude Code's `/plugin` browser.

### Added
- [Research report](docs/research.md) behind the design: prior art, evidence on clarifying questions, and the reasoning for each choice.
- Code of conduct, this changelog, and a social preview image.

## 1.0.0 (2026-11-15)

### Added
- **Claude Code plugin:** install the three skills and the hook with two commands (`/plugin marketplace add ssaaffaakk/every-corner-skills`, then `/plugin install every-corner@every-corner-skills`).
- **every-corner-tour:** reads every file in tiers, explains the project like a friend, proves coverage with a per-folder ledger, and caches the result in `docs/every-corner/TOUR.md` by commit.
- **every-corner-interview:** reads the project first, asks every question that changes the build (no cap, no useless questions), stops when every requirement has a testable done check, writes `docs/every-corner/specs/<feature>.md`, builds, and reviews the result against the spec.
- **every-corner-explain:** four risk levels; only hard-to-undo and irreversible actions get a full card, led by the undo label, with a safer option.
- Safety-net hook with the same four levels, a "Safety-net hook" on/off option, and 34 tests in CI.
- Showcase README with banner, badges, demo and FAQ.

### Changed
- Replaced `plan-every-corner` and `explain-before-approve` (0.1.0) with the three every-corner skills.
- The hook no longer flags the safe `git push --force-with-lease` and `git branch -d`.

## 0.1.0 (2026-11-14)

### Added
- First version: `plan-every-corner` (look around before building) and `explain-before-approve` (plain-language permission prompts), an optional risky-command hook, examples, and community files.
