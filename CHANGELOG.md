# Changelog

All notable changes to this project are listed here. Versions follow the `version` field in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json).

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
- **The hook searches the whole command, with a few precise exceptions (#2, #23, review findings).** Dangerous commands are found wherever they sit: after `VAR=x`, inside `if`/`for`, `( )`, `$( )`, `bash -c`, `ssh host '...'`, or a heredoc fed to a shell. Exceptions such as `--cached` and `--dry-run` count only within the same command segment, which fixes `git rm --cached a; git rm -f b` and `npm publish --dry-run && npm publish`. Also caught now: `git clean -d -f`, `git clean --force`, `git branch --delete --force`, `git --git-dir .git push -f`. Heredoc text that `cat` or `tee` writes to a file is ignored; mentioning a dangerous command in an `echo` or commit message can still warn, on purpose. All work is linear (one `awk` and one `sed` pass), so the hook takes roughly 10-20 ms per command and about 0.1 s on very large ones (it used to take about 44 ms). A segment-by-segment rewrite was tried in review and dropped: two independent reviewers showed it missed commands `main` caught and could time out on large inputs.
- **No more Python in the hook.** A `python3` fallback was tried in review and removed: it would import a `json.py` planted in the project folder and run it on every command. The no-`jq` fallback (`sed` + `awk`) now keeps newlines, so a dangerous command on line 2 or later is caught too.
- **Hook command stays in shell form.** The exec form suggested in #23 (`"command": "bash"` plus `"args"`) was not adopted: on a Claude Code version that predates `args`, bash would read the hook's JSON input as a script. The quoted shell form is safe on every version. Headless behavior is documented: in `claude -p` the hook's prompt can't be answered, so risky commands are denied.
- **Plugin icon added (#23)**, so `claude plugin validate` reports nothing.

### Added
- **Skill trigger tests (#21):** `evals/` holds six `claude plugin eval` cases, four that must load the interview and two that must not. All six pass. They use your own Claude account, so they run locally, not in CI.
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
