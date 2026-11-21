# Example: every-corner-interview for a new project

> Illustrative conversation for a habit tracker starting in an empty folder.

**The user says** *“Build me a habit tracker app.”*

## 1. Agree on the sub-rooms and their order

> **Claude:** This is a **new project (T4)**. I'd tackle it in this order:
>
> 1. Daily habits and check-ins
> 2. Accounts and syncing
> 3. Reminders
> 4. Deployment
>
> Does this split and order work for you?
>
> **User:** Yes, start with daily habits. Put reminders before accounts so we can decide what reminders need before we talk about syncing.

Claude records the agreed order: daily habits and check-ins → reminders → accounts and syncing → deployment. Only the first sub-room is interviewed below.

## 2. Start a draft for daily habits

The folder is empty, so there is no existing code or tour to consult. Before asking about daily habits, Claude drafts `docs/every-corner/specs/daily-habits.md` with **Draft** status. How to store the list is **Defaulted** to local storage for this sub-room so the daily flow can be checked on one device. The user-facing choices start **Open**.

## 3. Ask about daily habits

**Screen 1 — Purpose and scope**

> **Q1. Who is this for, and what should they be able to do on a normal day?**
>
> **Q2. What belongs in the first version of check-ins?**
> - Add habits and check off today's list (Recommended). This gets the daily routine working first.
> - Add habits, check them off, and see streaks and past days. This also needs a history view.

**User:** “It's for me. I want to open it, see what I planned for today, and check things off. Start with the first option.”

Claude records personal daily use and moves streaks and history out of scope before asking about today's list.

**Screen 2 — Today's list**

> **Q3. What should happen when a new day starts?**
> - Start a fresh checklist at midnight on the device (Recommended). The list is ready each morning.
> - Start a fresh checklist at 4 a.m. on the device. Late-night check-ins still count toward the previous day.
>
> **Q4. When you add a habit, how often should it appear?**
> - Every day (Recommended). Each habit appears without setting a schedule.
> - Only on the weekdays you choose. You can keep weekend habits off the weekday list.
>
> **Q5. What should you see before you add your first habit?**
> - A short message with an “Add habit” button (Recommended). You can start with one click.
> - A few sample habits you can add. You get ideas to start from.
>
> **Q6. Can you change the list after adding habits?**
> - Keep it add-only for the first version (Recommended). You can try check-ins before we add list management.
> - Let you rename and pause habits. You can adjust the list as your routine changes.

**User:** “Midnight, every day, and the button. Add-only is fine for the first version.”

Claude updates the spec with the day boundary, recurrence, empty state and add-only scope.

**Screen 3 — Mistakes, names and saving**

> **Q7. You tap a checkmark by mistake. What should happen?**
> - Tap it again to undo today's check-in (Recommended). A mistaken tap is easy to fix.
> - Use an Undo button shown after the check-in. The checkmark itself stays a one-way action.
>
> **Q8. “Walk” is already on the list. What should happen if you add “ walk ” or enter only spaces?**
> - Treat “ walk ” as the same name and explain why it can't be added. Ask for a name if the field is blank (Recommended). This keeps the checklist easy to read.
> - Allow “ walk ” as another habit and ask for a name if the field is blank. You can keep two habits with the same name.
>
> **Q9. If a change can't be saved on this device, what should you see?**
> - Keep the last saved list and show a message with a retry button (Recommended). You can see which changes stuck.
> - Keep the change visible with an “Unsaved” label and a retry button. The label stays until the change saves.

>
> **Q10. How should today's checklist be ordered?**
> - Keep the order you added habits (Recommended). A habit stays in the same spot as you check it off.
> - Sort by name. You can find a habit alphabetically.

**User:** “Tap again, and treat those names as the same even if the capitals differ. If saving fails, keep the saved list and let me retry. Keep the order I added habits.”

Claude records the answers and the extra detail about capitalization. The ledger now covers what appears, what is stored, the day boundary, ordering, duplicate and blank names, undo, and failed saves. For this local flow there is no network loading state. Every requirement for this sub-room has a done check.

## 4. Ask for approval

> **Goal** — Give you a daily checklist of habits you can add and check off.
>
> **Your decisions** — Keep an add-only list of daily habits in the order you added them. Reset checkmarks at device-local midnight. Show an “Add habit” button on an empty list. Tap a checkmark again to undo. Reject duplicate or blank names and offer a retry if a change fails to save.
>
> **Decisions I made for you** — Keep the list on this device for now. A browser data reset could clear the list.
>
> **Out of scope** — Editing and pausing habits, streaks, history, and the other three sub-rooms.
>
> **Spec** — `docs/every-corner/specs/daily-habits.md`
>
> Build it?

Claude waits for an explicit yes. The spec stays **Draft**. After approval, Claude can mark it **Agreed** and recommend a fresh session for building this sub-room from its spec.

## The daily habits spec (excerpt)

```markdown
# Daily habits and check-ins

Tier: T4 · Status: Draft · Last updated: 2026-11-15 · Commit: N/A (empty project)

## Goal
Give one person a daily checklist of habits they can add and check off.

## Non-goals
Editing or pausing habits, custom schedules, history, streaks, reminders,
accounts and syncing, and deployment.

## Requirements
| ID | Requirement | Done check |
|---|---|---|
| R1 | While there are no habits, the app shall show an empty message and an “Add habit” button. | Open with an empty list and use the button to open the add form. |
| R2 | When a habit with a valid new name is added, the app shall append it to the daily list and save it on the device. | Add “Walk” then “Read”, reopen the app, and check both names and their order. |
| R3 | If a trimmed name is blank or matches an existing name without regard to case, the app shall explain the problem and leave the list unchanged. | Add “Walk”, then try “ walk ” and a spaces-only name. Check the message and list after each try. |
| R4 | When the user taps a habit's checkmark, the app shall toggle and save that habit's completion for today. | Tap once, reload and check that it is done. Tap again, reload and check that it is open. |
| R5 | When the device's local date changes, the app shall keep the habits and show all of them unchecked for the new day. | Leave the app open past local midnight with “Walk” checked. Check that “Walk” remains on the list and is unchecked, then reload and check again. |
| R6 | If a change fails to save, the app shall retain the last saved list and offer to retry the change. | Force a save failure while adding a habit and while checking one off. Each time, verify no change appears as saved, then retry after restoring storage and verify it saves once. |

## Decisions made for you
- Store data on the device so this daily flow can be tested before syncing is designed.

## Coverage ledger
| Aspect | Status | Source |
|---|---|---|
| Purpose and scope | Answered | Q1, Q2, Q6 |
| Day boundary and recurrence | Answered | Q3, Q4 |
| Empty list | Answered | Q5 |
| Undo | Answered | Q7 |
| Blank names and duplicates | Answered | Q8 |
| Save failure | Answered | Q9 |
| Ordering | Answered | Q10 |
| Storage | Defaulted | See decisions above |
| Network loading, syncing and multi-user access | N/A | Local daily habits sub-room |
| Done checks | Defaulted | Proposed alongside R1–R6 for confirmation |

## Clarifications log
- Q8 inferred from “treat those names as the same even if the capitals differ”: trim names and compare them without regard to case.
```

## Why this works

| Choice | What it prevented |
|---|---|
| Agree on sub-rooms and their order first | Deciding how to sync before knowing what reminders need |
| Set the scope before asking about check-ins | Designing history and streaks for a daily checklist |
| Ask about midnight, duplicate names and failed saves | Leaving common cases for the builder to guess |
| Write a separate draft with checks and wait for approval | Starting the build before the user confirms how this part should work |
