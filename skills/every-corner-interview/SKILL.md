---
name: every-corner-interview
description: Use before building a new feature or starting a new project. Treat the user's request as "the room" - read the existing project first, then ask every question that would change the build (and only those) until the room is fully described, write a spec to docs/every-corner/specs/<feature>.md, and build it in one shot. Skip for unambiguous one-line fixes.
---

# Every Corner: Interview

The user's request is **the room**. They know what room they want, but the first sentence only tells you that a room exists, not how big it is, what goes inside, or how it should behave. Builds fail when you fill those gaps with guesses. Your job is to find every gap that matters, close it with the user, write it down, and then build the room right the first time.

This is how an excellent senior developer starts a feature: read first, ask sharp questions, agree on what "done" means, then build without surprises.

## Why it works this way (evidence, briefly)

- When requirements are incomplete, code-model accuracy drops sharply (35-52% Pass@1 on HumanEvalComm). Asking clarifying questions recovers most of it (80-89% of full-spec performance on Ambig-SWE).
- Models under-ask by default: on HumanEvalComm, over 60% of responses wrote code instead of asking. You must interview deliberately.
- Question **count** is not the lever, question **value** is. The strongest agents explore the code first and need about half as many questions (Ambig-SWE). Questions the user cannot answer waste turns.
- Closed multiple-choice questions go unanswered about 1-2% of the time, open ones about 18% (Pew). Use options wherever possible.
- Models catch subtle data-semantics ambiguities (ordering, comparison rules, collection handling) less than 20% of the time on their own (ClarifyCodeBench). Check them explicitly.

## Parameters

Defaults apply unless the user or the project says otherwise.

| Parameter | Default | Notes |
|---|---|---|
| `language` | English | All questions, specs and messages are in English. |
| `spec_dir` | `docs/every-corner/specs/` | One file per feature: `<feature-slug>.md`. Never overwrite another feature's spec. |
| `tour_file` | `docs/every-corner/TOUR.md` | Read it first if it exists (written by `every-corner-tour`). |
| `question_budget` | none | Ask until the stopping rule passes. No cap, no checkpoint pauses. |
| `questions_per_screen` | up to 4 | The `AskUserQuestion` tool limit. Use as many screens as needed. |
| `build_session` | same for T1-T2, fresh for T3-T4 | See Step 8. |

## Step 1: Size the room

Classify the request. The tier sets how much to read and how big the spec is. It never caps the questions. If you discover hidden complexity, move the tier **up**, never down. State the tier in one line ("This looks like a medium feature: it touches stored data and two screens.") so the user can correct it.

| Tier | Signals | Spec | Build |
|---|---|---|---|
| **T0 Fix** | One obvious change, no behavior choices | None. State your assumptions in one or two lines and build. | Same session |
| **T1 Small** | One behavior, one place in the app | Short (half a page) | Same session |
| **T2 Medium** | Several behaviors, touches stored data or more than one screen or service | 1-3 pages | Same session |
| **T3 Large** | New data model, new APIs, auth/payments, cross-cutting changes | 3-8 pages | Fresh session |
| **T4 New project** | Empty folder or a new product | Split into sub-rooms first | Fresh session per sub-room |

**T4:** before any detailed question, split the project into sub-rooms (for example: accounts, the core feature, admin, deployment). Agree on the list and the order with the user, then interview one sub-room at a time, each with its own spec file.

## Step 2: Read before you ask

Never ask what the project can tell you.

1. If `tour_file` exists, read it first. Check its commit stamp against `git log -1`; if the project changed a lot since, re-check only the parts you need.
2. Otherwise, take a proportional look:
   - **The desk:** the files this feature will touch, who calls them, the tests that cover them.
   - **The drawers:** config, data shapes and schemas, and how similar features are already built here. Find one good example to copy.
   - **Under the rug:** `TODO`/`HACK` comments and odd history (`git log`, `git blame`) near the area.
   - **The doors:** databases, external services, anything that leaves the machine or is hard to undo.
3. For a new project there is nothing to read. Skip to Step 3.

Answer from the code everything you can: the stack, conventions, existing helpers, auth, the test setup, naming. These become **Discovered** rows, not questions.

## Step 3: Draft the spec before asking

Create `spec_dir/<feature-slug>.md` from the template at the end of this file. Fill in every section with what you discovered and your best guesses. Then mark each row of the coverage ledger:

- **Discovered:** answered by the code (cite `file:line`).
- **Defaulted:** you chose a sensible default the user is unlikely to care about (write the reason).
- **Open:** needs the user.
- **N/A:** does not apply to this room.

Questions now target gaps in a concrete document instead of a blank page.

## Step 4: Decide what to ask

These are the areas of the room. Walk every row; most will be Discovered, Defaulted or N/A.

| Room aspect | Ledger rows | Usual question form |
|---|---|---|
| **Purpose** | goal, who uses it, what success looks like | open (intent belongs to the user) |
| **Size** | scope boundary, **explicit non-goals**, data volume and scale, phasing | multiple choice |
| **Contents** | things it stores, how each is identified, unique rules, lifecycle and states, integrations and what happens when they fail | multiple choice |
| **Behavior** | what happens on each trigger, in each state, optional features; UX flow including **empty, loading and error** states | scenario: "When X, should it...?" |
| **Edge cases** | wrong or missing input, zero/one/max, failure, two people at once, permissions | scenario |
| **Data semantics** (always check) | ordering, duplicates, comparison rules (case, whitespace, time zones), how collections are treated (empty list vs none), ranges, units, precision, output format, atomicity (all-or-nothing) | scenario |
| **Constraints** | stack, hosting, performance, security and privacy, compliance | multiple choice, often Defaulted |
| **Terminology** | words that could mean two things; vague adjectives ("fast", "simple", "secure") | short answer or options |
| **Done** | a testable check for every requirement; definition of done | confirm a proposed test |

Ask a question only when **all four** are true:

1. **Only the user can answer it.** Not the code, not common sense.
2. **The answer changes the build.** Different plausible answers would change the code, the data or the tests.
3. **It has not been asked already.** Do not re-ask an aspect in different words.
4. **The user can realistically answer it.** Do not ask a non-technical user which library or pattern to use. Decide implementation details yourself and record them as Defaulted.

Everything that fails the test becomes a stated default in the spec.

## Step 5: Ask

Use the `AskUserQuestion` tool when it is available. Ask as many questions as the room needs: one, or twenty.

**Order:** hardest-to-reverse first. Scope and non-goals, then the data model, then the core flows, then edge cases and data semantics, then look and feel. Early answers often remove later questions.

**Screens:** put up to 4 **independent** questions on one screen. Questions that depend on an earlier answer go on the next screen. After each screen, update the spec (the ledger and the Clarifications log) before asking more.

**Each question:**

- Plain English, no jargon. One clause on why it matters if that is not obvious.
- 2-4 concrete options. Do not add an "Other" option; the tool provides it.
- **Reversible choices:** put your recommended option first and mark it "(Recommended)", with a short reason. The user can accept it with one click.
- **Irreversible or high-stakes choices** (deleting data, money, privacy, public exposure): show the options neutrally with their consequences. Do not nudge.
- Use a scenario for behavior and edge cases: "A user favorites a recipe that is later deleted. What should they see?" Scenarios surface real decisions; abstract questions do not.
- Purpose questions may be open: the goal is the user's alone.

**When the user writes instead of choosing:** read what they actually said. If it answers the question, record it. If it changes the room, update the tier and the spec, and say what changed. If they did not understand, re-ask in simpler words with an example. Never treat silence or "ok" as an answer to a question you did not ask.

**"Build now":** the user can stop the interview at any time. Move every Open row to Defaulted with your best choice, list them as **risks** in the spec, and continue to Step 7.

**Without `AskUserQuestion`:** write the questions as a numbered list with lettered options and the recommendation marked, so the user can reply `1a, 2b, 3 rec`.

## Step 6: Stopping rule

Stop asking only when **all** of these are true:

- Every ledger row is Discovered, Answered, Defaulted or N/A. None is Open.
- Every requirement has a **testable done check** (a test, a command, or something visible on a screen). If you cannot write one, the requirement is still ambiguous: ask.
- No remaining choice would change the code, data or tests in a way the user would care about.
- Every data-semantics row has been checked.

If Step 2 and Step 3 leave nothing Open, say "I have everything I need" and skip straight to Step 7. A room that needs no questions is a valid result.

## Step 7: Confirm

Show a short summary in chat, not the whole spec:

- The goal in one sentence.
- 3-7 key decisions (answered and defaulted).
- What is out of scope.
- The risks (any "build now" defaults).
- The spec path.

Ask: "Build it?" Apply corrections to the spec before building.

## Step 8: Build

- **T0-T2:** build now, in this session, following the spec.
- **T3-T4:** tell the user to start a fresh session and say: `Build docs/every-corner/specs/<feature>.md`. The spec carries everything; the interview transcript would only fill the context. If your environment can start a session for them, offer to.

While building:

- Follow the spec. If reality contradicts it (a file is not what you expected, a decision cannot work), **stop and ask**, then update the spec. Do not quietly change course.
- Use `every-corner-explain` for every permission prompt. "Why" can point to the spec ("step 3 of the spec").

After building, run every done check, then do a **review pass**: walk the spec requirement by requirement and mark each Met / Not met / Changed (with reason) in the spec's Review section. Report the result in chat.

## Anti-patterns

- Asking what the code already answers ("Which framework do you use?").
- Asking implementation questions the user cannot judge ("Should I use a reducer or a store?").
- Asking several aspects as one question, or re-asking a decided aspect in new words.
- Abstract questions ("How should errors be handled?") instead of scenarios.
- Nudging on irreversible choices.
- A 20-page spec for a small feature, or a 4-story ceremony for a bug fix. Match the spec to the tier.
- Silently changing the plan during the build.

## Spec template

```markdown
# <Feature name>

Tier: <T1-T4> · Status: Draft | Agreed | Built · Last updated: <date> · Commit: <short sha>

## Goal
<One or two sentences: what this does and for whom.>

## Non-goals
- <What this explicitly will not do.>

## Glossary
- **<term>:** <meaning in this project>

## Requirements
Use these sentence shapes (EARS) so every requirement is checkable:
- Always: "The <system> shall <response>."
- On an event: "When <trigger>, the <system> shall <response>."
- In a state: "While <state>, the <system> shall <response>."
- Optional feature: "Where <feature is enabled>, the <system> shall <response>."
- Unwanted behavior: "If <bad thing>, then the <system> shall <response>."

| ID | Requirement | Done check |
|---|---|---|
| R1 | When a logged-in user clicks the heart, the app shall save the recipe to their favorites. | Test: `favorites.test.ts` "adds favorite" |

## Edge cases and data rules
- <Each decided edge case and data-semantics rule.>

## Assumptions (defaulted)
- <Choice> - <reason>. <Mark "RISK" if it came from "build now".>

## Plan
1. <Step in plain language.>

## Risk and undo
- <What could go wrong> / <how to revert>

## Coverage ledger
| Aspect | Status | Source |
|---|---|---|
| Scope boundary | Answered | Q2 |
| Auth | Discovered | `src/middleware/auth.ts:5` |
| Sorting order | Defaulted | Newest first, matches comments list |

## Clarifications log
- Q1 <question> -> <answer>

## Review (after build)
| ID | Result | Note |
|---|---|---|
| R1 | Met | |
```
