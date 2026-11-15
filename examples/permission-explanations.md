# Examples: every-corner-explain

> What the user sees right before the approval prompt, at each of the four risk levels.

## Level 1: read-only, stay quiet

```
Run command: git status
```

Explanation: none needed. At most: *"Checking which files changed."*

## Level 2: easy to undo, one line

```
Edit file: src/config.json
```

> Change the port from 3000 to 4000 in `config.json` so it doesn't clash with your other app (step 2 of the spec).

Several similar edits get one line together:

> Rename `getUser` to `findUser` in 5 files: `auth.js`, `users.js`, `admin.js`, `profile.js`, `users.test.js`.

## Level 3: hard to undo, full card

```
Run command: npm run migrate
```

```
⚠️ HARD TO UNDO
What: Add a new "favorites" table to the database.
Why: Step 1 of the favorites spec you approved.
Changes: The local database file data/app.db. Nothing leaves this computer.
Undo: Run "npm run migrate:down" to remove the table. Existing data is not touched.
Check this: This is the local database, not the production one.
```

## Level 4: cannot be undone, distinct card

```
Run command: git push --force origin feature/login
```

```
⛔ CANNOT BE UNDONE
What: Replace the feature/login branch on the server with your local copy.
Why: You rewrote your commits, so a normal push is rejected.
Changes: The shared branch on the server.
Undo: Not possible. Commits that exist only on the server would be lost.
Safer option: git push --force-with-lease (refuses to overwrite work you haven't seen).
Check this: Nobody else is working on this branch.
```

## When Claude doesn't know

```
Run command: ./scripts/cleanup.sh
```

> I haven't read `cleanup.sh`, so I can't say what it deletes. Let me read it first (reading changes nothing), then I'll explain it properly.

An honest "I don't know yet" beats a confident guess.

## When the action goes beyond the request

> You asked me to fix the login bug. This step would also upgrade the `express` library, which you didn't ask for. Do you want that, or should I fix the bug without upgrading?
