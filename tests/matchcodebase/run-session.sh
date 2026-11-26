#!/usr/bin/env bash
# Runs one headless Claude Code session on a throwaway copy of a fixture and prints one JSON summary line.
# Use it to check triggering and to compare cost with and without the skill (spec R1, R15).
#
#   ./tests/matchcodebase/run-session.sh <fixture-dir> <out-dir> <label> <with|without> "<prompt>"
#
# with     = plugin loaded from this repository
# without  = same plugin, copied without the every-corner-matchcodebase skill (the baseline)
# Bash is limited to read-style commands plus python3, make and pytest (the script and the project's own tools).
# Each run uses plan usage (about $0.50 in a first test), so run few and repeat for averages.
set -eu
if [ "$#" -ne 5 ]; then sed -n 2,9p "$0"; exit 2; fi
FIXTURE=$(cd "$1" && pwd); OUT=$2; LABEL=$3; MODE=$4; PROMPT=$5
REPO=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
WORK="$OUT/$LABEL"
[ -e "$WORK" ] && { echo "refusing to reuse $WORK; pick a new label" >&2; exit 2; }
mkdir -p "$WORK"; cp -R "$FIXTURE"/. "$WORK"/
( cd "$WORK" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )

PLUGIN="$REPO"
if [ "$MODE" = "without" ]; then
  PLUGIN="$OUT/$LABEL-plugin"
  mkdir -p "$PLUGIN"
  rsync -a --exclude '.git' --exclude 'skills/every-corner-matchcodebase' --exclude 'tests' "$REPO"/ "$PLUGIN"/
elif [ "$MODE" != "with" ]; then echo "mode must be with or without" >&2; exit 2; fi

START=$(date +%s)
( cd "$WORK" && claude -p "$PROMPT" --plugin-dir "$PLUGIN" --permission-mode acceptEdits \
    --allowedTools "Bash(python3:*)" "Bash(git:*)" "Bash(make:*)" "Bash(grep:*)" "Bash(cat:*)" "Bash(ls:*)" "Bash(pytest:*)" \
    --output-format stream-json --verbose --max-turns 40 > "$OUT/$LABEL.jsonl" 2> "$OUT/$LABEL.err" ) || true
SECS=$(( $(date +%s) - START ))

python3 - "$OUT/$LABEL.jsonl" "$WORK" "$LABEL" "$MODE" "$SECS" <<'PY'
import json, os, subprocess, sys
path, work, label, mode, secs = sys.argv[1:6]
tools, skills, res = [], [], {}
for line in open(path):
    try: e = json.loads(line)
    except ValueError: continue
    if e.get("type") == "assistant":
        for c in e["message"].get("content", []):
            if c.get("type") == "tool_use":
                tools.append(c["name"])
                if c["name"] == "Skill": skills.append(c["input"].get("skill", ""))
    if e.get("type") == "result": res = e
u = res.get("usage", {})
subprocess.run(["git", "-C", work, "add", "-A", "-N"], capture_output=True)  # count new files too
diff = subprocess.run(["git", "-C", work, "diff", "--shortstat"], capture_output=True, text=True).stdout.strip()
print(json.dumps({
    "label": label, "mode": mode, "seconds": int(secs), "turns": res.get("num_turns"),
    "cost_usd": res.get("total_cost_usd"), "tool_calls": len(tools), "skills_invoked": skills,
    "matchcodebase_invoked": any("matchcodebase" in s for s in skills),
    "style_md_written": os.path.exists(os.path.join(work, "docs/every-corner/STYLE.md")),
    "tokens": {"input": u.get("input_tokens"), "cache_creation": u.get("cache_creation_input_tokens"),
               "cache_read": u.get("cache_read_input_tokens"), "output": u.get("output_tokens")},
    "diff": diff}))
PY
