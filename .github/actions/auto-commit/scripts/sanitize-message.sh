#!/usr/bin/env bash
# Sanitize the raw opencode response into a single-line conventional commit
# message. Emits status=success and new_msg to GITHUB_OUTPUT.
# Requires env: raw_response, GITHUB_OUTPUT

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${raw_response:?raw_response is required}"

emit() { printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; }
emit_multiline() {
  {
    printf '%s<<EOF\n' "$1"
    cat
    printf 'EOF\n'
  } >> "$GITHUB_OUTPUT"
}

# Strip markdown noise (backticks, leading list markers, headers), keep first
# line, cap at 72 chars, trim whitespace.
NEW_MSG=$(printf '%s' "$raw_response" | tr -d '`' | sed 's/^[*#>\ ]*//' | head -1 | cut -c1-72 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$NEW_MSG" ]; then
  echo "::error::Sanitized message is empty. Raw response was:" >&2
  printf '%s\n' "$raw_response" >&2
  exit 1
fi

# Validate the sanitized result actually looks conventional. If the model
# ignored the rules, fail loudly so the workflow stops here.
CONVENTIONAL_RE='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)[:\(]'
if [[ ! $NEW_MSG =~ $CONVENTIONAL_RE ]]; then
  echo "::error::Sanitized message does not match conventional-commits format: $NEW_MSG" >&2
  exit 1
fi

emit "status=success"
emit_multiline new_msg <<< "$NEW_MSG"
