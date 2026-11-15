# Example: every-corner-interview

> Illustrative example. It continues the recipe app from the [tour example](tour-example.md). File names and line numbers are made up.

**The user says:** *"Add a favorites feature so people can save recipes."*

---

## 1. Size the room

> This looks like a **medium feature (T2)**: it stores new data and touches two screens. I'll build it in this session once we agree.

## 2. Read before asking

Claude reads `docs/every-corner/TOUR.md` and checks a few files. These are **Discovered**, so they are not asked:

- Accounts and login exist (`src/middleware/auth.js:5`).
- Comments are built as route → controller → table; favorites will copy that pattern.
- Recipes are never really deleted, only marked `deleted = 1` (`src/controllers/recipes.js:58`).
- Tests use Mocha in `test/`.

## 3. Draft the spec

Claude creates `docs/every-corner/specs/favorites.md` with best guesses. These become **Defaulted**, not asked:

- Favorites are listed newest first, matching comments.
- Saving the same recipe twice does nothing (no duplicates).
- Implementation: a `favorites` table with user, recipe and time; the user can't judge that, so Claude decides.

Six aspects are still **Open**.

## 4-5. Ask

**Screen 1** (four independent questions, hardest to reverse first):

> **1. Who can save favorites?**
> ○ Only logged-in users (Recommended): favorites need an account to be remembered
> ○ Anyone, saved only in their browser
>
> **2. A user saved a recipe that the author later deletes. What should they see?**
> ○ It disappears from their favorites quietly (Recommended)
> ○ A grey "This recipe was removed" placeholder
>
> **3. Where do favorites show up?**
> ○ A heart button on each recipe, plus a "My favorites" page (Recommended)
> ○ Only the heart button for now
>
> **4. Can other people see someone's favorites?**
> ○ No, they are private
> ○ Yes, on their public profile
> *(No recommendation: this is a privacy choice, so both are shown neutrally.)*

The user picks: 1 recommended, 2 recommended, 3 recommended, 4 "No, private".

**Screen 2** (depends on screen 1's answer to question 3):

> **5. What does an empty "My favorites" page say?**
> ○ "No favorites yet" plus a link to browse recipes (Recommended)
> ○ Just an empty list
>
> **6. A visitor who is not logged in clicks the heart. What happens?**
> ○ Go to the login page, then come back and save it (Recommended)
> ○ Show a message: "Log in to save favorites"

The user types instead of clicking: *"5 recommended. For 6, the first one, but don't lose their place on the page."* Claude records the extra detail as a requirement.

## 6. Stopping rule

Every ledger row is now Discovered, Answered or Defaulted. Every requirement has a done check. The data rules (ordering, duplicates, deleted recipes) are decided. Claude stops asking. That was 6 questions; a bigger room would have taken more.

## 7. Confirm

> **Goal:** Logged-in users can save recipes and see them on a private "My favorites" page.
>
> **Key decisions:** account required · favorites are private · deleted recipes vanish quietly · newest first · no duplicates · logged-out click goes to login and returns to the same spot.
>
> **Out of scope:** sharing, folders, notifications.
>
> **Spec:** `docs/every-corner/specs/favorites.md`
>
> Build it?

## The spec (excerpt)

```markdown
# Favorites

Tier: T2 · Status: Agreed · Last updated: 2026-11-15 · Commit: a1b2c3d

## Goal
Logged-in users can save recipes and see them on a private "My favorites" page.

## Non-goals
- Sharing favorites, folders or collections, notifications.

## Requirements
| ID | Requirement | Done check |
|---|---|---|
| R1 | When a logged-in user clicks the heart on a recipe, the app shall save it to their favorites. | Test "adds favorite" |
| R2 | When a user clicks a filled heart, the app shall remove the recipe from their favorites. | Test "removes favorite" |
| R3 | If a saved recipe is deleted, then the app shall leave it out of "My favorites". | Test "hides deleted" |
| R4 | If a logged-out visitor clicks the heart, then the app shall send them to log in and return them to the same place on the page. | Manual check, steps in Plan |
| R5 | The app shall show a user's favorites only to that user. | Test "other user gets 404" |

## Coverage ledger
| Aspect | Status | Source |
|---|---|---|
| Who can favorite | Answered | Q1 |
| Deleted recipes | Answered | Q2 |
| Privacy | Answered | Q4 (neutral options) |
| Ordering | Defaulted | Newest first, matches comments |
| Duplicates | Defaulted | Ignore repeat saves |
| Auth | Discovered | `src/middleware/auth.js:5` |
```

## 8. Build

Claude builds in the same session, explaining each risky step with `every-corner-explain` (the new table is "⚠️ HARD TO UNDO, step 1 of the spec"). Then it runs the tests and fills in the Review table: R1-R5 Met.

---

## Why this works

| Choice | What it prevented |
|---|---|
| Read the tour and code first | Asking about login, the database or the code pattern |
| Defaults for things the user doesn't care about | Wasted questions about sort order and duplicates |
| Scenario questions ("a recipe is later deleted...") | Edge cases turning into bugs after release |
| Neutral options for the privacy question | Nudging the user on a choice that's hard to reverse |
| Reading the user's typed answer carefully | Losing the "don't lose their place" detail |
| A done check for every requirement | Arguing later about whether it works |
