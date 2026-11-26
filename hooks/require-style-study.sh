#!/usr/bin/env bash
# PreToolUse hook for Edit, Write and MultiEdit.
#
# Makes sure every-corner-matchcodebase runs before code is written in a project that
# already has code. A skill description alone did not trigger it for small requests
# (see docs/every-corner/specs/every-corner-matchcodebase.md, R1), and a hook runs every time.
#
# It blocks at most ONCE per session, and only when all of these hold:
#   - the file being written is a source file,
#   - the project already contains other source files,
#   - docs/every-corner/STYLE.md does not exist yet.
# After that one block the agent can run the skill and retry, or retry as is.
#
# Installed as a plugin, switch it off with the "Style guard hook" option.

set -euo pipefail

case "${CLAUDE_PLUGIN_OPTION_STYLEGUARD:-true}" in
  false|False|FALSE|0|no|off) exit 0 ;;
esac

# Without jq we cannot read the tool input; stay out of the way rather than error.
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
session="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null || true)"
[ -z "$session" ] && session="nosession"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

[ -z "$file" ] && exit 0

SRC_EXT='py|js|jsx|mjs|cjs|ts|tsx|go|rs|java|kt|rb|php|c|h|cpp|cc|hpp|cs|swift|sh|scala|dart|lua'
ext="${file##*.}"
[ "$ext" = "$file" ] && exit 0
printf '%s' "$ext" | grep -Eqx "$SRC_EXT" || exit 0

# Nearest existing folder of the file (the folder may not exist yet for a new file).
dir="$(dirname "$file")"
while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do dir="$(dirname "$dir")"; done
[ -d "$dir" ] || exit 0

root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$root" ]; then
  # No git: the working folder if the file is inside it, otherwise the file's own folder.
  if [ -n "$cwd" ] && [ "${file#"$cwd"/}" != "$file" ]; then root="$cwd"; else root="$dir"; fi
fi

# Style notes already exist: nothing to do.
[ -f "$root/docs/every-corner/STYLE.md" ] && exit 0

# Already blocked once in this session: never block twice.
guard="${TMPDIR:-/tmp}/every-corner-style-guard"
[ -e "$guard/$session" ] && exit 0

# Does the project already contain other source code?
has_code=""
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  has_code="$(git -C "$root" ls-files --cached --others --exclude-standard 2>/dev/null \
    | grep -E "\\.(${SRC_EXT})\$" | grep -vxF -- "${file#"$root"/}" | head -1 || true)"
else
  names=()
  for e in ${SRC_EXT//|/ }; do names+=(-o -name "*.$e"); done
  has_code="$(find "$root" -maxdepth 4 \
    \( -name node_modules -o -name .git -o -name vendor -o -name venv -o -name .venv \) -prune -o \
    -type f \( -name '*.__none__' "${names[@]}" \) ! -path "$file" -print 2>/dev/null | head -1 || true)"
fi
[ -z "$has_code" ] && exit 0

mkdir -p "$guard" 2>/dev/null && : > "$guard/$session" 2>/dev/null || true

reason="STOP before writing code: this project already contains code and has no style notes yet (docs/every-corner/STYLE.md). Run the every-corner-matchcodebase skill first so the new code matches how this project is written, then repeat this edit. This check blocks once per session; the user can turn it off with /plugin configure every-corner@every-corner-skills."

jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
