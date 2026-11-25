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
# How it works: the patterns search the WHOLE command text, so a dangerous
# command is found wherever it sits: after `VAR=x`, inside `if`/`for`, `( )`,
# `$( )`, `bash -c`, `ssh host '...'`, or a heredoc fed to a shell. Missing a
# dangerous command is worse than one extra warning, so text that merely
# mentions one (an `echo`, a commit message) can also trigger a warning. Two
# things are cleaned up first: heredoc bodies that `cat`/`tee` write to a file,
# and quotes. Exclusions such as `--cached` or `--dry-run` are checked within
# the same command segment only.
#
# This is a safety net, not a security boundary: pattern matching can be evaded.
# In a headless `claude -p` run nobody can answer the "ask", so Claude Code
# denies the command; switch the hook off for unattended runs if that matters.

set -euo pipefail

# Installed as a plugin, the user can switch this off with the "Safety-net hook"
# option. Unset (manual install) means on. Any settings file that sets
# environment variables for a session (including a project's
# .claude/settings.json) can set this variable too.
case "${CLAUDE_PLUGIN_OPTION_SAFETYNET:-true}" in
  false|False|FALSE|0|no|off) exit 0 ;;
esac

input="$(cat)"
nl=$'\n'

# Read .tool_input.command with jq, or, without jq, a sed + awk fallback that
# undoes the JSON escapes (\\ \" \n \t \r). (No python3: it would import modules
# from the project folder.) EVERY_CORNER_HOOK_PARSER=raw forces the fallback for
# the tests; any other value is ignored.
raw_parse() {
  printf '%s' "$input" | tr '\n' ' ' \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | awk '{ gsub(/\\\\/, "@@EC_BS@@"); gsub(/\\"/, "\""); gsub(/\\n/, "\n");
             gsub(/\\[tr]/, " "); gsub(/@@EC_BS@@/, "\\"); printf "%s", $0 }'
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

# SQL can sit inside a heredoc fed to psql, so check the untouched command.
re_sql='(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[a-z_])'
sql=0
shopt -s nocasematch
[[ $cmd =~ $re_sql ]] && sql=1
shopt -u nocasematch

# Normalize in two linear passes:
#  awk: join backslash-newline continuations; drop the body of a heredoc that
#       `cat` or `tee` writes (text, not commands), unless it is piped to a shell;
#       `<<<` here-strings and commented lines are not heredocs.
#  sed: remove quotes, drop git's global options (`git -C dir push` -> `git push`),
#       and mark `git rm` / `npm rm` so the plain-rm rule does not see them.
text="$(printf '%s\n' "$cmd" | awk '
  {
    line = $0
    if (pending != "") { line = pending " " line; pending = "" }
    if (line ~ /\\$/) { pending = substr(line, 1, length(line) - 1); next }
    if (delim != "") {
      t = line; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t == delim) delim = ""
      next
    }
    print line
    if (line ~ /^[ \t]*#/) next
    if (line ~ /\|[ \t]*(sudo[ \t]+)?(ba|z|da)?sh([ \t]|$)/) next
    if (match(line, /(^|[^A-Za-z0-9_])(cat|tee)([^<]|<[^<])*<<-?[^A-Za-z_<]*[A-Za-z_][A-Za-z0-9_]*/)) {
      m = substr(line, RSTART, RLENGTH)
      sub(/.*<<-?[^A-Za-z_<]*/, "", m)
      delim = m
    }
  }
  END { if (pending != "") print pending }' \
  | sed -E \
      -e "s/[\"']//g" \
      -e 's/git(([[:blank:]]+(-C|-c|--git-dir|--work-tree|--namespace)[[:blank:]]+[^[:blank:]]+|[[:blank:]]+--?[a-zA-Z][a-zA-Z-]*(=[^[:blank:]]+)?)+)([[:blank:]]+[a-z])/git\5/g' \
      -e 's/git([[:blank:]]+)rm([[:blank:];&|)]|$)/git_rm\2/g' \
      -e 's/(npm|pnpm|yarn)([[:blank:]]+)rm([[:blank:];&|)]|$)/\1_rm\3/g')" || text="$cmd"

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
A='([[:blank:]]+[^;&|[:space:]]+)*[[:blank:]]+'
E='([[:space:];&|)`]|$)'

has() { [[ $text =~ $1 ]]; }

# For segments starting with $1 (a regex with no groups), set $seg to the
# segment's arguments, one segment at a time; the callback $2 inspects $seg.
each_segment() {
  local s="$text" re="($1)([^;&|${nl}]*)(.*)"
  while [[ $s =~ $re ]]; do
    seg=" ${BASH_REMATCH[2]} "
    s="${BASH_REMATCH[3]}"
    "$2"
  done
}
seg_flag() {  # short-letter cluster ($1) or long name ($2) in $seg
  local re
  if [ -n "$1" ]; then re="[[:blank:]]-[a-zA-Z]*$1[a-zA-Z]*[[:blank:]]"; [[ $seg =~ $re ]] && return 0; fi
  if [ -n "$2" ]; then re="[[:blank:]]--$2(=[^[:blank:]]*)?[[:blank:]]"; [[ $seg =~ $re ]] && return 0; fi
  return 1
}

# Level 4: cannot be undone
if has "${B}rm${A}(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)${E}"; then
  raise 4 "Deletes folders and everything in them permanently. They do not go to the trash." \
          "List what would be deleted first, or move it to the trash."
fi
if has "${B}git[[:blank:]]+push${A}(-[a-zA-Z]*f[a-zA-Z]*|--force|\\+[^[:space:]]+)${E}"; then
  raise 4 "Replaces the branch on the server with your local copy. Commits that exist only on the server are lost." \
          "git push --force-with-lease (refuses to overwrite work you haven't seen)."
fi
if has "${B}git[[:blank:]]+push${A}(-d|--delete|:[^[:space:]]+)${E}"; then
  raise 4 "Deletes a branch or tag on the server, for everyone. Commits that exist only there are lost." \
          "Make sure nobody still uses it, or keep a backup tag of it first."
fi
if has "${B}git[[:blank:]]+reset${A}--hard${E}"; then
  raise 4 "Throws away all uncommitted changes in your working folder." \
          "git stash (keeps the changes so you can get them back)."
fi
if has "${B}git[[:blank:]]+(checkout|restore)([[:blank:]]+--)?[[:blank:]]+\\.${E}"; then
  raise 4 "Discards every uncommitted change in this folder." \
          "git stash (keeps the changes so you can get them back)."
fi
check_clean() {
  if seg_flag f force && ! seg_flag n dry-run; then
    raise 4 "Deletes files git is not tracking. They are in no commit, so they cannot be recovered." \
            "git clean -nd first (shows what would be deleted, deletes nothing)."
  fi
}
each_segment "git[[:blank:]]+clean" check_clean
if [ "$sql" = 1 ]; then
  raise 4 "Permanently removes a database table or all of its data." \
          "Take a backup or export first, and make sure this is not the production database."
fi
if has "(curl|wget)[^|;${nl}]*\\|[[:blank:]]*(sudo[[:blank:]]+)?(ba|z|da)?sh${E}"; then
  raise 4 "Downloads a script from the internet and runs it immediately, without you seeing what it does." \
          "Download the script, read it, then run it."
fi
check_publish() {
  local re='[[:blank:]](publish|upload)[[:blank:]]'
  if [[ $seg =~ $re ]] && ! seg_flag '' dry-run && ! seg_flag '' help && ! seg_flag h ''; then
    raise 4 "Publishes this package publicly. A published version cannot be taken back." \
            "Run a dry run first (for npm: npm publish --dry-run)."
  fi
}
each_segment "npm|pnpm|yarn|cargo|twine" check_publish
if has "${B}(mkfs(\\.[a-z0-9]+)?${E}|dd[[:blank:]][^;&|${nl}]*of=/dev/)"; then
  raise 4 "Overwrites a whole disk or partition." \
          "Double-check the device name; there is no safe version of this."
fi
if has "${B}docker[[:blank:]]+(system|volume)[[:blank:]]+prune${E}"; then
  raise 4 "Deletes unused Docker data. Volumes can hold database files." \
          "Run docker system df first to see what would be removed."
fi
if has "${B}kubectl${A}delete${E}"; then
  raise 4 "Deletes resources from a Kubernetes cluster." \
          "Check the current context (kubectl config current-context) and try --dry-run=client first."
fi

# Level 3: hard to undo
check_git_rm() {
  if seg_flag f force && ! seg_flag '' cached; then
    raise 3 "Removes files from git and from disk, even if they have changes you haven't committed. The last committed version can be restored; uncommitted edits in them are lost." \
            "Commit or stash first, or use git rm --cached to keep the files on disk."
  fi
}
each_segment "git_rm" check_git_rm
check_branch() {
  if seg_flag D '' || { seg_flag d delete && seg_flag f force; }; then
    raise 3 "Deletes a branch even if its work was never merged. Recovery needs git reflog." \
            "git branch -d (refuses if the work isn't merged)."
  fi
}
each_segment "git[[:blank:]]+branch" check_branch
if has "${B}(sudo|doas)${E}"; then
  raise 3 "Runs with administrator rights. It can change anything on this computer, not just this project."
fi
if has "${B}chmod${A}0?777${E}"; then
  raise 3 "Lets every user on this computer read, change and run these files." \
          "Use a narrower permission, such as chmod 755 or chmod +x."
fi
if has "${B}git[[:blank:]][^;&|${nl}]*--no-verify${E}"; then
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
