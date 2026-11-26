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
# When the skill itself runs, the session is marked and nothing is blocked.
#
# Installed as a plugin, switch it off with the "Style guard hook" option.

set -uo pipefail
# Byte-wise text handling: fast, and no "illegal byte sequence" on odd input.
export LC_ALL=C

case "${CLAUDE_PLUGIN_OPTION_STYLEGUARD:-true}" in
  false|False|FALSE|0|no|off) exit 0 ;;
esac

input="$(cat)"

# Read the fields with jq (one call), or, without jq, a sed fallback per field, so
# the hook never switches itself off just because jq is missing (the same idea as
# explain-risky-commands.sh; keep the two in sync). EVERY_CORNER_HOOK_PARSER=raw
# forces the fallback; the tests run every case with both.
US=$'\037'   # field separator that cannot appear in a path
if [ "${EVERY_CORNER_HOOK_PARSER:-auto}" != "raw" ] && command -v jq >/dev/null 2>&1; then
  fields="$(printf '%s' "$input" | jq -r --arg us "$US" \
    '[.tool_name, .session_id, .cwd, .tool_input.file_path, .tool_input.skill]
     | map(if type == "string" then . else "" end) | join($us)' 2>/dev/null | head -1)"
else
  raw_field() { # name -> value of that string field (the hook input is one JSON line)
    printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -1 \
      | sed -e 's/\\\\/@@EC_BS@@/g' -e 's/\\"/"/g' -e 's/\\\//\//g' -e 's/@@EC_BS@@/\\/g'
  }
  fields="$(raw_field tool_name)$US$(raw_field session_id)$US$(raw_field cwd)$US$(raw_field file_path)$US$(raw_field skill)"
fi
IFS="$US" read -r tool session cwd file skill <<< "$fields"
session="$(printf '%s' "$session" | tr -cd 'A-Za-z0-9_-')"   # names a file below: no ../
[ -n "$session" ] || session="nosession"

# (No session id at all shares one mark, "nosession": harmless, Claude Code always sends one.)
# One empty file per session marks "already handled", in the plugin's data folder
# when Claude Code provides one, otherwise in a folder only this user owns.
guard="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/every-corner-style-guard"
mark() { # -> 0 only if this session's mark now exists
  [ -d "$guard" ] || { mkdir -p "${guard%/*}" && mkdir -m 700 "$guard"; } 2>/dev/null
  [ -d "$guard" ] && [ -O "$guard" ] && [ ! -L "$guard" ] || return 1
  find "$guard" -type f -mtime +7 -delete 2>/dev/null   # old sessions
  : > "$guard/$session" 2>/dev/null
}

# The skill itself ran (the agent followed its description): mark the session,
# so the first edit afterwards is not sent back to it.
if [ "$tool" = "Skill" ]; then
  case "$skill" in *every-corner-matchcodebase*) mark ;; esac
  exit 0
fi

# Cheap checks first: a source file, a session not handled yet, a working folder.
# Keep the extensions in sync with LANGS in skills/every-corner-matchcodebase/scripts/style-counts.py.
shopt -s nocasematch   # A.PY counts too (the script lower-cases extensions)
case "${file##*.}" in
  py|js|jsx|mjs|cjs|ts|tsx|go|rs|java|kt|rb|php|c|h|cpp|cc|hpp|cs|swift|sh|scala|dart|lua) ;;
  *) exit 0 ;;
esac
shopt -u nocasematch
case "$file" in /*) ;; *) exit 0 ;; esac   # Claude Code sends absolute paths
case "$file" in */../*|*/..) exit 0 ;; esac   # not normalised: cannot tell where it points
[ -e "$guard/$session" ] && exit 0
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

# git, but never with configuration planted in the repository: a committed folder
# that looks like a bare repository (HEAD, objects/, refs/, config) would otherwise
# be opened by git's discovery and its core.fsmonitor command run. (Git older than
# 2.38 ignores safe.bareRepository; core.fsmonitor=false still stops the command.)
# core.quotePath=false: file names with non-ASCII characters come out as they are.
g() { git -c safe.bareRepository=explicit -c core.fsmonitor=false -c core.quotePath=false "$@"; }

# The project is the working folder's repository, or the working folder itself.
# Real paths on both sides: git reports them with symlinks resolved (macOS /tmp is
# /private/tmp), Claude Code may not.
cwd="$(cd "$cwd" && pwd -P)" || exit 0
root="$(g -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
in_git=1; [ -n "$root" ] || { root="$cwd"; in_git=0; }

# The file's nearest existing folder (a new file may sit in a folder not created yet).
dir="${file%/*}"
while [ -n "$dir" ] && [ ! -d "$dir" ]; do dir="${dir%/*}"; done
[ -n "$dir" ] || dir="/"
real_dir="$(cd "$dir" && pwd -P)" || exit 0
file="$real_dir${file#"$dir"}"

# The edited file may belong to a repository of its own below the working project: a
# parent folder holding several projects, or a nested repository. Judge it by that one.
sub="$(g -C "$real_dir" rev-parse --show-toplevel 2>/dev/null)"
case "$sub" in "$root"/*) root="$sub"; in_git=1 ;; esac

# Only guard the project Claude is working in: a scratch script in a temp folder
# or a file in another repository is not the user's code.
case "$file" in "$root"/*) ;; *) exit 0 ;; esac

# Does the project already contain other source code?
# Vendored and build folders do not count (keep in sync with SKIP_DIRS in style-counts.py).
src_re='\.(py|js|jsx|mjs|cjs|ts|tsx|go|rs|java|kt|rb|php|c|h|cpp|cc|hpp|cs|swift|sh|scala|dart|lua)$'
skip_re='(^|/)(\.git|node_modules|vendor|third_party|dist|build|out|target|__pycache__|\.venv|venv|\.tox|\.next|\.nuxt|coverage|\.idea|\.gradle|Pods|bin|obj|site-packages|\.mypy_cache|\.pytest_cache)/'
rel="${file#"$root"/}"
if [ "$in_git" = 1 ]; then
  list="$(g -C "$root" ls-files --cached --others --exclude-standard 2>/dev/null)"
else
  list="$(cd "$root" && find . -maxdepth 5 \( -name node_modules -o -name .git -o -name vendor \) -prune -o -type f -print 2>/dev/null | head -50000 | sed 's#^\./##')"
fi
# Generated, minified and lock files do not count either (keep in sync with SKIP_NAME in the script).
gen_re='(\.min\.|\.lock$|-lock\.|package-lock|\.generated\.|_pb2|\.pb\.go$|\.d\.ts$|\.snap$)'
has_code="$(printf '%s\n' "$list" | grep -iE "$src_re" | grep -vxF -- "$rel" | grep -vE "$skip_re" | grep -vE "$gen_re" | head -1)"
[ -n "$has_code" ] || exit 0

# Block only if the mark could be written; otherwise every edit of the session
# would be blocked.
mark || exit 0

off="This check blocks once per session; the user can turn it off with /plugin configure every-corner@every-corner-skills."
if [ -f "$root/docs/every-corner/STYLE.md" ]; then
  reason="STOP before writing code: this project has style notes in docs/every-corner/STYLE.md. Run the every-corner-matchcodebase skill first; it reuses those notes and re-checks only files changed since they were written. Then repeat this edit. $off"
else
  reason="STOP before writing code: this project already contains code and has no style notes yet (docs/every-corner/STYLE.md). Run the every-corner-matchcodebase skill first so the new code matches how this project is written, then repeat this edit. $off"
fi

# Built by hand so the output never depends on jq. The reason has no quotes or backslashes.
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
