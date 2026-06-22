#!/usr/bin/env bash
# Detect merge commits and emit a single boolean output.
# Emits is_merge=true|false to GITHUB_OUTPUT.

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"

# A merge commit has 2+ parents. git rev-list --parents -n 1 HEAD outputs
# "<sha> <parent1> [<parent2>...]" so wc -w > 2 means it's a merge.
if [ "$(git rev-list --parents -n 1 HEAD | wc -w)" -gt 2 ]; then
  printf 'is_merge=true\n' >> "$GITHUB_OUTPUT"
else
  printf 'is_merge=false\n' >> "$GITHUB_OUTPUT"
fi
