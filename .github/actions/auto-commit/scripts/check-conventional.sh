#!/usr/bin/env bash
# Check whether the current commit message is already in conventional-commits
# format. Emits status=skipped if so, status=needs-fix otherwise.
# Requires env: CURRENT_MSG, GITHUB_OUTPUT

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${CURRENT_MSG:?CURRENT_MSG is required}"

CONVENTIONAL_RE='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)[:\(]'

emit() { printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; }

if [[ $CURRENT_MSG =~ $CONVENTIONAL_RE ]]; then
  emit "status=skipped"
else
  emit "status=needs-fix"
fi
