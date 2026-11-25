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
# How it works: read the command, normalize it once (join line continuations,
# drop heredoc bodies, strip quotes), split it into segments at ; && || | &, and
# classify each segment by its command word. All matching happens inside bash
# (no grep per rule), so the hook adds only a few milliseconds to each command.
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

# Read .tool_input.command with jq, or, without jq, a sed fallback that undoes
# the JSON escapes (\\ \" \t \n \r). EVERY_CORNER_HOOK_PARSER forces one parser;
# the tests use it. (No python3: it would import modules from the project folder.)
parser="${EVERY_CORNER_HOOK_PARSER:-auto}"
if [ "$parser" = "auto" ]; then
  if command -v jq >/dev/null 2>&1; then parser=jq; else parser=raw; fi
fi
if [ "$parser" = "jq" ]; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || cmd=""
else
  cmd="$(printf '%s' "$input" | tr '\n' ' ' \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | sed -e 's/\\\\/@@EC_BACKSLASH@@/g' -e 's/\\"/"/g' -e 's/\\[tnr]/ /g' \
          -e 's/@@EC_BACKSLASH@@/\\/g')" || cmd=""
  [ -z "$cmd" ] && cmd="$input"
fi
[ -z "$cmd" ] && exit 0

nl=$'\n'
q="'"

# 1. Join backslash-newline continuations (a variable, because bash 3.2 on macOS
#    ignores $'...' inside this kind of pattern).
cmd="${cmd//\\$nl/ }"

# 2. Drop heredoc bodies, so text written into a file is not read as commands.
stripped=""
delim=""
re_heredoc='<<-?[[:space:]]*[\\"'"$q"']?([A-Za-z_][A-Za-z0-9_]*)'
while IFS= read -r line || [ -n "$line" ]; do
  if [ -n "$delim" ]; then
    re_end="^[[:space:]]*${delim}[[:space:]]*\$"
    [[ $line =~ $re_end ]] && delim=""
    continue
  fi
  stripped="$stripped$line$nl"
  if [[ $line =~ $re_heredoc ]]; then delim="${BASH_REMATCH[1]}"; fi
done <<< "$cmd"

# 3. Strip quotes, so "+main" or "-rf" cannot hide an argument.
full="${cmd//[\"$q]/}"          # whole command, heredocs included (for SQL)
work="${stripped//[\"$q]/}"     # heredocs dropped (for everything else)

level=0
what=""
safer=""

# Keep the most serious finding across all segments.
raise() {
  if [ "$1" -gt "$level" ]; then level="$1"; what="$2"; safer="${3:-}"; fi
}

# Does the current segment's argument list carry a flag? $1 = short letter (or
# a bracket class) found anywhere in a cluster like -uf, $2 = long name.
flag() {
  local re
  if [ -n "$1" ]; then
    re="[[:space:]]-[a-zA-Z]*$1[a-zA-Z]*[[:space:]]"
    [[ $args =~ $re ]] && return 0
  fi
  if [ -n "$2" ]; then
    re="[[:space:]]--$2(=[^[:space:]]*)?[[:space:]]"
    [[ $args =~ $re ]] && return 0
  fi
  return 1
}

git_rules() {
  local a="$args" sub
  local re_c='^[[:space:]]+-[Cc][[:space:]]+[^[:space:]]+(.*)$'
  local re_o='^[[:space:]]+-[^[:space:]]*(.*)$'
  local re_s='^[[:space:]]+([^[:space:]]+)(.*)$'
  # Skip git's global options (-C dir, -c key=value, --no-pager, ...).
  while :; do
    if [[ $a =~ $re_c ]]; then a="${BASH_REMATCH[1]}"
    elif [[ $a =~ $re_o ]]; then a="${BASH_REMATCH[1]}"
    else break
    fi
  done
  [[ $a =~ $re_s ]] || return 0
  sub="${BASH_REMATCH[1]}"
  args="${BASH_REMATCH[2]} "
  local re_plus='[[:space:]]\+[^[:space:]]'
  local re_colon='[[:space:]]:[^[:space:]]'
  local re_dot='^[[:space:]]+(--[[:space:]]+)?\.[[:space:]]'
  case "$sub" in
    push)
      if flag f force || [[ $args =~ $re_plus ]]; then
        raise 4 "Replaces the branch on the server with your local copy. Commits that exist only on the server are lost." \
                "git push --force-with-lease (refuses to overwrite work you haven't seen)."
      elif flag d delete || [[ $args =~ $re_colon ]]; then
        raise 4 "Deletes a branch or tag on the server, for everyone. Commits that exist only there are lost." \
                "Make sure nobody still uses it, or keep a backup tag of it first."
      fi ;;
    reset)
      flag '' hard && raise 4 "Throws away all uncommitted changes in your working folder." \
                              "git stash (keeps the changes so you can get them back)." ;;
    checkout|restore)
      [[ $args =~ $re_dot ]] && raise 4 "Discards every uncommitted change in this folder." \
                                        "git stash (keeps the changes so you can get them back)." ;;
    clean)
      if flag f force && ! flag n dry-run; then
        raise 4 "Deletes files git is not tracking. They are in no commit, so they cannot be recovered." \
                "git clean -nd first (shows what would be deleted, deletes nothing)."
      fi ;;
    rm)
      if flag f force && ! flag '' cached; then
        raise 3 "Removes files from git and from disk, even if they have changes you haven't committed. The last committed version can be restored; uncommitted edits in them are lost." \
                "Commit or stash first, or use git rm --cached to keep the files on disk."
      fi ;;
    branch)
      if flag D '' || { flag d delete && flag f force; }; then
        raise 3 "Deletes a branch even if its work was never merged. Recovery needs git reflog." \
                "git branch -d (refuses if the work isn't merged)."
      fi ;;
  esac
  if flag '' no-verify; then
    raise 3 "Skips the project's safety checks (git hooks) for this commit or push." \
            "Run without --no-verify and fix what the checks report."
  fi
  return 0
}

# Classify one segment by its command word.
classify() {
  local s="$1" w had_sudo=0 wrapped=0
  local re_trim='^[[:space:]]*(.*)$'
  local re_wrap='^(sudo|command|exec|nohup|time|env|xargs|nice)[[:space:]]+(.*)$'
  local re_opt='^(-[^[:space:]]*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)[[:space:]]+(.*)$'
  local re_path='^[^[:space:]]*/([^/[:space:]]+)(.*)$'
  local re_first='^([^[:space:]]+)(.*)$'
  [[ $s =~ $re_trim ]] && s="${BASH_REMATCH[1]}"
  # Look through wrappers: sudo, env VAR=x, xargs -0, command, ...
  while :; do
    if [[ $s =~ $re_wrap ]]; then
      [ "${BASH_REMATCH[1]}" = "sudo" ] && had_sudo=1
      wrapped=1
      s="${BASH_REMATCH[2]}"
    elif [ "$wrapped" = 1 ] && [[ $s =~ $re_opt ]]; then
      s="${BASH_REMATCH[2]}"
    else
      break
    fi
  done
  s="${s#\\}"                                   # \rm -> rm
  [[ $s =~ $re_path ]] && s="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"   # /bin/rm -> rm
  [[ $s =~ $re_first ]] || return 0
  w="${BASH_REMATCH[1]}"
  args="${BASH_REMATCH[2]} "

  local re_publish='^[[:space:]]+publish[[:space:]]'
  local re_upload='^[[:space:]]+upload[[:space:]]'
  local re_dd='[[:space:]]of=/dev/'
  local re_prune='^[[:space:]]+(system|volume)[[:space:]]+prune[[:space:]]'
  local re_delete='[[:space:]]delete[[:space:]]'
  local re_777='^[[:space:]]+(-R[[:space:]]+)?0?777[[:space:]]'
  local re_exec='[[:space:]]-exec(dir)?[[:space:]]+(.*)$'
  case "$w" in
    rm)
      flag '[rR]' recursive && raise 4 "Deletes folders and everything in them permanently. They do not go to the trash." \
                                       "List what would be deleted first, or move it to the trash." ;;
    git) git_rules ;;
    npm|pnpm|yarn|cargo|twine)
      if { [[ $args =~ $re_publish ]] || [[ $args =~ $re_upload ]]; } \
         && ! flag '' dry-run && ! flag '' help && ! flag h ''; then
        raise 4 "Publishes this package publicly. A published version cannot be taken back." \
                "Run a dry run first (for npm: npm publish --dry-run)."
      fi ;;
    mkfs|mkfs.*)
      raise 4 "Overwrites a whole disk or partition." "Double-check the device name; there is no safe version of this." ;;
    dd)
      [[ $args =~ $re_dd ]] && raise 4 "Overwrites a whole disk or partition." \
                                       "Double-check the device name; there is no safe version of this." ;;
    docker)
      [[ $args =~ $re_prune ]] && raise 4 "Deletes unused Docker data. Volumes can hold database files." \
                                          "Run docker system df first to see what would be removed." ;;
    kubectl)
      [[ $args =~ $re_delete ]] && raise 4 "Deletes resources from a Kubernetes cluster." \
                                           "Check the current context (kubectl config current-context) and try --dry-run=client first." ;;
    chmod)
      [[ $args =~ $re_777 ]] && raise 3 "Lets every user on this computer read, change and run these files." \
                                        "Use a narrower permission, such as chmod 755 or chmod +x." ;;
    find)
      if [[ $args =~ $re_exec ]]; then classify "${BASH_REMATCH[2]}"; fi ;;
  esac
  if [ "$had_sudo" = 1 ]; then
    raise 3 "Runs with administrator rights. It can change anything on this computer, not just this project."
  fi
  return 0
}

# Downloading a script straight into a shell spans a pipe, so check it first.
re_pipe_sh='(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh([[:space:]]|$)'
if [[ $work =~ $re_pipe_sh ]]; then
  raise 4 "Downloads a script from the internet and runs it immediately, without you seeing what it does." \
          "Download the script, read it, then run it."
fi

# SQL can sit inside a heredoc fed to psql, so check the whole command.
re_sql='(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[a-z_])'
shopt -s nocasematch
if [[ $full =~ $re_sql ]]; then
  raise 4 "Permanently removes a database table or all of its data." \
          "Take a backup or export first, and make sure this is not the production database."
fi
shopt -u nocasematch

# Split into segments at && || ; | & and newlines, then classify each one.
segs="$work"
segs="${segs//&&/$nl}"
segs="${segs//||/$nl}"
segs="${segs//;/$nl}"
segs="${segs//|/$nl}"
segs="${segs//&/$nl}"
args=""
while IFS= read -r seg || [ -n "$seg" ]; do
  [ -n "$seg" ] && classify "$seg"
done <<< "$segs"

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
