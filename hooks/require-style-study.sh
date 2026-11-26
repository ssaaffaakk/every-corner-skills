#!/usr/bin/env bash
# PreToolUse hook for Edit, Write and MultiEdit (and Skill, see below).
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

# git, but never with configuration planted in the repository: a committed folder
# that looks like a bare repository (HEAD, objects/, refs/, config) would
# otherwise be opened by git's discovery and its core.fsmonitor command run.
g() { git -c safe.bareRepository=explicit -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"; }

# Read three fields with jq, or, without jq, a sed fallback (so the hook never
# switches itself off just because jq is missing). EVERY_CORNER_HOOK_PARSER=raw
# forces the fallback; the tests run every case with both.
json_field() { # name -> value of the first string field with that name
  if [ "${EVERY_CORNER_HOOK_PARSER:-auto}" != "raw" ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r --arg k "$1" '.. | objects | select(has($k)) | .[$k] | strings' 2>/dev/null | head -1 || true
  else
    printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
      | head -1 | sed -e 's/\\\\/@@EC_BS@@/g' -e 's/\\"/"/g' -e 's/\\\//\//g' -e 's/@@EC_BS@@/\\/g' || true
  fi
}
file="$(json_field file_path)"
# The session id names a file below, so keep only safe characters (no ../).
session="$(json_field session_id | tr -cd 'A-Za-z0-9_-')"
[ -z "$session" ] && session="nosession"
cwd="$(json_field cwd)"

# Plugin data folder when Claude Code provides one, otherwise a folder only this
# user owns. One empty file per session marks "already handled".
guard="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/every-corner-style-guard"
mark() { # -> 0 only if this session's mark now exists
  [ -e "$guard/$session" ] && return 0
  mkdir -p -m 700 "$guard" 2>/dev/null && [ -O "$guard" ] && [ ! -L "$guard" ] || return 1
  find "$guard" -type f -mtime +7 -delete 2>/dev/null || true   # old sessions
  : > "$guard/$session" 2>/dev/null && [ -f "$guard/$session" ] && [ ! -L "$guard/$session" ]
}

# The skill itself ran (the agent followed its description): mark the session,
# so the first edit afterwards is not sent back to the skill.
if [ "$(json_field tool_name)" = "Skill" ]; then
  case "$(json_field skill)" in *every-corner-matchcodebase*) mark || true ;; esac
  exit 0
fi

[ -z "$file" ] && exit 0

SRC_EXT='py|js|jsx|mjs|cjs|ts|tsx|go|rs|java|kt|rb|php|c|h|cpp|cc|hpp|cs|swift|sh|scala|dart|lua'
ext="${file##*.}"
[ "$ext" = "$file" ] && exit 0
printf '%s' "$ext" | grep -Eqx "$SRC_EXT" || exit 0

# Nearest existing folder of the file (the folder may not exist yet for a new file).
dir="$(dirname "$file")"
while [ ! -d "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do dir="$(dirname "$dir")"; done
[ -d "$dir" ] || exit 0
# Compare real paths: git reports the top folder with symlinks resolved
# (macOS /tmp is /private/tmp), Claude Code may not.
real_dir="$(cd "$dir" 2>/dev/null && pwd -P)" || exit 0
file="$real_dir${file#"$dir"}"; dir="$real_dir"
[ -n "$cwd" ] && cwd="$(cd "$cwd" 2>/dev/null && pwd -P || printf '%s' "$cwd")"

root="$(g -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"

# Only guard the project Claude is working in: a scratch script in a temp
# folder or a file in another repository is not the user's code.
if [ -n "$cwd" ] && [ "${file#"$cwd"/}" = "$file" ]; then
  cwd_root="$(g -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] && [ "$root" = "$cwd_root" ] || exit 0
fi

if [ -z "$root" ]; then
  # No git: the working folder if the file is inside it, otherwise the file's own folder.
  if [ -n "$cwd" ] && [ "${file#"$cwd"/}" != "$file" ]; then root="$cwd"; else root="$dir"; fi
fi

# Already blocked once (or the skill already ran) in this session.
[ -e "$guard/$session" ] && exit 0

# Does the project already contain other source code?
has_code=""
if g -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  has_code="$(g -C "$root" ls-files --cached --others --exclude-standard 2>/dev/null \
    | grep -E "\\.(${SRC_EXT})\$" | grep -vxF -- "${file#"$root"/}" | head -1 || true)"
else
  names=()
  for e in ${SRC_EXT//|/ }; do names+=(-o -name "*.$e"); done
  has_code="$(find "$root" -maxdepth 4 \
    \( -name node_modules -o -name .git -o -name vendor -o -name venv -o -name .venv \) -prune -o \
    -type f \( -name '*.__none__' "${names[@]}" \) ! -path "$file" -print 2>/dev/null | head -1 || true)"
fi
[ -z "$has_code" ] && exit 0

# Block only if the mark could be written: otherwise every edit of the session
# would be blocked, and never write through a planted folder or symlink.
mark || exit 0

off="This check blocks once per session; the user can turn it off with /plugin configure every-corner@every-corner-skills."
if [ -f "$root/docs/every-corner/STYLE.md" ]; then
  reason="STOP before writing code: this project has style notes in docs/every-corner/STYLE.md. Run the every-corner-matchcodebase skill first; it reuses those notes and re-checks only files changed since they were written. Then repeat this edit. $off"
else
  reason="STOP before writing code: this project already contains code and has no style notes yet (docs/every-corner/STYLE.md). Run the every-corner-matchcodebase skill first so the new code matches how this project is written, then repeat this edit. $off"
fi

# Built by hand so the output never depends on jq. The reason has no quotes or backslashes.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
