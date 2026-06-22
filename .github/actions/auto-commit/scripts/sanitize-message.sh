#!/usr/bin/env bash
# Sanitize the raw opencode response into a conventional commit message with
# a subject line and an optional multi-line body. The model is expected to
# return a message where the subject is on the first line, optionally followed
# by a blank line and a body of bullet points.
#
# Emits status=success, new_msg (subject + body) to GITHUB_OUTPUT.
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

# Strip markdown noise (backticks, leading list markers, headers) globally so
# the body bullets are clean too.
CLEAN=$(printf '%s\n' "$raw_response" | tr -d '`' | sed 's/^[*#>\ ]*//')

# Extract subject: first non-empty line, capped at 72 chars, trimmed.
SUBJECT=$(printf '%s\n' "$CLEAN" | awk 'NF {print; exit}' | cut -c1-72 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$SUBJECT" ]; then
  echo "::error::Sanitized subject is empty. Raw response was:" >&2
  printf '%s\n' "$raw_response" >&2
  exit 1
fi

# Validate subject matches conventional-commits format. If not, fail loudly
# so the workflow stops here instead of producing a bad message.
CONVENTIONAL_RE='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)[:\(]'
if [[ ! $SUBJECT =~ $CONVENTIONAL_RE ]]; then
  echo "::error::Sanitized subject does not match conventional-commits format: $SUBJECT" >&2
  exit 1
fi

# Extract body: everything after the first blank line following the subject.
# Use awk to find the first blank line and emit what comes after.
BODY=$(printf '%s\n' "$CLEAN" | awk '
  BEGIN { found_subject = 0; found_blank = 0 }
  /^[[:space:]]*$/ {
    if (found_subject && !found_blank) { found_blank = 1; next }
  }
  NF {
    if (found_subject && found_blank) { print; next }
    if (!found_subject) { found_subject = 1; next }
  }
')

# Wrap body lines at 72 chars while preserving leading "- " bullets.
WRAPPED_BODY=""
if [ -n "$BODY" ]; then
  WRAPPED_BODY=$(printf '%s\n' "$BODY" | fold -s -w 72)
fi

# Compose the final commit message: subject + blank line + body (if any).
if [ -n "$WRAPPED_BODY" ]; then
  NEW_MSG="${SUBJECT}

${WRAPPED_BODY}"
else
  NEW_MSG="$SUBJECT"
fi

emit "status=success"
emit_multiline new_msg <<< "$NEW_MSG"
