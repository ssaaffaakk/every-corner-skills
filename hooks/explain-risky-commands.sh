#!/usr/bin/env bash
# PreToolUse hook for the Bash tool.
#
# Sorts each shell command into one of four risk levels:
#   1 read-only, 2 easy to undo  -> pass through silently (no extra prompt)
#   3 hard to undo               -> ask, with a plain-English warning
#   4 cannot be undone           -> ask, with a distinct warning and a safer option
#
# Why a hook: a skill depends on the model remembering to explain. A hook runs
# every time. It only interrupts for levels 3 and 4, because warnings shown on
# every command stop being read.
#
# This is a safety net, not a security boundary: pattern matching can be evaded.

set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

[ -z "$cmd" ] && exit 0

level=0
what=""
safer=""

# Case-sensitive by default (git -d vs -D matters); SQL keywords use matchi.
match()  { printf '%s' "$cmd" | grep -Eq -- "$1"; }
matchi() { printf '%s' "$cmd" | grep -Eiq -- "$1"; }

hard()   { level=3; what="$1"; safer="${2:-}"; }
cannot() { level=4; what="$1"; safer="${2:-}"; }

# Level 4: cannot be undone
if match 'rm[[:space:]]+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r|-r[[:space:]]+-f|-f[[:space:]]+-r)'; then
  cannot "Deletes files and folders permanently. They do not go to the trash." \
         "List what would be deleted first, or move it to the trash."
elif match 'git[[:space:]]+push.*(--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$))'; then
  cannot "Replaces the branch on the server with your local copy. Commits that exist only on the server are lost." \
         "git push --force-with-lease (refuses to overwrite work you haven't seen)."
elif match 'git[[:space:]]+reset[[:space:]]+.*--hard|git[[:space:]]+reset[[:space:]]+--hard'; then
  cannot "Throws away all uncommitted changes in your working folder." \
         "git stash (keeps the changes so you can get them back)."
elif match 'git[[:space:]]+(checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)'; then
  cannot "Discards every uncommitted change in this folder." \
         "git stash (keeps the changes so you can get them back)."
elif match 'git[[:space:]]+clean[[:space:]]+-[a-z]*f'; then
  cannot "Deletes files git is not tracking. They are in no commit, so they cannot be recovered." \
         "git clean -nd first (shows what would be deleted, deletes nothing)."
elif matchi '(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[a-z_])'; then
  cannot "Permanently removes a database table or all of its data." \
         "Take a backup or export first, and make sure this is not the production database."
elif match '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh'; then
  cannot "Downloads a script from the internet and runs it immediately, without you seeing what it does." \
         "Download the script, read it, then run it."
elif match '(npm|pnpm|yarn)[[:space:]]+publish|cargo[[:space:]]+publish|twine[[:space:]]+upload' \
     && ! match '--(help|dry-run)'; then
  cannot "Publishes this package publicly. A published version cannot be taken back." \
         "Run a dry run first (for npm: npm publish --dry-run)."
elif match '(^|[[:space:];&|])(mkfs(\.[a-z0-9]+)?|dd[[:space:]].*of=/dev/)'; then
  cannot "Overwrites a whole disk or partition." \
         "Double-check the device name; there is no safe version of this."
elif match 'docker[[:space:]]+(system|volume)[[:space:]]+prune'; then
  cannot "Deletes unused Docker data. Volumes can hold database files." \
         "Run docker system df first to see what would be removed."
elif match 'kubectl[[:space:]]+delete'; then
  cannot "Deletes resources from a Kubernetes cluster." \
         "Check the current context (kubectl config current-context) and try --dry-run=client first."

# Level 3: hard to undo
elif match '(^|[[:space:];&|])sudo[[:space:]]'; then
  hard "Runs with administrator rights. It can change anything on this computer, not just this project."
elif match 'chmod[[:space:]]+(-R[[:space:]]+)?0?777'; then
  hard "Lets every user on this computer read, change and run these files." \
       "Use a narrower permission, such as chmod 755 or chmod +x."
elif match 'git[[:space:]]+branch[[:space:]]+-D'; then
  hard "Deletes a branch even if its work was never merged. Recovery needs git reflog." \
       "git branch -d (refuses if the work isn't merged)."
elif match '--no-verify'; then
  hard "Skips the project's safety checks (git hooks) for this commit or push." \
       "Run without --no-verify and fix what the checks report."
fi

[ "$level" -lt 3 ] && exit 0

if [ "$level" -eq 4 ]; then
  reason="⛔ CANNOT BE UNDONE: $what"
else
  reason="⚠️ HARD TO UNDO: $what"
fi
[ -n "$safer" ] && reason="$reason Safer option: $safer"

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
