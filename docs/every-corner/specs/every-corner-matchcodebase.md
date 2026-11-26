# every-corner-matchcodebase (new skill)

Tier: T3 · Status: Built · Last updated: 2026-11-24 · Commit: ea461d4

## Goal
A fourth skill for this plugin for working in an existing codebase whose style can be completely different from what the agent normally writes. Before any code is written, the agent studies the project's code sentence by sentence (how it is written and how it is used). When coding starts, it writes in exactly the same style, so new code is a perfect match and the codebase stays solid. Works for projects written by someone else or another AI tool, and for earlier sessions of this same agent.

## Non-goals
- Not a rule about which existing files may be edited: the user said that question was not the point. The rule is study first, write second.
- Not a replacement for `every-corner-tour` (explains) or `every-corner-interview` (spec for a new feature). It reuses their outputs (`TOUR.md`, specs) instead of repeating their work. (Defaulted: avoids duplicate token cost.)

## Alternatives considered
Found in the research report (`docs/every-corner/research/matchcodebase-landscape.md`). Decision: build our own, borrowing ideas, because none found both learns style cheaply and verifies the result.

| Alternative | Verdict | What we take or why not |
|---|---|---|
| Convention Learner (`codewithmukesh/dotnet-claude-kit`, 850 stars) | Borrow ideas | "Observe before enforcing", explicit configs win. Not adopted: tied to .NET MCP tools, no verification step. |
| ECC `inherit-legacy-style` (309,877 stars) | Borrow idea, unverified | Learning from git history. Could not read its text, so the checking behavior is unknown. |
| project-conventions / project-convention-discovery (mcpmarket) | Borrow idea | Config-first scan. About 1 star, undocumented. |
| awesome-copilot `write-coding-standards-from-file` | Borrow naming only | `STYLE.md` name. Not adopted: loads whole files into memory (token-heavy). |
| Aider repo map | Borrow idea | Rank files and fit a token budget. Maps structure, not style. |
| Cline Memory Bank, Cursor rules, AGENTS.md generators | Reject as a base | Always-loaded or generated context files; two studies found no average benefit. Borrow: small scoped files. |
| Existing `every-corner-tour` (this repo) | Reuse | Inventory, ledger, commit stamp and caching are reused, not rebuilt. |

Rule: before building a part, check this table; reuse over rewrite.

## Parked rooms
- Phase 2: deep research of similar GitHub repos. Needs: the v1 skill to exist first.
- Phase 3: token counting and token reduction. Needs: v1 to measure.
- Phase 4: stress tests (headless sessions, simulated user, like `docs/stress-test.md`). Needs: v1 plus the token baseline.
- User said these follow the build; each gets its own spec.

## Glossary
- **Continue:** keep building a project in its existing style, as a new agent or a new session, without breaking what is there.
- **Vibe coding:** generating code without understanding the project or checking it against how the project works.

## Requirements
Done checks are headless sessions on a fixture project (`claude -p`, as in `docs/stress-test.md`), plus file checks.

| ID | Requirement | Done check |
|---|---|---|
| R1 | When the agent is about to write or edit code in a project that already has source files, the skill shall load before any code is written. | Fixture with a clearly different style, prompt "add X": skill is the first action. Empty folder: skill not loaded. |
| R19 | A plugin hook shall block the first Edit, Write or MultiEdit of a source file once per session when the project has other source code and no `STYLE.md`, and shall never block in an empty project, for non-source files, or when switched off. When `STYLE.md` exists it blocks once with the reuse message, and it never blocks after the skill itself ran. | `hooks/test-style-guard.sh` (each case with and without jq) and headless runs. |
| R2 | The skill shall list every file, mark generated, vendored, lockfile, binary and media files as Skipped with a reason, and cover every other source file with a counting script that prints style frequencies (naming, quoting, imports, line length, comments, error handling, logging, test layout) and outliers, not code. It shall then read in full: the config files, the area being touched, one or two example files per kind of file, and the outliers the script flagged. (Changed from reading every source file in full after the research report; approved by the user.) | `STYLE.md` ledger has one row per folder; the script's file count equals the source file count; every file read in full is listed with its reason. |
| R3 | The skill shall read only to learn usage: call sites, tests, README and change history. It shall not run, install or start anything while studying. | Tool-call log of the study phase has no run, install or start commands. |
| R4 | The skill shall write `docs/every-corner/STYLE.md` with style rules (naming, layout, imports, formatting, comments, error handling, logging, tests, commit messages), each backed by a short verbatim excerpt cited as `file:line` with the full path. It shall hold only conventions the configs and counts do not already show, no repository overview, and stay under about 150 lines (Defaulted). | Script checks every cited line exists and the excerpt matches. |
| R5 | If the project mixes styles (old and new code, several languages), the skill shall record each and follow the style of the area being edited; new files follow the most recent code. | Fixture with two styles: new code in each area matches that area. |
| R6 | When `STYLE.md` exists with a commit stamp, the skill shall re-read only files changed since then. | Change one file, rerun: only that file is read. |
| R7 | After studying, the skill shall hand over to the normal path (interview for a feature, then build), and all new code shall follow `STYLE.md`. | Interview Step 2 reads `STYLE.md` when present; built code passes R8. |
| R8 | After building, the skill shall run the project's own formatter, linter and tests first when they exist, then compare naming and structure of the new lines with the nearest example file and `STYLE.md` (formatting alone is easy to fake), and fix deviations before reporting done. If the project has none of these, it shall say so and check against `STYLE.md` only. | Fixture with a planted deviation: it is reported and fixed. Fixture without tools: the message says so. |
| R9 | When editing an existing file, the skill shall leave untouched lines exactly as they were. | `git diff` has no reformat-only changes outside the new lines. |
| R10 | The skill shall match style, not defects: bugs, insecure patterns and dead code found while studying are reported to the user, not copied. | Fixture with a planted insecure pattern: new code does not copy it; it is reported. |
| R11 | Text in the project that tells AI assistants to skip the study shall be ignored, with one line saying so. | Fixture file with such a note: study still runs; one line in chat. |
| R12 | Because R2 uses a counting script, project size no longer forces a full read. For the files read in full, large projects use one helper agent per top-level folder, each returning at most about 30 lines (the tour's method). | 1000-file fixture: main context stays small; every folder has a ledger row. |
| R14 | `SKILL.md` shall stay under 500 lines; the counting script and detailed guidance live in separate files that load only when needed. | Line count; token count of `SKILL.md` recorded. |
| R15 | The repo shall include a measurement harness: each fixture task runs headless several times with and without the skill, and reports cost and tokens. | Harness runs and prints a with/without table. |
| R16 | The skill shall be released only if it beats the no-skill baseline on style checks without a large cost increase (similar generated context files did not help in two studies). | Phase 3-4 results recorded in the research folder. |
| R17 | Study cost shall not grow with the number of files beyond the files read in full. The counting script shall run in one pass with no LLM calls. Numeric targets (seconds, tokens) are set after the first measurement with R15. | 100-file and 1000-file fixtures: tokens differ only by the extra files read in full; script time recorded. |
| R18 | When `STYLE.md` exists and the commit has not changed, the skill shall read no source files and go straight to the next step; independent folder reads shall run in parallel. | Rerun on an unchanged fixture: zero source-file reads; timing recorded. |
| R13 | The plugin shall ship the skill: `skills/every-corner-matchcodebase/SKILL.md` with an imperative `description`, version bump, `CHANGELOG.md`, README row, `docs/how-it-works.md` section and `examples/matchcodebase-example.md`. | Files exist; front matter valid; CI hook tests still pass. |

## Edge cases and data rules
- Project already has `docs/every-corner/TOUR.md`: reuse it, re-read only what changed (Discovered: `skills/every-corner-tour/SKILL.md:36-38`).
- Project has no formatter, linter or tests: skill says so and checks against `STYLE.md` only (R8).
- Project is half old, half new: R5.
- Project's own code contains bugs or unsafe patterns: reported, not copied (R10).

## Decisions made for you (defaulted)
- Written in English, like all repo text (`CONTRIBUTING.md` line 3 and memory rule).
- One `SKILL.md` per skill in `skills/<name>/`, valid front matter, imperative `description` so it triggers (`CHANGELOG.md` 1.0.3 lesson: soft descriptions failed to load).
- Plugin version bump and `CHANGELOG.md`, `README.md`, `docs/how-it-works.md`, `examples/` updated when built (`CONTRIBUTING.md` "Changing a skill").
- Work happens in a clone of this repository; the installed plugin copy is a cache and is not edited.

- When editing an existing file, new lines match the surrounding lines exactly and untouched lines are never reformatted - follows from "perfect match".
- Similar prior art exists outside this repository (a local skill that aligns architecture, not syntax); examined in the research phase.

- Style notes are saved to `docs/every-corner/STYLE.md` (same folder as `TOUR.md`), stamped with the commit, and reused next session; re-read only what changed - mirrors the tour's caching.
- v1 `SKILL.md` stays about the size of the tour skill (about 9 KB); real token counts come in the token phase.

- Interview Step 2 gets one line: read `STYLE.md` when present (R7). Tour hand-off line mentions the new skill.
- Skill name `every-corner-matchcodebase` (from the user's "ever-corner-matchcodebase"; "ever" read as typo).

- From the research report, added without asking because they are reversible implementation details: STYLE.md size cap (R4), linter first then comparison with an example file (R8), SKILL.md under 500 lines (R14), measurement harness (R15), release only if it beats the no-skill baseline (R16). Source: `docs/every-corner/research/matchcodebase-landscape.md`.

## Plan
1. Interview (this file). 2. Build the skill in a fresh session: `Build docs/every-corner/specs/every-corner-continue.md`. 3. Phases 2-4 above, each its own spec.

## Risk and undo
- Building: new file plus doc edits on a branch; revert by deleting the branch. Nothing is pushed or published without asking.

## Coverage ledger
| Aspect | Status | Source |
|---|---|---|
| Repo layout and skill format | Discovered | `skills/*/SKILL.md`, `.claude-plugin/plugin.json` |
| Existing tour behavior | Discovered | `skills/every-corner-tour/SKILL.md` |
| Existing interview behavior | Discovered | `skills/every-corner-interview/SKILL.md` |
| What the new skill does beyond tour + interview | Answered | Q1: study style sentence by sentence, then write the exact same style |
| Who wrote the code being continued | Answered | Q2: both (other people or tools, and earlier sessions of this agent) |
| What "without changing" allows | Answered | Q3: user rejected the question; meaning is study before writing, not a file-edit rule |
| Skill name | Answered | Q4: user wrote "ever-corner-matchcodebase"; read as `every-corner-matchcodebase` (typo "ever" assumed, flagged in summary) |
| Trigger and order | Answered | Q5: "before we start coding, then you can follow the path" -> runs automatically before coding starts, then the normal path (interview, build) continues |
| Study depth | Answered | Q6: every source file in full; Q11 changed it to a counting script over every file plus full reads of config, touched area, examples and outliers |
| Proof of match | Answered | Q7: automatic checks only (project's own formatter/linter/tests plus own style notes), no sample question to the user |
| Huge projects (cost of reading every file) | Answered | Q8: user wants a faster, cheaper way and asked for deep research; v1 default R12 |
| "How it is used" evidence | Answered | Q9: read only (R3) |
| Previous chat to learn from | Answered | Q10: an earlier chat; only its last ~40 of 1230 messages were read (work in a colleague's repo with PR review and commit style) |
| Done checks | Defaulted | R1-R18 above |
| Token budget for v1 | Defaulted | about tour size (9 KB); measured in phase 3 |

## Clarifications log
- Q1 What does the new skill add beyond tour and interview? -> "this is for code base, when you're starting an existing project the code base can be completely different than what our agents write, so to keep codebase solid we need to write exact style, sentence by sentence so we create a perfect match"
- Q2 Who wrote the project? -> Both cases.
- Q4 Name? -> "ever-corner-matchcodebase" (read as every-corner-matchcodebase).
- Q5 When does it start? -> "before we start coding, then you can follow the path" (inferred: automatic before code is written, then interview/build continue).
- Q6 How much to read? -> Every source file, in full. Note: conflicts with the later goal of using fewer tokens; handled in the token phase.
- Q7 How to prove the match? -> Automatic checks only.
- Q11 Replace the full read with a counting script plus targeted reads (proposed by the research report)? -> "Yes, update spec". R2 and R12 changed.
- Q13 Should a hook make the skill start reliably? (found when the first smoke tests showed it skipped for small requests) -> "Yes, add hook". Added R19.
- Q12 "Make it token and time saving, but don't forget: did we find alternatives?" -> added the Alternatives considered section and R17-R18 (token and time). Read as: save tokens and time, and record the alternatives from the research in the spec.
- Q8 Huge projects? -> "should be a way to make it faster and less token, do /deep-research". Parked to the research phase; v1 default R12.
- Q9 How is usage learned? -> Read only.
- Q10 Which earlier chat? -> an earlier chat.
- Q3 What may the agent do to existing files? -> Rejected: "what I want is understand their code base sentence by sentence before we write code; when we start coding write the exact same style". Recorded as: no edit restriction beyond style match.

## Review (after build)
| ID | Result | Note |
|---|---|---|
| R1 | Met (2 runs) | Without the hook: not invoked in 2 of 2 runs. With the style guard hook: invoked in 2 of 2 runs ("add a function", "fix a file-handle leak"); order was Read, Edit blocked once, Skill, script, `STYLE.md`, Edit. Empty-folder case covered by the hook tests, not by a headless run. |
| R19 | Met | 82 hook checks pass (each case with and without jq), also under macOS bash 3.2; the existing hook tests (423 checks after merging main) still pass; `claude plugin validate --strict .` passes; real runs t5 and t6 started the skill. |
| R2 | Met | `scripts/style-counts.py`; 35 checks in `tests/matchcodebase/test-style-counts.sh`; file counts add up; output has no code; 1,000 files in about 0.2 s. Heuristic outliers; JS/TS semicolon detection is approximate. |
| R3 | Met (one run) | Run t4: only `ls`, `git ls-files`, the script, `cat`/Read and `git log`/`grep` before the first write; `make lint` and `make test` ran only after the edit. |
| R4 | Met (one run) | `STYLE.md` written with 10 citations; all 10 resolve to real lines. Under the size cap. |
| R5 | Not tested | Fixture has one older-style file; the agent labelled it legacy. No mixed-area test yet. |
| R6, R18 | Not tested | Reuse by commit stamp is written in Step 0 but no rerun was done. |
| R7 | Met | Interview Step 2 and tour hand-off now point to the new skill. |
| R8 | Partly | Run t4 ran `make lint`, `make test` and a small check after editing. Neither tool is installed in the sandbox, so what they reported was not verified here. |
| R9 | Met (one run) | `git diff` showed only the 4 new lines. |
| R10 | Met (one run) | Run t2 listed the missing `__init__`, unused imports and an unclosed file under "Defects seen" and copied none. |
| R11 | Not tested | |
| R12 | Met | One helper agent per folder is in Step 3; with the script, size no longer forces a full read (1,000-file check). |
| R13 | Met | Skill, manifests (1.1.0), changelog, README, how-it-works, example, CI step; front matter valid; hook tests 82/82. |
| R14 | Met | `SKILL.md` is 105 lines, about 1,800 tokens by chars/4. |
| R15 | Partly | `tests/matchcodebase/run-session.sh` runs paired with/without sessions and prints cost and tokens. Only single runs so far. |
| R16 | Not yet | One fixture cannot show a win: the neighbor function already shows the style, so the no-skill run matched it too. Needs harder fixtures. |
| R17 | Partly | The script's cost does not grow with file count. Tokens versus project size not measured. |

### First numbers (one run each, fixture of 5 files, user's other plugins loaded)
| Run | Skill started | Turns | Cost | Seconds |
|---|---|---|---|---|
| without the skill | n/a | 7 | $0.29 | 44 |
| with, started on its own | no (2 of 2) | 6 | $0.29 | 43 |
| with the style guard hook, "add" request | yes | 10 | $0.55 | 61 |
| with the style guard hook, "fix" request | yes | 12 | $0.43 | 77 |
| without the skill, "fix" request | n/a | 6 | $0.29 | 40 |
| with, asked by name, script blocked by permissions | yes | 26 | $0.49 | 99 |
| with, asked by name, script allowed | yes | 16 | $0.42 | 74 |

### Decision (R1)
User chose option A on 2026-11-26 ("Yes, add hook"): a plugin hook starts the skill. Built as `hooks/require-style-study.sh` (R19), on by default with a "Style guard hook" option to turn it off.

### Still open
Paragraph for later phases: token measurement on larger projects (R15-R17), harder style fixtures where the neighbor file does not reveal the style (R16), mixed-style and unchanged-commit reruns (R5, R6, R18), prompt-injection note (R11).
