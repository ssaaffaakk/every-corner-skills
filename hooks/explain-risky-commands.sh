#!/usr/bin/env bash
# PreToolUse hook for the Bash tool.
# If a command matches a known risky pattern, ask for confirmation and attach a
# plain-language warning to the permission prompt. Everything else passes through.
#
# Why a hook: a skill depends on the model remembering to explain. A hook runs
# every time, so the highest-risk commands always get a human-readable warning.

set -euo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"

[ -z "$cmd" ] && exit 0

reason=""

match() { printf '%s' "$cmd" | grep -Eq -- "$1"; }

if match 'rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)'; then
  reason="Deletes files and folders permanently, with no trash and no undo. Check that the path is inside your project."
elif match 'git[[:space:]]+push.*(--force|-f([[:space:]]|$))'; then
  reason="Overwrites the branch on the server with your local version. Teammates' work can be lost. Cannot be undone."
elif match 'git[[:space:]]+reset[[:space:]]+--hard'; then
  reason="Throws away all uncommitted changes in your working folder. Cannot be undone."
elif match 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*f'; then
  reason="Deletes files that git does not track yet. They are not in any commit, so they cannot be recovered."
elif match '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh'; then
  reason="Downloads a script from the internet and runs it immediately, without you seeing what it does first."
elif match '(^|[[:space:];&|])sudo[[:space:]]'; then
  reason="Runs with administrator rights. It can change anything on this computer, not just this project."
elif match '(DROP[[:space:]]+(TABLE|DATABASE)|TRUNCATE[[:space:]]+TABLE)'; then
  reason="Permanently removes a database table or its data. Check that this is not the production database."
elif match 'chmod[[:space:]]+(-R[[:space:]]+)?777'; then
  reason="Lets every user on this computer read, change and run these files. Usually not what you want."
fi

[ -z "$reason" ] && exit 0

jq -n --arg r "Plain-language warning: $reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
