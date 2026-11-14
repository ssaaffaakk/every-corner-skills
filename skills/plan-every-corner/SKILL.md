---
name: plan-every-corner
description: Use before building or changing anything non-trivial. Walks through the "room" the task lives in (the desk, the drawers, under the rug, the doors) and produces a short, evidence-backed room report and a plain-language plan for the human to approve before any code is written. Skip for typo-sized changes.
---

# Plan Every Corner

Most failed first attempts are not bad code. They are a wrong assumption about the room: a helper that already exists, a config that overrides the change, a test that locks in the old behavior. A senior engineer spends the first ten minutes finding those. This skill makes you do the same, on purpose, and then lets the human correct you cheaply.

You do **not** write or edit code in this skill. It ends at an approved plan.

## When to use

Use it when the change touches more than one file, touches auth, data, money, config, migrations, or public interfaces, or when you are unsure how the area works. Do not use it for typos, renames in one file, or questions that need no change.

Scale the depth to the risk. A small feature gets a quick pass (steps 1-2, 5). Anything that touches data, auth, or other services gets the full pass.

## The process

### 1. The room: pin down the task

Restate the request in at most two sentences, plus what "done" looks like (something observable: a test passes, a page shows X, a command prints Y). If you cannot do this, you do not understand the task yet. That is your first question to the human.

### 2. The desk: what is directly in front of you

- The files you expect to change. Read them fully, not just the matching lines.
- Who calls them (search for usages, do not guess).
- The tests that cover them, and whether those tests currently pass.

### 3. The drawers: close by, not visible from the file

Look only at what could change your plan:

- Config and environment: env vars, feature flags, build and deploy config.
- Data shape: schemas, types, migrations, fixtures.
- Conventions: how similar things are already done here (find one good example and copy its pattern, do not invent a new one).
- Tooling: lint rules, CI checks, pre-commit hooks that will reject your change.

### 4. Under the rug: where surprises hide

- Comments like HACK, TODO, FIXME, "do not change", near the code you will touch.
- `git log` / `git blame` on any code that looks strange. The history usually explains why.
- Code that looks unused but is referenced dynamically (string lookups, reflection, config-driven loading).
- Generated files, vendored code, and duplicated logic you might fix in one place but not the other.
- Flaky or skipped tests in the area.

### 5. The doors: where the change touches the outside

- Database, queues, third-party APIs, other services.
- Anything that leaves the machine (network calls, emails, uploads).
- Anything hard to undo (deletes, migrations, publishes, pushes).

### 6. Stop rule

Stop exploring when one more search would not change what you would do. Do not tour the repo. Reading 40 files to summarize the README is the failure mode this skill exists to prevent.

## Evidence rules (what separates this from a generic tour)

- Every factual claim carries a reference: `path/to/file.ts:42`, a command you ran, or a commit hash.
- Anything you did not verify is labeled **assumed**, never stated as fact.
- If a search found nothing, say "searched X, found nothing" rather than staying silent. Absence is information.

## The output: a room report

Produce exactly this, and keep it short enough to read in two minutes:

```
## Room report

**Task (my understanding):** <1-2 sentences>
**Done looks like:** <observable result>

**What I found**
- <fact> (`file:line`)
- <fact> (`file:line`)

**Surprises / under the rug**
- <thing that could bite, with reference>

**Assumed, not verified**
- <assumption> -> <how it could be checked, or who to ask>

**Plan (plain language, in order)**
1. <what changes, in everyday words>
2. ...

**Risk and undo**
- <what could go wrong> / <how to revert>

**Questions that change the plan** (max 3, only if needed)
1. <question> - my default if you don't answer: <default>
```

Rules for the report:

- Plain language first. A junior should be able to read the plan and explain it back. Put technical names in parentheses, not up front.
- Questions only where the answer changes the plan, and never for things you could look up yourself. Always offer a default so the human can just say "go".
- If the room is simple, say so: "No significant surprises" is a valid, valuable result.

## Hand-off

After the human approves (or corrects) the report, state the final plan in one tight list and begin the work. While executing, use the `explain-before-approve` skill so every permission prompt is understandable. If you discover something that contradicts the report, stop and say so before continuing instead of quietly changing course.

## Guardrails

- Do not edit files, install packages, or run anything with side effects during this skill. Read-only commands only.
- Do not ask one question at a time in a long interview. Ask the few that matter, once, with defaults.
- Do not pad. A short, accurate report beats a long, impressive one.
