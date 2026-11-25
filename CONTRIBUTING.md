# Contributing

Thanks for helping. This project exists so beginners can understand what an AI coding tool is doing, so clarity matters more than cleverness. Everything in this repo, including code comments, is written in English.

## Ways to help

- **Real before/after examples.** Show a permission prompt or a plan from your own work, with identifying details removed. These are the most useful contributions.
- **New hook patterns.** Dangerous commands we do not flag yet.
- **Wording fixes.** If a sentence confused you, it will confuse others.
- **Bug reports.** A skill that did not trigger, an explanation that was wrong or misleading, or a hook that flagged something harmless.

Not sure where to start? Look for issues labeled [`good first issue`](https://github.com/ssaaffaakk/every-corner-skills/labels/good%20first%20issue).

## Writing style

These rules apply to the skills, the hook warnings and the docs:

1. **Plain words first.** Say "delete the folder", not "remove the directory recursively". Put technical names in parentheses.
2. **Say whether it can be undone.** Every warning should make clear whether the action is easy to undo, hard to undo, or impossible to undo.
3. **Describe the real effect.** Never make a risky action sound softer than it is.
4. **Short.** If a warning does not fit in two sentences, it is too long.

## Adding a hook pattern

1. Add a new `elif match '...'` branch to [`hooks/explain-risky-commands.sh`](hooks/explain-risky-commands.sh) with a plain-language `reason`.
2. Add test cases to [`hooks/test-hook.sh`](hooks/test-hook.sh): at least one dangerous command that should be flagged, and one similar-looking safe command that should pass.
3. Run `./hooks/test-hook.sh` and make sure everything passes.

## Changing a skill

Each skill is a single `SKILL.md` file in `skills/<name>/`. When you change one:

- Keep the front matter (`name`, `description`) valid. The `description` decides when Claude uses the skill, so make it specific.
- If your change affects what users see, update the matching file in `examples/`.
- Describe how you tried it: which task, what Claude did before, and what it did after.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Make a focused change. One idea per pull request.
3. Fill in the pull request template.
4. CI runs the hook tests on Linux and macOS, ShellCheck, and `claude plugin validate --strict`. Please make sure they pass.

If you change a skill's `description`, also run the trigger tests locally (they use your own Claude account, so they don't run in CI):

```bash
claude plugin eval . --runs 1
```

## Releases (maintainers)

The version lives only in `.claude-plugin/plugin.json`. Bump it there, add a `CHANGELOG.md` entry, and tag the release. Do not add a `version` to the marketplace entry: when both are set, `plugin.json` wins and the two drift apart.

## Reporting problems

Use the issue templates. For a bug, tell us which skill, what Claude did, what you expected, and your Claude Code version. Please remove anything private (names, keys, internal paths) before pasting.
