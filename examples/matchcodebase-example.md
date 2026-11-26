# Example: every-corner-matchcodebase

> The script output below is real: it is what `style-counts.py` prints for the fixture project in `tests/matchcodebase/fixtures/odd-python`. The chat messages and `STYLE.md` are illustrative; a real run cites and re-opens your actual files.

**Situation:** A developer inherits a small Python project and says: *"Add a function that saves an order's notes to a file."*

The project is unusual: it indents with tabs, quotes strings with `'`, and names Python functions in camelCase. Left alone, an AI agent would write `snake_case` functions, spaces and `"` quotes. Before writing a line, Claude runs the counting script. Nothing is run or installed; it only reads.

## What the script prints (real output)

```
STYLE COUNTS  root=<project>  git=True
files listed 7 | counted 5 | skipped 2 {'not source (docs, data, media, config)': 2}
folders: app 4, . 2, tests 1

== python (5 files, 117 lines)
indent: tabs (78% of indented lines use tabs)
quotes: double 8, single 21 -> single
line length: p95 33, max 41
functions: camelCase 80%, snake_case 20% (n=15)
classes: PascalCase 100% (n=3)
constants: UPPER_SNAKE 100% (n=3)
file names: snake_case 100% (n=2)
comments 0% of lines, docstring blocks 4
imports: 0/0 multi-line groups sorted; relative 0, absolute 5
idioms: raise 3
tests: 1 files e.g. tests/test_orders.py
examples (read in full): app/orders.py, app/billing.py
outliers (read in full) 1 total, showing 1:
  app/legacy_helpers.py  [indent spaces; quotes double; function names snake_case]

== tooling
configs: pyproject.toml[tool.ruff,tool.pytest], Makefile
commands: lint=make lint, test=make test
```

Claude then reads in full only `app/orders.py` (the area it will touch), `app/billing.py` (a second example) and `app/legacy_helpers.py` (the outlier). It checks the history and finds the outlier is the oldest file, so it is old style, not the project's direction.

## What Claude says in chat

> I counted 5 source files and read 3 in full. This project uses tabs, single quotes and camelCase function names; one older file (`app/legacy_helpers.py`) breaks all three, so I'm treating it as legacy. Style notes are in `docs/every-corner/STYLE.md`. Writing the new function in the project's style now.

## `docs/every-corner/STYLE.md` (excerpt)

```markdown
# Style notes for orders-app
Commit: a1b2c3d · Date: 2026-11-26 · Counted 5 files, read 3 in full

## Tools (run after writing code)
- lint: `make lint` · test: `make test`

## Rules the tools do not enforce
| Area | Rule | Evidence |
|---|---|---|
| Naming | Functions are camelCase (80% of 15) | `app/orders.py:19` `def loadOrders(path):` |
| Strings | Single quotes | `app/orders.py:28` `with open(path, 'w') as fh:` |
| Errors | Raise `KeyError` with a short message | `app/orders.py:16` `raise KeyError('missing ' + str(item))` |

## Mixed styles
- `app/legacy_helpers.py`: spaces, double quotes, snake_case. Oldest file; new files follow the rest of `app/`.

## Defects seen (not copied)
- none
```

## What it writes, and how it checks

The new `saveOrderNotes(path, notes)` goes into `app/orders.py` next to its neighbors, with tabs, single quotes and a camelCase name. Only the new lines change; untouched lines stay exactly as they were.

Afterwards Claude runs `make lint` and `make test`, compares the new function's naming and structure with `saveOrders` above it, confirms `git diff` shows no reformatting of old lines, and reports what was checked by the tools, what by comparison, and what it could not check.
