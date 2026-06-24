#!/usr/bin/env bash
# Sanitize the raw opencode response into a PR title, description, and labels.
# Expected format from the model:
#
#   TITLE: feat(login): add login button
#
#   - Add LoginButton component
#   - Wire form to auth service
#
#   LABELS: feat,frontend
#
# Emits status=success, pr_title, pr_description, pr_labels (comma-separated)
# to GITHUB_OUTPUT. The description preserves bullets and wraps at 72 chars.
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

# Find the LINE numbers where TITLE: and LABELS: appear, so we can split the
# response into three sections.
TITLE_LINE=$(printf '%s\n' "$CLEAN" | awk 'BEGIN{n=0} {n++; if (/^[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*/) {print n; exit}}')
LABELS_LINE=$(printf '%s\n' "$CLEAN" | awk 'BEGIN{n=0} {n++; if (/^[Ll][Aa][Bb][Ee][Ll][Ss]:[[:space:]]*/) {print n; exit}}')

# --- Title ---
if [ -n "$TITLE_LINE" ]; then
  TITLE=$(printf '%s\n' "$CLEAN" | awk -v start="$TITLE_LINE" 'NR==start {sub(/^[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*/, ""); print; exit}')
else
  TITLE=$(printf '%s\n' "$CLEAN" | awk 'NF {print; exit}')
fi

# Strip any "TITLE:" prefix that survived.
TITLE=$(printf '%s' "$TITLE" | sed 's/^[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | cut -c1-72)

if [ -z "$TITLE" ]; then
  echo "::error::Sanitized title is empty. Raw response was:" >&2
  printf '%s\n' "$raw_response" >&2
  exit 1
fi

# Warn (don't fail) if title doesn't match conventional-commits format.
CONVENTIONAL_RE='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)[:\(]'
if [[ ! $TITLE =~ $CONVENTIONAL_RE ]]; then
  echo "::warning::Title does not match conventional-commits format: $TITLE" >&2
fi

# --- Description ---
# Description is everything between the TITLE line and the LABELS line.
if [ -n "$TITLE_LINE" ] && [ -n "$LABELS_LINE" ]; then
  DESCRIPTION=$(printf '%s\n' "$CLEAN" | awk -v t="$TITLE_LINE" -v l="$LABELS_LINE" 'NR>t && NR<l')
elif [ -n "$TITLE_LINE" ]; then
  DESCRIPTION=$(printf '%s\n' "$CLEAN" | awk -v t="$TITLE_LINE" 'NR>t')
else
  DESCRIPTION=""
fi

# Normalize bullets: ensure each starts with "- ". Then wrap each line at 72 chars.
DESCRIPTION=$(printf '%s\n' "$DESCRIPTION" \
  | sed 's/^[[:space:]]*[*\-][[:space:]]*/- /' \
  | sed 's/^[[:space:]]*//' \
  | fold -s -w 72 \
  | sed '/^$/d')

# --- Labels ---
if [ -n "$LABELS_LINE" ]; then
  LABELS=$(printf '%s\n' "$CLEAN" | awk -v start="$LABELS_LINE" 'NR==start {sub(/^[Ll][Aa][Bb][Ee][Ll][Ss]:[[:space:]]*/, ""); print; exit}')
else
  LABELS=""
fi

# Sanitize labels: lowercase, comma-separated, no spaces, only allow alphanum
# and dash. Anything else is dropped. Cap at 4 labels. The `|| true` at the
# end handles SIGPIPE from `head` or `paste` truncation, matching the
# pattern used in auto-commit.
if [ -n "$LABELS" ]; then
  LABELS=$(printf '%s' "$LABELS" | tr '[:upper:]' '[:lower:]' | tr -d ' ' | tr ',' '\n' | grep -E '^[a-z0-9-]+$' | head -4 | paste -sd ',' - || true)
fi

# Whitelist filter: only allow labels from this set. This prevents the model
# from inventing arbitrary labels that don't exist in the repo.
ALLOWED='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|frontend|backend|api|db|infra|auth|ui)$'
if [ -n "$LABELS" ]; then
  LABELS=$(printf '%s' "$LABELS" | tr ',' '\n' | grep -E "$ALLOWED" | paste -sd ',' - || true)
fi

emit "status=success"
emit "pr_title=$TITLE"
emit_multiline pr_description <<< "$DESCRIPTION"
emit "pr_labels=$LABELS"
