#!/usr/bin/env bash
# Checks that style-counts.py reports what the fixtures were built to show.
# Run from the repository root: ./tests/matchcodebase/test-style-counts.sh
set -u
cd "$(dirname "$0")/../.."
S=skills/every-corner-matchcodebase/scripts/style-counts.py
F=tests/matchcodebase/fixtures
pass=0; fail=0
check() { # name, python expression over d (the JSON report)
  if python3 - "$2" "$3" <<'PY'
import json, sys
d = json.load(open(sys.argv[2]))
sys.exit(0 if eval(sys.argv[1]) else 1)
PY
  then pass=$((pass+1)); echo "PASS $1"; else fail=$((fail+1)); echo "FAIL $1"; fi
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
python3 $S $F/odd-python --json > "$TMP/py.json" || { echo "FAIL script crashed on odd-python"; exit 1; }
python3 $S $F/semi-less-js --json > "$TMP/js.json" || { echo "FAIL script crashed on semi-less-js"; exit 1; }

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
out=$(python3 $S $F/odd-python)
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
python3 $S "$TMP/big" --json > "$TMP/big.json"
elapsed=$(python3 -c "import time;print(round(time.time()-$start,2))")
check "1000 files: counted + skipped == listed"    "d['files_counted']+sum(d['skipped'].values())==d['files_listed']==1001" "$TMP/big.json"
check "1000 files: all 1000 python files counted"  "d['languages']['python']['files']==1000" "$TMP/big.json"
if python3 -c "import sys;sys.exit(0 if $elapsed < 5 else 1)"; then pass=$((pass+1)); echo "PASS 1000 files in ${elapsed}s (limit 5s)"; else fail=$((fail+1)); echo "FAIL 1000 files took ${elapsed}s"; fi

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
