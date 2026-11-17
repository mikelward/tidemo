#!/bin/sh
# Whether each checkout named has every change committed: make sync copies
# a checkout's files but records its commit, so a change not committed
# would be copied without being recorded. Says which, and fails, if not.
status=0
for dir in "$@"; do
    if ! git -C "$dir" rev-parse --verify --quiet HEAD >/dev/null; then
        echo "$dir isn't a git checkout with a commit" >&2
        status=1
    elif ! git -C "$dir" diff --quiet HEAD --; then
        echo "$dir has changes not committed: commit or stash them first" >&2
        status=1
    fi
done
exit $status
