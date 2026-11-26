#!/usr/bin/env bash
# Eval scaffold: sets up the eval workspace (the current folder) as a git project.
set -euo pipefail
git init -q && git add -A && git -c user.email=eval@example.com -c user.name=eval commit -qm init --allow-empty
