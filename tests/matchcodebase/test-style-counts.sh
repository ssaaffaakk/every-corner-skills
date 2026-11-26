#!/usr/bin/env bash
# Checks that style-counts.py reports what the fixtures were built to show.
# Run from the repository root: ./tests/matchcodebase/test-style-counts.sh
set -u
cd "$(dirname "$0")/../.." || exit 1
S=skills/every-corner-matchcodebase/scripts/style-counts.py
F=tests/matchcodebase/fixtures
pass=0; fail=0
check() { # name, python expression over d (the JSON report)
  if python3 -I - "$2" "$3" <<'PY'
import json, sys
d = json.load(open(sys.argv[2]))
sys.exit(0 if eval(sys.argv[1]) else 1)
PY
  then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1"; fi
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# shellcheck source=git-fixtures.sh
. tests/matchcodebase/git-fixtures.sh
python3 -I $S $F/odd-python --json > "$TMP/py.json" || { echo "FAIL script crashed on odd-python"; exit 1; }
python3 -I $S $F/semi-less-js --json > "$TMP/js.json" || { echo "FAIL script crashed on semi-less-js"; exit 1; }

check "python: tabs are the dominant indent"       "d['languages']['python']['indent']['dominant']=='tabs'" "$TMP/py.json"
check "python: single quotes dominate"             "d['languages']['python']['quotes']['dominant']=='single'" "$TMP/py.json"
check "python: functions are camelCase"            "max(d['languages']['python']['functions'].items(), key=lambda kv: kv[1])[0]=='camelCase'" "$TMP/py.json"
check "python: legacy_helpers.py is an outlier"    "any(o['path'].endswith('legacy_helpers.py') for o in d['languages']['python']['outliers'])" "$TMP/py.json"
check "python: outlier flags tabs/quotes/names"    "any('indent spaces' in o['flags'] and 'quotes double' in o['flags'] for o in d['languages']['python']['outliers'])" "$TMP/py.json"
check "python: ruff and pytest found in pyproject" "any('tool.ruff' in c for c in d['tooling']['configs'])" "$TMP/py.json"
check "python: make lint and make test found"      "d['tooling']['commands'].get('lint')=='make lint' and d['tooling']['commands'].get('test')=='make test'" "$TMP/py.json"
check "python: test file counted as test"          "d['languages']['python']['tests']['files']==1" "$TMP/py.json"
check "python: examples are not the outlier"       "not any('legacy' in e for e in d['languages']['python']['examples'])" "$TMP/py.json"
check "js: no semicolons detected"                 "d['languages']['javascript']['semicolons']['no']>d['languages']['javascript']['semicolons']['yes']" "$TMP/js.json"
check "js: single quotes dominate"                 "d['languages']['javascript']['quotes']['dominant']=='single'" "$TMP/js.json"
check "js: legacy-report.js is an outlier"         "any(o['path'].endswith('legacy-report.js') for o in d['languages']['javascript']['outliers'])" "$TMP/js.json"
check "js: npm scripts found"                      "d['tooling']['commands'].get('test')=='npm run test'" "$TMP/js.json"

# The output must contain numbers and file names, never code (R2).
out=$(python3 -I $S $F/odd-python)
if echo "$out" | grep -q -E "def |return |append\("; then fail=$((fail+1)); echo "FAIL output contains code"; else pass=$((pass+1)); echo "PASS output contains no code"; fi

# R2/R17: file counts add up and a 1000-file project is read in one fast pass.
python3 - "$TMP" <<'PY'
import os, sys
root = os.path.join(sys.argv[1], "big")
for i in range(1000):
    d = os.path.join(root, "pkg%d" % (i % 20)); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "mod%d.py" % i), "w").write("def doThing%d(x):\n    return x\n\n\ndef doOther%d(y):\n    return y\n" % (i, i))
open(os.path.join(root, "notes.md"), "w").write("# notes\n")
PY
start=$(python3 -c 'import time;print(time.time())')
python3 -I $S "$TMP/big" --json > "$TMP/big.json"
elapsed=$(python3 -c "import time;print(round(time.time()-$start,2))")
check "1000 files: counted + skipped == listed"    "d['files_counted']+sum(d['skipped'].values())==d['files_listed']==1001" "$TMP/big.json"
check "1000 files: all 1000 python files counted"  "d['languages']['python']['files']==1000" "$TMP/big.json"
if python3 -c "import sys;sys.exit(0 if $elapsed < 5 else 1)"; then pass=$((pass+1)); echo "PASS 1000 files in ${elapsed}s (limit 5s)"; else fail=$((fail+1)); echo "FAIL 1000 files took ${elapsed}s"; fi

# Review findings: hostile inputs must not hang the script or reach outside the project.
timed() { # name, limit-seconds, command...  (python timer: macOS has no `timeout`)
  local name="$1" lim="$2"; shift 2
  if python3 -I -c '
import subprocess, sys
try:
    sys.exit(subprocess.run(sys.argv[2:], capture_output=True, timeout=float(sys.argv[1])).returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)' "$lim" "$@"
  then pass=$((pass+1)); echo "PASS $name"; else fail=$((fail+1)); echo "FAIL $name (hung or crashed)"; fi
}
H="$TMP/hostile"; mkdir -p "$H/src"
python3 -c "
import sys; d = sys.argv[1]
open(d + '/src/A.java', 'w').write('public' + ' ' * 5000 + 'x\n' + 'public ' + 'a ' * 199 + 'b\n')
open(d + '/src/B.cs', 'w').write('public' + ' ' * 5000 + 'x\n')
open(d + '/src/c.c', 'w').write('a' * 5000 + ' b\n')
open(d + '/src/ok.py', 'w').write('x = 1\n')" "$H"
mkfifo "$H/src/pipe.py" "$TMP/outside.fifo"; ln -s "$TMP/outside.fifo" "$H/src/link.py"
timed "hostile files (long lines, FIFO, symlink to FIFO) finish" 10 python3 -I $S "$H" --json
python3 -I $S "$H" --json > "$TMP/h.json" 2>/dev/null
check "FIFO and symlink are skipped, not read"     "d['skipped'].get('symlink or special file')==2" "$TMP/h.json"
( cd "$H" && git init -q && git add src/ok.py && git commit -qm i )
python3 -I $S "$H" "--since=--output=$TMP/pwned" >/dev/null 2>&1
if [ -e "$TMP/pwned..HEAD" ]; then fail=$((fail+1)); echo "FAIL --since passed an option to git"
else pass=$((pass+1)); echo "PASS --since accepts only a commit hash"; fi

( cd "$H" && printf 'y = 2\n' > src/new_untracked.py && printf 'x = 3\n' > src/ok.py )
stamp=$(git -C "$H" log -1 --format=%h)
python3 -I $S "$H" --since "$stamp" --json > "$TMP/since.json"
check "--since counts uncommitted and untracked changes" "d['languages']['python']['files']==2" "$TMP/since.json"

# Round-1 double review: patterns that backtrack on one long or blank-line-heavy file.
mkdir -p "$TMP/slow"
python3 -I -c "
import sys; d = sys.argv[1]
open(d + '/a.ts', 'w').write(' \n' * 100000)
open(d + '/b.py', 'w').write('x = ' + '\"\\\\' * 100000 + '\n')
open(d + '/c.js', 'w').write('import ' + 'a ' * 100000 + '\n')" "$TMP/slow"
timed "blank-line, quote-backslash and import-heavy files finish" 10 python3 -I $S "$TMP/slow"

# --since: non-ASCII names, and a root that is a subfolder of the repository.
G="$TMP/since"; mkdir -p "$G/pkg/çalışma" && ( cd "$G" && git init -q && printf 'x = 1\n' > pkg/çalışma/a.py && git add -A && git commit -qm i )
( cd "$G" && printf 'y = 1\n' > pkg/çalışma/new.py && printf 'z = 1\n' > pkg/plain.py && printf 'o = 1\n' > outside.py )
stamp=$(git -C "$G" log -1 --format=%h)
python3 -I $S "$G" --since "$stamp" --json > "$TMP/s1.json"
python3 -I $S "$G/pkg" --since "$stamp" --json > "$TMP/s2.json"
check "--since lists non-ASCII and untracked files"  "d['files_listed']==3" "$TMP/s1.json"
check "--since from a subfolder root lists only that folder" "d['files_listed']==2" "$TMP/s2.json"
if python3 -I $S "$TMP/no-such-folder" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL a missing folder was accepted"
else pass=$((pass+1)); echo "PASS a missing folder stops with an error"; fi

# Tooling files are read the same safe way, and a stale --since stamp is an error.
mkdir -p "$TMP/tool" && printf 'x = 1\n' > "$TMP/tool/a.py" && mkfifo "$TMP/tool/Makefile" "$TMP/tool/package.json"
timed "FIFO named Makefile or package.json does not hang" 10 python3 -I $S "$TMP/tool"
if python3 -I $S "$H" --since deadbeef >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL --since with an unknown commit was accepted"
else pass=$((pass+1)); echo "PASS --since with an unknown commit stops with an error"; fi
mkbare "$TMP/bare" "$TMP/PWNED"
python3 -I $S "$TMP/bare/src" --json > /dev/null 2>&1; python3 -I $S "$TMP/bare" --json > /dev/null 2>&1
if [ -e "$TMP/PWNED" ]; then fail=$((fail+1)); echo "FAIL a planted git config ran a command from the script"
else pass=$((pass+1)); echo "PASS planted git config never runs"; fi

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
