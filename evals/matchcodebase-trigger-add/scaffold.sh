#!/usr/bin/env bash
# Eval scaffold: copies the odd-python fixture into the eval workspace (the current folder)
# and makes it a git project, so the skill sees a project that already has code.
set -euo pipefail
src="$(cd "$(dirname "$0")/../../tests/matchcodebase/fixtures/odd-python" && pwd)"
cp -R "$src"/. .
git init -q && git add -A && git -c user.email=eval@example.com -c user.name=eval commit -qm init
