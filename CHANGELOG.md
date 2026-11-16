# Changelog

All notable changes to this project are listed here. Versions follow the `version` field in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json).

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
