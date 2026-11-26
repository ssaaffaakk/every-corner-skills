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
if [ -e "$TMP/pwned" ] || [ -e "$TMP/pwned..HEAD" ]; then fail=$((fail+1)); echo "FAIL --since passed an option to git"
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

# Lines under the 400-character cap that mix spaces with other whitespace (NBSP, VT, FF, U+2003).
mkdir -p "$TMP/uni"
python3 -I -c "
import sys; d = sys.argv[1]
for ext in ('java', 'cs', 'c', 'js'):
    for n, ws in enumerate(('\xa0', '\x0b', '\x0c', '\u2003')):
        open('%s/f%d.%s' % (d, n, ext), 'w', encoding='utf-8').write(((' ' + ws) * 190 + ' x\n') * 300)" "$TMP/uni"
timed "Unicode whitespace in Java, C#, C and JS files finishes" 10 python3 -I $S "$TMP/uni"

# One file full of repeated keywords just under the line cap.
mkdir -p "$TMP/kw"
python3 -I -c "
import sys; d = sys.argv[1]
open(d + '/A.java', 'w').write(('final ' * 66 + '\n') * 2400)
open(d + '/B.cs', 'w').write(('async ' * 66 + '\n') * 2400)" "$TMP/kw"
timed "399-character keyword lines in Java and C# finish quickly" 2.5 python3 -I $S "$TMP/kw"

# CRLF repositories: the per-file check used to be quadratic (10,000 files took 3.6 s, now about 0.5 s).
mkdir -p "$TMP/crlf" "$TMP/lf"
python3 -I -c "
import sys
for i in range(10000):
    open('%s/crlf/m%d.py' % (sys.argv[1], i), 'w', newline='').write('def f(x):\r\n    return x\r\n')
    open('%s/lf/m%d.py' % (sys.argv[1], i), 'w', newline='').write('def f(x):\n    return x\n')" "$TMP"
# Same size, so a loaded machine slows both alike: CRLF must not cost much more than LF (it was 7x).
if python3 -I - $S "$TMP/crlf" "$TMP/lf" <<'RATIO'
import subprocess, sys, time
script, crlf, lf = sys.argv[1:4]
def took(folder):
    t = time.monotonic(); subprocess.run([sys.executable, "-I", script, folder], capture_output=True, timeout=120); return time.monotonic() - t
a, b = took(crlf), took(lf)
sys.exit(0 if a < 3 * b + 0.5 else 1)
RATIO
then pass=$((pass+1)); echo "PASS 10,000 CRLF files cost about the same as 10,000 LF files"
else fail=$((fail+1)); echo "FAIL 10,000 CRLF files are much slower than LF files"; fi

# Odd tooling files and file names that are not UTF-8 must not crash the report.
mkdir -p "$TMP/odd"
printf '{"scripts": null}' > "$TMP/odd/package.json"; printf 'x = 1\n' > "$TMP/odd/a.py"
timed "package.json with scripts null does not crash" 10 python3 -I $S "$TMP/odd"
python3 -I -c "open('$TMP/odd/package.json', 'w').write('[' * 100000)"
timed "deeply nested package.json does not crash" 10 python3 -I $S "$TMP/odd"
mkdir -p "$TMP/badname" && ( cd "$TMP/badname" && git init -q && printf 'x = 1\n' > a.py && git add -A && git commit -qm i \
  && git update-index --add --cacheinfo "100644,$(printf 'x = 1\n' | git hash-object -w --stdin),$(printf '\377\376.py')" )
timed "a git file name that is not UTF-8 does not crash" 10 python3 -I $S "$TMP/badname"

# The hook and the script must agree on what counts as source code.
if python3 -I - hooks/require-style-study.sh $S <<'SYNC'
import re, sys
hook, script = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
h_ext = set(re.search(r'case "\$\{file##\*\.\}" in\n\s+([\w|]+)\) ;;', hook).group(1).split("|"))
s_ext = set(re.findall(r'"\.(\w+)":', re.search(r"LANGS = \{(.*?)\n\}", script, re.S).group(1)))
h_skip = set(re.search(r"skip_re='\(\^\|/\)\((.*?)\)/'", hook).group(1).replace("\\.", ".").split("|"))
s_skip = set(re.findall(r'"([^"]+)"', re.search(r"SKIP_DIRS = \{(.*?)\}", script, re.S).group(1)))
h_gen = re.search(r"gen_re='(.*?)'\n", hook).group(1)
s_gen = re.search(r'SKIP_NAME = re\.compile\(\s*r"(.*?)"\s*\)', script, re.S).group(1)
ok = h_ext == s_ext and h_skip == s_skip and h_gen == s_gen
if not ok:
    print("extensions only in hook:", h_ext - s_ext, "only in script:", s_ext - h_ext)
    print("skip dirs only in hook:", h_skip - s_skip, "only in script:", s_skip - h_skip)
    print("generated-file patterns equal:", h_gen == s_gen)
sys.exit(0 if ok else 1)
SYNC
then pass=$((pass+1)); echo "PASS hook and script agree on source extensions, vendored folders and generated files"
else fail=$((fail+1)); echo "FAIL hook and script disagree on what counts as source code"; fi

# --since: non-ASCII names, and a root that is a subfolder of the repository.
G="$TMP/since"; mkdir -p "$G/pkg/çalışma" && ( cd "$G" && git init -q && printf 'x = 1\n' > pkg/çalışma/a.py && git add -A && git commit -qm i )
( cd "$G" && printf 'y = 1\n' > pkg/çalışma/new.py && printf 'z = 1\n' > pkg/plain.py && printf 'o = 1\n' > outside.py && echo '# edit' >> pkg/çalışma/a.py )
stamp=$(git -C "$G" log -1 --format=%h)
python3 -I $S "$G" --since "$stamp" --json > "$TMP/s1.json"
python3 -I $S "$G/pkg" --since "$stamp" --json > "$TMP/s2.json"
check "--since lists modified, non-ASCII and untracked files"  "d['files_listed']==4" "$TMP/s1.json"
check "--since from a subfolder root lists only that folder, including a modified tracked file" "d['files_listed']==3" "$TMP/s2.json"
if python3 -I $S "$TMP/no-such-folder" >/dev/null 2>&1; then fail=$((fail+1)); echo "FAIL a missing folder was accepted"
else pass=$((pass+1)); echo "PASS a missing folder stops with an error"; fi

# File names from the repository are data: a name that is not UTF-8, or has a newline, must not crash or forge lines.
mkdir -p "$TMP/names" && ( cd "$TMP/names" && git init -q && printf 'x = 1\n' > a.py && git add -A && git commit -qm i \
  && git update-index --add --cacheinfo "100644,$(printf 'x = 1\n' | git hash-object -w --stdin),$(printf '\377\376/b.py')" \
  && printf 'y = 1\n' > "$(printf 'c\nFORGED LINE.py')" )
for loc in en_US.UTF-8 C.UTF-8 C; do
  timed "text report with non-UTF-8 and newline names under LC_ALL=$loc" 10 env LC_ALL=$loc python3 -I $S "$TMP/names"
done
if python3 -I $S "$TMP/names" | grep -q '^FORGED LINE'; then fail=$((fail+1)); echo "FAIL a file name forged a line of the report"
else pass=$((pass+1)); echo "PASS a file name cannot forge a line of the report"; fi

# The terminal's encoding can be anything: a name it cannot show is escaped, never a traceback.
mkdir -p "$TMP/enc" && printf 'x = 1\n' > "$TMP/enc/日本é.py"
if python3 -I -c "
import runpy, sys
sys.stdout.reconfigure(encoding='ascii')
sys.argv = ['style-counts.py', sys.argv[1]]
runpy.run_path(sys.argv[0] if False else '$S', run_name='__main__')" "$TMP/enc" > "$TMP/enc.out" 2>&1; then
  pass=$((pass+1)); echo "PASS text report on an ASCII-only terminal"
else fail=$((fail+1)); echo "FAIL text report crashed on an ASCII-only terminal"; tail -2 "$TMP/enc.out"; fi

# core.fsmonitor set in the repository's own config must not run (git ls-files would run it).
mkdir -p "$TMP/fsm" && ( cd "$TMP/fsm" && git init -q && printf 'x = 1\n' > a.py && git add -A && git commit -qm i && git config core.fsmonitor "touch $TMP/FSMON; false" )
python3 -I $S "$TMP/fsm" --json >/dev/null 2>&1
if [ -e "$TMP/FSMON" ]; then fail=$((fail+1)); echo "FAIL core.fsmonitor from the repository config ran"
else pass=$((pass+1)); echo "PASS core.fsmonitor from the repository config never runs"; fi

# --since: a file named like the commit must not make git fail (and fall back to a full count).
H2="$TMP/ambig"; mkdir -p "$H2" && ( cd "$H2" && git init -q && printf 'x = 1\n' > a.py && git add -A && git commit -qm one \
  && printf 'y = 1\n' > b.py && git add -A && git commit -qm two )
ambig=$(git -C "$H2" log -1 --format=%h); printf x > "$H2/$ambig"
python3 -I $S "$H2" --since "$ambig" --json > "$TMP/ambig.json"
check "--since works when a file is named like the commit" "d['git'] is True and d['files_listed']==1" "$TMP/ambig.json"

# The time budget: files not reached are reported, not silently dropped.
python3 -I $S "$H2" --budget 0 --json > "$TMP/budget.json"
check "--budget 0 reads nothing and says so" "d['files_counted']==0 and any('not reached' in k for k in d['skipped'])" "$TMP/budget.json"

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
