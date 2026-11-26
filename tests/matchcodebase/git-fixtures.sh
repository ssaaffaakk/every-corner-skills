# shellcheck shell=bash
# Shared by hooks/test-style-guard.sh and tests/matchcodebase/test-style-counts.sh (sourced, not run).

# A throwaway identity, so test commits never depend on the user's git config.
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# mkbare DIR MARKER: a clone of a repository whose src/ folder is shaped like a bare
# git repository with its own config. Its core.fsmonitor creates MARKER, so a test
# can prove that no git call ever loads configuration planted in a repository.
mkbare() {
  local up="$1-up"
  mkdir -p "$up/src/objects" "$up/src/refs/heads"
  ( cd "$up" && git init -q \
    && printf 'ref: refs/heads/main\n' > src/HEAD && touch src/objects/.keep src/refs/heads/.keep \
    && printf '[core]\n\trepositoryformatversion = 0\n\tbare = false\n\tworktree = .\n\tfsmonitor = "touch %s; false"\n' "$2" > src/config \
    && printf 'x = 1\n' > src/app.py && printf 'y = 1\n' > main.py \
    && git add -A && git commit -qm init && git clone -q "$up" "$1" )
}
