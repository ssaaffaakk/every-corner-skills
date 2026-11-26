#!/usr/bin/env bash
# Tests for require-style-study.sh
# Usage: ./hooks/test-style-guard.sh            (HOOK_BASH=/bin/bash to run the hook with a specific bash)
# Each case says whether the hook should "block" (deny, once) or "pass" (silent).
# Every case runs once per parser the hook supports (jq, and the fallback used
# without jq), so the hook is proven to work without jq too. jq is skipped if missing.

set -uo pipefail
cd "$(dirname "$0")" || exit 1
HOOK="$PWD/require-style-study.sh"
hook_bash="${HOOK_BASH:-bash}"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"

parsers=""
command -v jq >/dev/null 2>&1 && parsers="jq"
parsers="$parsers raw"

fail=0; total=0

# Hook input for an Edit call, built without jq (the test paths contain no special characters).
input_for() { # file session [cwd]  (cwd defaults to the project folder under $T)
  local cwd="${3:-}" proj
  if [ -z "$cwd" ]; then proj="${1#"$T"/}"; cwd="$T/${proj%%/*}"; fi
  printf '{"tool_name":"Edit","session_id":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$2" "$cwd" "$1"
}

check() { # expected name file session [VAR=value] [cwd]
  local expected="$1" name="$2" file="$3" session="$4" extra="${5:-EVERY_CORNER_NOOP=1}" cwd="${6:-}" out got p ok=1
  for p in $parsers; do
    total=$((total + 1))
    out="$(input_for "$file" "$session-$p" "$cwd" | env "$extra" EVERY_CORNER_HOOK_PARSER="$p" "$hook_bash" "$HOOK")"
    case "$out" in
      '') got="pass" ;;
      *'"permissionDecision":"deny"'*) got="block" ;;
      *) got="unknown" ;;
    esac
    if [ "$got" = "block" ] && command -v jq >/dev/null 2>&1 && ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
      got="invalid-json"
    fi
    if [ "$got" != "$expected" ]; then
      printf 'FAIL  [%s] expected %s, got %s: %s\n' "$p" "$expected" "$got" "$name"
      fail=$((fail + 1)); ok=0
    fi
  done
  [ "$ok" -eq 1 ] && printf 'ok    %-6s %s\n' "$expected" "$name"
}

mkproject() { # dir  -> git project with two source files
  mkdir -p "$1/app"; ( cd "$1" && git init -q \
    && printf 'def loadOrders(p):\n\treturn p\n' > app/orders.py \
    && printf 'def loadUsers(p):\n\treturn p\n' > app/users.py \
    && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
}

# 1. Source edit in a project with code and no STYLE.md: block once.
mkproject "$T/p1"
check block "source edit, project has code, no STYLE.md" "$T/p1/app/orders.py" s1
check pass  "same session, second edit is never blocked" "$T/p1/app/users.py" s1
check block "a different session is blocked once" "$T/p1/app/orders.py" s2

# 2. Cases that must stay silent.
mkproject "$T/p2"; mkdir -p "$T/p2/docs/every-corner"; echo "# style" > "$T/p2/docs/every-corner/STYLE.md"
check block "STYLE.md exists: sent to the skill to reuse it" "$T/p2/app/orders.py" s3
check pass  "STYLE.md exists: still only once per session" "$T/p2/app/users.py" s3
mkproject "$T/p3"
check pass "not a source file (README.md)" "$T/p3/README.md" s4
check pass "not a source file (docs, json)" "$T/p3/package.json" s5
mkdir -p "$T/empty" && ( cd "$T/empty" && git init -q )
check pass "empty project, new file (nothing to match)" "$T/empty/main.py" s6
mkdir -p "$T/empty2"
check pass "empty folder without git" "$T/empty2/main.py" s7
mkproject "$T/p4"
check pass "option switched off" "$T/p4/app/orders.py" s8 CLAUDE_PLUGIN_OPTION_STYLEGUARD=false

# 3. More blocking cases.
mkproject "$T/p5"
check block "new file in a folder that does not exist yet" "$T/p5/newpkg/sub/feature.py" s9
mkdir -p "$T/nogit/src" && printf 'const a = 1\n' > "$T/nogit/src/a.js" && printf 'const b = 2\n' > "$T/nogit/src/b.js"
check block "project without git" "$T/nogit/src/c.js" s10
mkdir -p "$T/only/src" && printf 'x = 1\n' > "$T/only/src/solo.py"
check pass "the only source file is the one being edited (no git)" "$T/only/src/solo.py" s11
mkdir -p "$T/nm/node_modules/pkg" && printf 'module.exports = 1\n' > "$T/nm/node_modules/pkg/index.js"
check pass "code only inside node_modules does not count" "$T/nm/app.js" s12

# 4. Review findings: files outside the project, unsafe session ids, large edits.
mkproject "$T/p6"; mkdir -p "$T/scratch" && printf 'y = 1\n' > "$T/scratch/old.py"
check pass  "scratch script outside the working project" "$T/scratch/helper.py" s13 EVERY_CORNER_NOOP=1 "$T/p6"
mkproject "$T/p7"; mkdir -p "$T/p7/sub"
check block "file in the same repo but outside the working subfolder" "$T/p7/app/orders.py" s14 EVERY_CORNER_NOOP=1 "$T/p7/sub"
mkproject "$T/p8"
check block "session id with ../ is still blocked once" "$T/p8/app/orders.py" "../../escaped"
if ls "$T" | grep -q escaped || ls "$TMPDIR" | grep -q escaped; then
  echo "FAIL  guard file escaped its folder"; fail=$((fail + 1))
else echo "ok    pass   guard file stays in its folder"; fi
total=$((total + 1))
mkproject "$T/p9"
big="$(awk 'BEGIN { for (i = 0; i < 100000; i++) printf "def f%d(x):\\n    return x\\n", i }')"
for p in $parsers; do
  total=$((total + 1)); t0=$SECONDS
  out="$(printf '{"session_id":"big-%s","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' \
    "$p" "$T/p9" "$T/p9/app/new.py" "$big" | EVERY_CORNER_HOOK_PARSER="$p" "$hook_bash" "$HOOK")"
  took=$((SECONDS - t0))
  case "$out" in *'"deny"'*) ;; *) echo "FAIL  [$p] 3 MB write was not blocked"; fail=$((fail + 1)); continue ;; esac
  if [ "$took" -gt 4 ]; then echo "FAIL  [$p] 3 MB write took ${took}s (limit 4s)"; fail=$((fail + 1))
  else echo "ok    block  [$p] 3 MB write handled in ${took}s"; fi
done

# Code review: unwritable mark folder, skill run before the first edit, symlinked paths.
mkproject "$T/p10"; mkdir -p "$T/ro"; chmod 500 "$T/ro"
for p in $parsers; do
  total=$((total + 1)); n=0
  for i in 1 2 3; do
    out="$(input_for "$T/p10/app/new.py" "ro-$p" | CLAUDE_PLUGIN_DATA="$T/ro" EVERY_CORNER_HOOK_PARSER="$p" "$hook_bash" "$HOOK")"
    case "$out" in *'"deny"'*) n=$((n + 1)) ;; esac
  done
  if [ "$n" -eq 0 ]; then echo "ok    pass   [$p] unwritable mark folder never blocks"
  else echo "FAIL  [$p] unwritable mark folder blocked $n of 3 edits"; fail=$((fail + 1)); fi
done
chmod 700 "$T/ro"
mkproject "$T/p11"
for p in $parsers; do
  total=$((total + 1))
  out="$(printf '{"tool_name":"Skill","session_id":"sk-%s","cwd":"%s","tool_input":{"skill":"every-corner:every-corner-matchcodebase"}}' "$p" "$T/p11" \
    | EVERY_CORNER_HOOK_PARSER="$p" "$hook_bash" "$HOOK")"
  [ -z "$out" ] || { echo "FAIL  [$p] the Skill call itself was blocked"; fail=$((fail + 1)); }
  total=$((total + 1))
  out="$(input_for "$T/p11/app/orders.py" "sk-$p" | EVERY_CORNER_HOOK_PARSER="$p" "$hook_bash" "$HOOK")"
  if [ -z "$out" ]; then echo "ok    pass   [$p] skill ran first: the first edit is not blocked"
  else echo "FAIL  [$p] skill ran first, edit still blocked"; fail=$((fail + 1)); fi
done
mkdir -p "$T/real/solo" && ( cd "$T/real/solo" && git init -q && printf 'x = 1\n' > main.py && git add -A && git -c user.email=t@t -c user.name=t commit -qm i )
ln -s "$T/real" "$T/link"
check pass "only source file, reached through a symlinked folder" "$T/link/solo/main.py" s15 EVERY_CORNER_NOOP=1 "$T/link/solo"

# 5. Bad input must never error or block.
for p in $parsers; do
  total=$((total + 1))
  out="$(printf 'not json' | EVERY_CORNER_HOOK_PARSER="$p" "$hook_bash" "$HOOK" 2>/dev/null)"; rc=$?
  if [ -z "$out" ] && [ "$rc" -eq 0 ]; then echo "ok    pass   [$p] malformed input is ignored"
  else echo "FAIL  [$p] malformed input (rc=$rc)"; fail=$((fail + 1)); fi
done

echo
if [ "$fail" -eq 0 ]; then echo "All $total cases passed."; else echo "$fail of $total cases failed."; exit 1; fi
