#!/usr/bin/env bash
# Eval scaffold: sets up the eval workspace (the current folder) as a git project.
set -euo pipefail
src="$(cd "$(dirname "$0")/../../tests/matchcodebase/fixtures/semi-less-js" && pwd)"
cp -R "$src"/. .
git init -q && git add -A && git -c user.email=eval@example.com -c user.name=eval commit -qm init --allow-empty
