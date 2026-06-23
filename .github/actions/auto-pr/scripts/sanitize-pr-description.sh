#!/usr/bin/env bash
# Sanitize the raw opencode response into a PR title and description.
# Expected format from the model:
#
#   TITLE: feat(login): add login button
#
#   - Add LoginButton component
#   - Wire form to auth service
#
# Emits status=success, pr_title (single line), pr_description (multiline) to
# GITHUB_OUTPUT. The description preserves bullet points and wraps at 72 chars.
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

# Strip markdown noise globally.
CLEAN=$(printf '%s\n' "$raw_response" | tr -d '`' | sed 's/^[*#>\ ]*//')

# Extract the line that starts with "TITLE:". If absent, fall back to the
# first non-empty line.
TITLE=$(printf '%s\n' "$CLEAN" | awk '
  /^[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*/ {
    sub(/^[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*/, "")
    print
    exit
  }
' | head -1)

if [ -z "$TITLE" ]; then
  TITLE=$(printf '%s\n' "$CLEAN" | awk 'NF {print; exit}')
fi

# Strip any "TITLE:" prefix that the model may have left in the first line.
TITLE=$(printf '%s' "$TITLE" | sed 's/^[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*//')

# Trim and cap to 72 chars.
TITLE=$(printf '%s' "$TITLE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-72)

if [ -z "$TITLE" ]; then
  echo "::error::Sanitized title is empty. Raw response was:" >&2
  printf '%s\n' "$raw_response" >&2
  exit 1
fi

# Validate the title follows conventional-commits format. We allow either a
# conventional subject (feat:, fix:, ...) or a plain descriptive title.
CONVENTIONAL_RE='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)[:\(]'
if [[ ! $TITLE =~ $CONVENTIONAL_RE ]]; then
  echo "::warning::Title does not match conventional-commits format: $TITLE" >&2
  # Not a hard error: we still accept the title and proceed.
fi

# Extract description: everything after the TITLE line. If the model emitted
# a blank line, then bullets, capture only the bullets.
DESCRIPTION=$(printf '%s\n' "$CLEAN" | awk '
  BEGIN { past_title = 0; saw_blank = 0 }
  NR == 1 && /^[Tt][Ii][Tt][Ll][Ee]:/ { past_title = 1; next }
  NR == 1 && !/^[Tt][Ii][Tt][Ll][Ee]:/ { past_title = 1 }  # fall back: no TITLE: line
  past_title {
    if (!NF) { saw_blank = 1; next }
    if (saw_blank) { print }
  }
')

# Normalize bullets: ensure each starts with "- " (the model may have dropped
# the dash in some cases). Then wrap each line at 72 chars.
DESCRIPTION=$(printf '%s\n' "$DESCRIPTION" \
  | sed 's/^[[:space:]]*[*\-][[:space:]]*/- /' \
  | sed 's/^[[:space:]]*//' \
  | fold -s -w 72)

emit "status=success"
emit "pr_title=$TITLE"
emit_multiline pr_description <<< "$DESCRIPTION"
