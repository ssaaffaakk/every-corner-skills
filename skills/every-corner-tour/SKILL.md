---
name: every-corner-tour
description: Use when someone is new to an existing project, returns to one after a while, or asks to explain how a codebase works. Read every corner of the project in tiers, explain its logic in plain English like a friend telling a story, prove coverage with a per-folder ledger, and save it to docs/every-corner/TOUR.md so later sessions reuse it.
---

# Every Corner: Tour

Someone just walked into a house that is already built. Show them around the way a friend who knows it well would: what each room is for, how people move through it, where the odd creaky stairs are, and where to find things when they need them. Not a file listing, not a README summary.

**Read only.** You do not change any project code in this skill; the only files you write are the tour. Do not run the project's tests, builds, scripts or servers either: read the commands from the project's docs and config and list them in the tour. Only read-only shell commands (`git log`, `git ls-files`, `git blame`, `ls`, `grep`, `find`, `wc`) are allowed.

## Parameters

| Parameter | Default | Notes |
|---|---|---|
| `language` | English | |
| `reader` | `new-joiner` | Infer from the request (table below). It sets depth and emphasis. |
| `depth` | `standard` | `quick`, `standard` or `deep`. Small projects are read fully at any depth. |
| `tour_file` | `docs/every-corner/TOUR.md` | Keep it under about 200 lines. Longer material goes in `docs/every-corner/tour/<chapter>.md`. |
| `small_project_threshold` | about 50 source files | At or below this, read every source file fully. |

| Request sounds like | `reader` | `depth` (concept steps) |
|---|---|---|
| "I'm new", "onboard me", "explain this project" | new-joiner | standard (9-13) |
| "quick overview", "what is this?" | quick-look | quick (5-8) |
| "how is this architected", "deep dive" | architect | deep (14-18) |
| "how does <feature> work" | feature-explainer | standard, focused on that feature |
| "I need to fix <bug> in <area>" | bug-fixer | quick, focused on that path |

## Step 0: Reuse what exists

If `tour_file` exists, read its commit stamp and run `git diff --stat <stamp>..HEAD`. Re-tour only the folders that changed, update their ledger rows and the stamp, and tell the user what is new. Do not redo a full tour for a small change.

## Step 1: Level 0 - inventory every file

List every tracked file without reading contents (`git ls-files`, or a gitignore-aware listing if there is no git). Count files per folder. Put every top-level folder, and every important second-level folder, into the coverage ledger.

Mark these as **Skipped** with the reason right away: generated code, build output, vendored or copied third-party code, lockfiles, binaries and media, large data files. Never read them in full.

## Step 2: Level 1 - outline every source file

For every remaining source file, capture its outline: exports, classes, functions and their signatures, routes, and models. Use symbol search, `grep` for definitions, or language tooling. Do not read whole bodies yet.

In a large project, give each top-level folder to a helper agent (subagent) that returns a summary of at most about 30 lines: what the folder is for, its key files, what it depends on, and anything odd. This keeps raw file contents out of the main conversation.

## Step 3: Level 2 - read the core fully

Read in full only:

- **Entry points:** where the program starts (main files, server setup, the app shell, CLI commands).
- **The core path:** the files the most important flow passes through. Rank candidates by how often other code references them and how often they change (`git log --name-only`, count the repeats).
- **Config:** environment variables, settings, build and deploy files the project quietly depends on.

Treat the README as a claim to check, not a source of truth. When the code disagrees with it, say so.

## Step 4: Trace one real flow end to end

Pick the most important thing the project does (a user signs up, a request comes in, a job runs) and follow it from start to finish through the actual code. This becomes "The story". In a bigger project, trace a second major flow too.

## Step 5: Hunt the surprises

- `TODO`, `HACK`, `FIXME`, "do not change" comments.
- Code that looks wrong or odd: check `git blame` and the commit message to learn why.
- Hidden dependencies: environment variables, feature flags, cron jobs, things loaded by name at runtime.
- Duplicated logic, half-finished migrations, dead-looking code that is actually used.
- Anything that talks to the outside or is hard to undo.
- Tests that are skipped or flaky.

## Step 6: Verify before you write

Every `file:line` you will cite must exist and point at the right code. Re-open and check it. Never guess line numbers. If you could not confirm something, say "I think..., but I could not confirm it."

Write every path **in full, from the project root, exactly as it exists**: `migrations/versions/4b2c1a9d_add_user_table.py:19`, never `4b2c1a9d_...py:19`. Do not shorten paths with `...` or `…`, even long ones. A reference the reader cannot open is a broken reference. If a path is too long for a sentence, put the reference in a table or on its own line instead.

## Step 7: Write the tour

Write `tour_file` with this structure:

```markdown
# Tour of <project>

Written for: <reader> · Depth: <depth> · Commit: <short sha> · Date: <date>

## In one sentence
<What this project is for, in everyday words.>

## The story
<One real flow, step by step, in plain words, with `file:line` for each step.
End with a one-line summary of the loop, e.g. "door -> receptionist -> desk -> database -> page".>

## The map
<One small Mermaid diagram of the main parts. One, not five.>

## Concepts, from basic to advanced
### 1. <Concept>
- **What you're looking at:** <file:line and what it is>
- **How it works:** <plain explanation; an analogy if it helps>
- **Why it matters:** <the reason it is built this way>
- **Gotcha:** <the thing that trips people up, or "none">

## Glossary
- **<term>:** <meaning in this project>

## How to run it and check it works
<Exact commands, and what you should see. Taken from the project's own docs and config; the tour lists them, it does not run them.>

## Things that will surprise you
- <Quirk, with file:line and why, from git history if known.>

## Where to look when you want to...
| I want to... | Look at |
|---|---|
| change how login works | `src/auth/` |

## Coverage ledger
| Folder | Files | Status | Note |
|---|---|---|---|
| `src/routes/` | 12 | Explained | Concept 2 |
| `src/utils/` | 9 | Mentioned | Small helpers, outlined only |
| `public/vendor/` | 40 | Skipped | Third-party code copied in |
| `scripts/legacy/` | 3 | Unknown | Could not tell what calls these |

## What you can do now
<3-5 concrete next steps the reader is now ready for.>
```

**Ledger statuses:** Explained (covered in the tour), Mentioned (outlined, short note), Skipped (with a reason), Unknown (looked, could not work it out). Every top-level folder must have a row. A folder missing from the ledger is a bug in the tour.

## How to talk (this matters most)

- Write like a friend explaining over coffee: short sentences, everyday words, "you".
- Explain any technical term the first time in one clause ("the router, which decides which code handles each web address").
- Use an analogy when it makes something click; do not force one onto everything.
- Always give the **why**, not only the what.
- Be honest about uncertainty and about what you did not read.
- Never pad. A clear tour beats a long one. If the project is simple, say so.

## Step 8: Hand over in chat

In chat, give a short friendly summary (the one-sentence description, the story's one-line loop, the two biggest surprises), the path to `tour_file`, and ask what they want next: go deeper on a part, or start a feature. If they want to build something, hand off to `every-corner-interview`, which reads `tour_file` first and therefore asks fewer questions.

## Anti-patterns

- Restating the README. Listing folders without explaining how they work together.
- Claiming coverage of code you did not read. Silently skipping a folder.
- Guessed line numbers or file paths, or paths shortened with `...`.
- Five diagrams. Walls of jargon. Explaining *what* without *why*.
- Editing project files during a tour (only `tour_file` and its chapters are written).
- Running the project's tests, builds, scripts or servers. List the commands; do not run them.
