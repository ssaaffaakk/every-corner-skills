# Examples: permission explanations

> What the human sees right above the approval prompt, before and after using `explain-before-approve`.

## 1. Deleting a folder

**Before** (what a junior sees):

```
Run command: rm -rf node_modules package-lock.json
[ Accept ]  [ Reject ]
```

**After:**

> **What:** Delete the downloaded libraries folder and the lock file, then re-install them.
> **Why:** The install is stuck on a version conflict; a clean re-install usually fixes it (step 2 of the plan).
> **Changes:** Only `node_modules/` and `package-lock.json` in this project. Nothing leaves your computer.
> **Undo:** Easy to undo: `npm install` re-creates both. The lock file may pick slightly newer versions.
> **Check this:** The command is run from the project folder, not your home folder.

---

## 2. Installing a package

**Before:**

```
Run command: npm install zod
```

**After:**

> **What:** Download a validation library called `zod` and add it to the project.
> **Why:** The plan needs to check that the sign-up form data is valid before saving it (step 3).
> **Changes:** Adds a line to `package.json`, updates the lock file, downloads code into `node_modules/`.
> **Undo:** Easy: `npm uninstall zod`.
> **Check this:** `zod` is a widely used library, and the name is spelled exactly like that (typo-squatted look-alike packages exist).

---

## 3. A force push (the dangerous one)

**Before:**

```
Run command: git push --force origin feature/login
```

**After:**

> **What:** Replace the `feature/login` branch on the server with the version on your computer.
> **Why:** You rewrote local history while cleaning up commits, so the server will reject a normal push.
> **Changes:** The shared branch on the server. Anyone else who has pushed to it will have their commits removed from it.
> **Undo:** Hard to undo; commits that exist only on the server are lost.
> **Check this:** Nobody else is working on this branch. If unsure, I can use `--force-with-lease`, which refuses to overwrite work you have not seen.

---

## 4. A read-only command (stay quiet)

```
Run command: git status
```

Explanation: *none needed.* One line at most: "Checking which files have changed."

---

## 5. When the model is not sure

> **What:** Run the `cleanup.sh` script in the repo.
> **Why:** The README says to run it before building.
> **Changes:** *I haven't read the script, so I can't say what it deletes.*
> **Undo:** Unknown.
> **Instead:** Let me read the script first and then ask again. (Reading it changes nothing.)

This case matters most. An honest "I don't know yet" beats a confident guess.
