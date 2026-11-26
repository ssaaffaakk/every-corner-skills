#!/usr/bin/env bash
# Tests for require-style-study.sh
# Usage: ./hooks/test-style-guard.sh
# Each case says whether the hook should "block" (deny, once) or "pass" (silent).

set -uo pipefail
cd "$(dirname "$0")"
HOOK="$PWD/require-style-study.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"

fail=0; total=0

run() { # file session [env assignment]  -> prints hook output
  local file="$1" session="$2"
  jq -n --arg f "$file" --arg s "$session" --arg c "$PWD" \
    '{tool_name:"Edit", session_id:$s, cwd:$c, tool_input:{file_path:$f}}' | "$HOOK"
}
check() { # expected name file session [VAR=value]
  local expected="$1" name="$2" file="$3" session="$4" out got
  total=$((total + 1))
  if [ -n "${5:-}" ]; then out="$(env "$5" "$HOOK" < <(jq -n --arg f "$file" --arg s "$session" '{session_id:$s, tool_input:{file_path:$f}}'))"
  else out="$(run "$file" "$session")"; fi
  if [ -z "$out" ]; then got="pass"
  elif [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]; then got="block"
  else got="unknown"; fi
  if [ "$got" = "$expected" ]; then printf 'ok    %-6s %s\n' "$expected" "$name"
  else printf 'FAIL  expected %s, got %s: %s\n' "$expected" "$got" "$name"; fail=$((fail + 1)); fi
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
check pass "STYLE.md already exists" "$T/p2/app/orders.py" s3
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

# 4. Bad input must never error or block.
total=$((total + 1))
out="$(printf 'not json' | "$HOOK" 2>/dev/null)"; rc=$?
if [ -z "$out" ] && [ "$rc" -eq 0 ]; then echo "ok    pass   malformed input is ignored"; else echo "FAIL  malformed input (rc=$rc)"; fail=$((fail + 1)); fi

echo
if [ "$fail" -eq 0 ]; then echo "All $total cases passed."; else echo "$fail of $total cases failed."; exit 1; fi
