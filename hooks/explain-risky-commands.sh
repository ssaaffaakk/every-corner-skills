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
# In a headless `claude -p` run nobody can answer the "ask", so Claude Code
# denies the command; switch the hook off for unattended runs if that matters.

set -euo pipefail

# Installed as a plugin, the user can switch this off with the "Safety-net hook"
# option. Unset (manual install) means on.
case "${CLAUDE_PLUGIN_OPTION_SAFETYNET:-true}" in
  false|False|FALSE|0|no|off) exit 0 ;;
esac

input="$(cat)"

# Read .tool_input.command with jq, or python3, or (with neither) fall back to
# the raw JSON: the patterns below only need to appear somewhere in the input.
# EVERY_CORNER_HOOK_PARSER forces one parser; the tests use it.
parser="${EVERY_CORNER_HOOK_PARSER:-auto}"
if [ "$parser" = "auto" ]; then
  if command -v jq >/dev/null 2>&1; then parser=jq
  elif command -v python3 >/dev/null 2>&1; then parser=python3
  else parser=raw
  fi
fi
case "$parser" in
  jq)      cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')" ;;
  python3) cmd="$(printf '%s' "$input" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", "") or "")
except Exception:
    pass')" ;;
  *)       # No JSON parser: pull the "command" string out with sed and unescape
           # \" and \\. If that fails, scan the raw input as a last resort.
           cmd="$(printf '%s' "$input" | tr '\n' ' ' \
             | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
             | sed -e 's/\\"/"/g' -e 's/\\\\/\\/g')"
           [ -z "$cmd" ] && cmd="$input" ;;
esac

[ -z "$cmd" ] && exit 0

level=0
what=""
safer=""

# Case-sensitive by default (git -d vs -D matters); SQL keywords use matchi.
match()  { printf '%s' "$cmd" | grep -Eq -- "$1"; }
matchi() { printf '%s' "$cmd" | grep -Eiq -- "$1"; }

hard()   { level=3; what="$1"; safer="${2:-}"; }
cannot() { level=4; what="$1"; safer="${2:-}"; }

# A plain `rm` that deletes recursively: -r, -R, -rf, -Rf, -fr, --recursive, in
# any order. `git rm` is excluded here (git can restore tracked files) and is
# handled at level 3 below.
recursive_rm() {
  printf '%s' "$cmd" \
    | sed -E 's/git[[:space:]]+rm([[:space:]]|$)/git_rm\1/g' \
    | grep -oE '(^|[^[:alnum:]_.-])rm[[:space:]][^;&|]*' \
    | grep -Eq -- '[[:space:]](-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)'
}

# Level 4: cannot be undone
if recursive_rm; then
  cannot "Deletes folders and everything in them permanently. They do not go to the trash." \
         "List what would be deleted first, or move it to the trash."
elif match 'git[[:space:]]+push[^;&|]*([[:space:]]--force([[:space:]]|$)|[[:space:]]-f([[:space:]]|$)|[[:space:]]\+[^[:space:];&|])'; then
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
elif match 'git[[:space:]]+rm([[:space:]][^;&|]*)?[[:space:]](-[a-zA-Z]*f[a-zA-Z]*|--force)([[:space:]]|$)'; then
  hard "Removes files from git and from disk, even if they have changes you haven't committed. The last committed version can be restored; uncommitted edits in them are lost." \
       "Commit or stash first, or use git rm --cached to keep the files on disk."
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

# Build the JSON by hand so the output never depends on jq.
escaped="$(printf '%s' "$reason" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$escaped"
