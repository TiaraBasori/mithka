#!/bin/sh
set -eu

# The first GitHub Actions migration uploads used epoch timestamps, including
# iOS build 1786500062. Keep later builds monotonic within the existing 0.10.0
# train while deriving every new value deterministically from Git history.
BUILD_NUMBER_OFFSET=1786500000
COMMIT="${1:-HEAD}"

COMMIT_HEIGHT="$(git rev-list --count "$COMMIT")"
case "$COMMIT_HEIGHT" in
  ''|*[!0-9]*)
    echo "error: expected a numeric commit height, got $COMMIT_HEIGHT" >&2
    exit 1
    ;;
esac

if [ "$COMMIT_HEIGHT" -lt 1 ]; then
  echo "error: commit height must be positive" >&2
  exit 1
fi

printf '%s\n' "$((BUILD_NUMBER_OFFSET + COMMIT_HEIGHT))"
