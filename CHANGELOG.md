# Changelog

All notable changes to this project are listed here. Versions follow the `version` field in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json).

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
