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
# How it works: the patterns search the WHOLE command text, heredoc bodies
# included, so a dangerous command is found wherever it sits: after `VAR=x`,
# inside `if`/`for`, `( )`, `$( )`, `bash -c`, `ssh host '...'`, or a heredoc.
# Missing a dangerous command is worse than one extra warning, so text that
# merely mentions one (an `echo`, a commit message, a file written with `cat`)
# can also trigger a warning. The few exceptions (`--cached`, `--dry-run`,
# `git clean -n`, `git branch -d`) are checked within the same command segment,
# after splitting the text at ; & | ( ) ` < > and newlines. Matching uses grep,
# which is linear on macOS and Linux, so large commands stay far below the
# hook's timeout.
#
# This is a safety net, not a security boundary: pattern matching can be evaded.
# In a headless `claude -p` run nobody can answer the "ask", so Claude Code
# denies the command; switch the hook off for unattended runs if that matters.

set -euo pipefail
# Byte-wise text handling: fast, and no "illegal byte sequence" on odd input.
export LC_ALL=C

# Installed as a plugin, the user can switch this off with the "Safety-net hook"
# option. Unset (manual install) means on. Any settings file that sets
# environment variables for a session (including a project's
# .claude/settings.json) can set this variable too.
case "${CLAUDE_PLUGIN_OPTION_SAFETYNET:-true}" in
  false|False|FALSE|0|no|off) exit 0 ;;
esac

input="$(cat)"

# Read .tool_input.command with jq, or, without jq, a sed fallback that undoes
# the JSON escapes (\\ \" \n \t \r) in linear time. (No python3: it would import
# modules from the project folder.) EVERY_CORNER_HOOK_PARSER=raw forces the
# fallback for the tests; any other value is ignored.
nl=$'\n'
raw_parse() {
  printf '%s' "$input" | tr '\n' ' ' \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | sed -e 's/\\\\/@@EC_BS@@/g' -e 's/\\"/"/g' -e 's/\\[tr]/ /g' \
          -e "s/\\\\n/\\${nl}/g" -e 's/@@EC_BS@@/\\/g'
}
cmd=""
if [ "${EVERY_CORNER_HOOK_PARSER:-auto}" != "raw" ] && command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || cmd=""
fi
if [ -z "$cmd" ]; then
  cmd="$(raw_parse)" || cmd=""
  [ -z "$cmd" ] && cmd="$input"
fi
[ -z "$cmd" ] && exit 0

# SQL can sit inside a heredoc fed to psql; check the untouched command.
re_sql='(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[a-z_])'
sql=0
grep -qiE -- "$re_sql" <<< "$(tr '\n' ' ' <<< "$cmd")" && sql=1

# Normalize, each step a single linear pass:
#  awk: join backslash-newline continuations.
#  sed: remove quotes and fd duplications such as 2>&1; mark `git rm` and
#       `npm rm` so the plain-rm rule does not see them, but only where git/npm
#       is the command word (so `sudo -u git rm -rf` stays a plain rm, and
#       `git -c alias.x='!rm -rf build'` keeps its rm).
C='(^|[;&|(`{][[:blank:]]*|[[:blank:]](sudo|env|command|time|nohup|then|do|else|xargs)[[:blank:]]+)'   # git/npm as the command word

text="$(printf '%s\n' "$cmd" \
  | tr '\r' ' ' \
  | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' \
  | sed -E \
      -e "s/[\"']//g" \
      -e 's/[0-9]*[<>]&[0-9-]*//g' \
      -e "s#${C}git(([[:blank:]]+((-C|-c|--git-dir|--work-tree|--namespace)[[:blank:]]+[^[:blank:];&|<>!]+|--?[a-zA-Z][a-zA-Z-]*(=[^[:blank:];&|<>!]+)?))*)[[:blank:]]+rm([[:blank:];&|)<>]|\$)#\\1git_rm\\8#g" \
      -e "s#${C}(npm|pnpm|yarn)([[:blank:]]+)rm([[:blank:];&|)<>]|\$)#\\1\\3_rm\\5#g")" || text="$cmd"

# One command segment per line, for the rules that have an exception.
segs="$(printf '%s\n' "$text" | tr ';&|()`<>' '\n\n\n\n\n\n\n\n')" || segs="$text"

level=0
what=""
safer=""

# Keep the most serious finding.
raise() {
  if [ "$1" -gt "$level" ]; then level="$1"; what="$2"; safer="${3:-}"; fi
}

# Building blocks. B: start of a command word. A: further arguments on the same
# line and segment. E: end of a word.
B='(^|[^[:alnum:]_.-])'
A='([[:blank:]]+[^;&|<>[:space:]]+)*[[:blank:]]+'
E='([[:space:];&|)`<>]|$)'

# grep, not bash's =~: glibc's regex (bash and GNU sed on Linux) is quadratic
# for these patterns on long lines; grep's matcher is linear. A here-string, not
# a pipe, so an early match cannot turn into a SIGPIPE failure under pipefail.
has() { grep -Eq -- "$1" <<< "$text"; }

# Which keywords occur at all? Rules whose keyword is missing are skipped, so a
# normal command costs one grep instead of twenty.
kw=" $( { grep -oE 'rm|git|curl|wget|publish|upload|mkfs|dd|docker|kubectl|sudo|doas|chmod|no-verify' <<< "$text" || true; } | sort -u | tr '\n' ' ')"
need() { case "$kw" in *" $1 "*) return 0 ;; esac; return 1; }

# Is there a segment that matches $1 and $2 but not $3? (grep: one line = one segment)
seg_has() {
  local out
  if [ -n "${3:-}" ]; then
    out="$(printf '%s\n' "$segs" | grep -E -- "$1" | grep -E -- "$2" | grep -vE -- "$3")" || true
  else
    out="$(printf '%s\n' "$segs" | grep -E -- "$1" | grep -E -- "$2")" || true
  fi
  [ -n "$out" ]
}
short() { printf '%s' "[[:blank:]]-[a-zA-Z]*$1[a-zA-Z]*([[:blank:]]|\$)"; }
long()  { printf '%s' "[[:blank:]]--$1(=|[[:blank:]]|\$)"; }
# A flag that appears AFTER the command word $1 (so `xargs -n 1 git clean -fd`
# does not count the -n of xargs).
after() { printf '%s' "$1([[:blank:]]+[^#[:blank:]][^[:blank:]]*)*($2)"; }   # stops at a # comment

# Level 4: cannot be undone
if need rm && has "${B}rm${A}(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)${E}"; then
  raise 4 "Deletes folders and everything in them permanently. They do not go to the trash." \
          "List what would be deleted first, or move it to the trash."
fi
if need git && has "${B}git${A}push${A}(-[a-zA-Z]*f[a-zA-Z]*|--force|\\+[^[:space:]]+)${E}"; then
  raise 4 "Replaces the branch on the server with your local copy. Commits that exist only on the server are lost." \
          "git push --force-with-lease (refuses to overwrite work you haven't seen)."
fi
if need git && has "${B}git${A}push${A}(-d|--delete|:[^[:space:]]+)${E}"; then
  raise 4 "Deletes a branch or tag on the server, for everyone. Commits that exist only there are lost." \
          "Make sure nobody still uses it, or keep a backup tag of it first."
fi
if need git && has "${B}git${A}reset${A}--hard${E}"; then
  raise 4 "Throws away all uncommitted changes in your working folder." \
          "git stash (keeps the changes so you can get them back)."
fi
if need git && has "${B}git${A}(checkout|restore)([[:blank:]]+--)?[[:blank:]]+\\.${E}"; then
  raise 4 "Discards every uncommitted change in this folder." \
          "git stash (keeps the changes so you can get them back)."
fi
GCLEAN="${B}git${A}clean"
if need git && has "${GCLEAN}${E}" \
   && seg_has "${GCLEAN}([[:blank:]]|\$)" "$(after "$GCLEAN" "$(short f)|$(long force)")" \
              "$(after "$GCLEAN" "$(short n)|$(long dry-run)")"; then
  raise 4 "Deletes files git is not tracking. They are in no commit, so they cannot be recovered." \
          "git clean -nd first (shows what would be deleted, deletes nothing)."
fi
if [ "$sql" = 1 ]; then
  raise 4 "Permanently removes a database table or all of its data." \
          "Take a backup or export first, and make sure this is not the production database."
fi
if { need curl || need wget; } && { grep -Eq -- "(curl|wget)[^|]*\\|[[:blank:]]*(sudo([[:blank:]]+-[^[:blank:]]+)*[[:blank:]]+)?(ba|z|da)?sh${E}" <<< "$(tr '\n' ' ' <<< "$text")" \
   || has "${B}(ba|z|da)?sh[[:blank:]]+[<]?[[:blank:]]*[(\$]*[[:blank:]]*(curl|wget)${E}"; }; then
  raise 4 "Downloads a script from the internet and runs it immediately, without you seeing what it does." \
          "Download the script, read it, then run it."
fi
PUB="${B}(npm|pnpm|yarn|cargo|twine)"
if { need publish || need upload; } && has "(publish|upload)${E}" \
   && seg_has "${B}((npm|pnpm|yarn|cargo)([[:blank:]]+[^[:blank:]]+)*[[:blank:]]+publish|twine[[:blank:]]+upload)([[:blank:]]|\$)" \
              "." "$(after "$PUB" "[[:blank:]]--dry-run(=true)?([[:blank:]]|\$)|$(long help)|$(short h)")"; then
  raise 4 "Publishes this package publicly. A published version cannot be taken back." \
          "Run a dry run first (for npm: npm publish --dry-run)."
fi
if { need mkfs || need dd; } && has "${B}(mkfs(\\.[a-z0-9]+)?${E}|dd[[:blank:]][^;&|]*of=/dev/)"; then
  raise 4 "Overwrites a whole disk or partition." \
          "Double-check the device name; there is no safe version of this."
fi
if need docker && has "${B}docker[[:blank:]]+(system|volume)[[:blank:]]+prune${E}"; then
  raise 4 "Deletes unused Docker data. Volumes can hold database files." \
          "Run docker system df first to see what would be removed."
fi
if need kubectl && has "(^|[^[:alnum:]_-])kubectl${A}delete${E}"; then
  raise 4 "Deletes resources from a Kubernetes cluster." \
          "Check the current context (kubectl config current-context) and try --dry-run=client first."
fi

# Level 3: hard to undo
if need git && has "${B}git_rm${E}" \
   && seg_has "${B}git_rm([[:blank:]]|\$)" "$(after "${B}git_rm" "$(short f)|$(long force)")" \
              "$(after "${B}git_rm" "$(long cached)")"; then
  raise 3 "Removes files from git and from disk, even if they have changes you haven't committed. The last committed version can be restored; uncommitted edits in them are lost." \
          "Commit or stash first, or use git rm --cached to keep the files on disk."
fi
GBRANCH="${B}git${A}branch"
if need git && has "${GBRANCH}${E}" \
   && { seg_has "${GBRANCH}([[:blank:]]|\$)" "$(after "$GBRANCH" "$(short D)")" \
        || { seg_has "${GBRANCH}([[:blank:]]|\$)" "$(after "$GBRANCH" "$(short d)|$(long delete)")" \
             && seg_has "${GBRANCH}([[:blank:]]|\$)" "$(after "$GBRANCH" "$(short f)|$(long force)")"; }; }; then
  raise 3 "Deletes a branch even if its work was never merged. Recovery needs git reflog." \
          "git branch -d (refuses if the work isn't merged)."
fi
if { need sudo || need doas; } && has "${B}(sudo|doas)${E}"; then
  raise 3 "Runs with administrator rights. It can change anything on this computer, not just this project."
fi
if need chmod && has "${B}chmod${A}[0-7]?777${E}"; then
  raise 3 "Lets every user on this computer read, change and run these files." \
          "Use a narrower permission, such as chmod 755 or chmod +x."
fi
if need no-verify && has "${B}git${E}" && has "[[:space:]]--no-verify${E}"; then
  raise 3 "Skips the project's safety checks (git hooks) for this commit or push." \
          "Run without --no-verify and fix what the checks report."
fi

[ "$level" -lt 3 ] && exit 0

if [ "$level" -eq 4 ]; then
  reason="⛔ CANNOT BE UNDONE: $what"
else
  reason="⚠️ HARD TO UNDO: $what"
fi
[ -n "$safer" ] && reason="$reason Safer option: $safer"

# Build the JSON by hand so the output never depends on jq. The reason is always
# one of the fixed strings above; escape \ and " anyway.
escaped="${reason//\\/\\\\}"
escaped="${escaped//\"/\\\"}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$escaped"
