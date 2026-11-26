#!/usr/bin/env bash
# PreToolUse hook for Edit, Write and MultiEdit.
#
# Makes sure every-corner-matchcodebase runs before code is written in a project that
# already has code. A skill description alone did not trigger it for small requests
# (see docs/every-corner/specs/every-corner-matchcodebase.md, R1), and a hook runs every time.
#
# It blocks at most ONCE per session, and only when all of these hold:
#   - the file being written is a source file inside the working project,
#   - the project already contains other source files.
# Without docs/every-corner/STYLE.md the agent is sent to study the project.
# With it, the agent is sent to the same skill, which reuses STYLE.md and
# re-reads only what changed: without this nudge later sessions never read it.
# After that one block the agent can run the skill and retry, or retry as is.
#
# Installed as a plugin, switch it off with the "Style guard hook" option.

set -uo pipefail
# Byte-wise text handling: fast, and no "illegal byte sequence" on odd input.
export LC_ALL=C

case "${CLAUDE_PLUGIN_OPTION_STYLEGUARD:-true}" in
  false|False|FALSE|0|no|off) exit 0 ;;
esac

input="$(cat)"

# Read three fields with jq, or, without jq, a sed fallback (so the hook never
# switches itself off just because jq is missing). EVERY_CORNER_HOOK_PARSER=raw
# forces the fallback; the tests run every case with both.
json_field() { # name -> value of the first string field with that name
  if [ "${EVERY_CORNER_HOOK_PARSER:-auto}" != "raw" ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r --arg k "$1" '.. | objects | select(has($k)) | .[$k] | strings' 2>/dev/null | head -1 || true
  else
    printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
      | head -1 | sed -e 's/\\\//\//g' -e 's/\\\\/\\/g' || true
  fi
}
file="$(json_field file_path)"
# The session id names a file below, so keep only safe characters (no ../).
session="$(json_field session_id | tr -cd 'A-Za-z0-9_-')"
[ -z "$session" ] && session="nosession"
cwd="$(json_field cwd)"

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

# Only guard the project Claude is working in: a scratch script in a temp
# folder or a file in another repository is not the user's code.
if [ -n "$cwd" ] && [ "${file#"$cwd"/}" = "$file" ]; then
  cwd_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] && [ "$root" = "$cwd_root" ] || exit 0
fi

if [ -z "$root" ]; then
  # No git: the working folder if the file is inside it, otherwise the file's own folder.
  if [ -n "$cwd" ] && [ "${file#"$cwd"/}" != "$file" ]; then root="$cwd"; else root="$dir"; fi
fi

# Already blocked once in this session: never block twice.
# The plugin's private data folder when Claude Code provides one; otherwise a
# folder only this user can write to.
guard="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/every-corner-style-guard"
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

# Never write through a folder or file someone else planted (shared /tmp).
if mkdir -p -m 700 "$guard" 2>/dev/null && [ -O "$guard" ] && [ ! -L "$guard" ] && [ ! -L "$guard/$session" ]; then
  : > "$guard/$session" 2>/dev/null || true
fi

off="This check blocks once per session; the user can turn it off with /plugin configure every-corner@every-corner-skills."
if [ -f "$root/docs/every-corner/STYLE.md" ]; then
  reason="STOP before writing code: this project has style notes in docs/every-corner/STYLE.md. Run the every-corner-matchcodebase skill first; it reuses those notes and re-checks only files changed since they were written. Then repeat this edit. $off"
else
  reason="STOP before writing code: this project already contains code and has no style notes yet (docs/every-corner/STYLE.md). Run the every-corner-matchcodebase skill first so the new code matches how this project is written, then repeat this edit. $off"
fi

# Built by hand so the output never depends on jq. The reason has no quotes or backslashes.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
