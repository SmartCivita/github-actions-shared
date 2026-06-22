#!/usr/bin/env bash
# Generate a conventional commit message via opencode.
# Usage: fix-commit-message.sh <prompt-template-file>
# Requires env: CURRENT_MSG, CHANGED_FILES, FILE_COUNT, DIFF_CONTENT, OPENCODE_API_KEY, GITHUB_OUTPUT
# Outputs: status (success|skipped), new_msg

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${CURRENT_MSG:?CURRENT_MSG is required}"
: "${CHANGED_FILES:?CHANGED_FILES is required}"
: "${FILE_COUNT:?FILE_COUNT is required}"

PROMPT_TEMPLATE="${1:?usage: fix-commit-message.sh <prompt-template-file>}"
[[ -f "$PROMPT_TEMPLATE" ]] || { echo "::error::Prompt template not found: $PROMPT_TEMPLATE" >&2; exit 1; }

CONVENTIONAL_RE='^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)[:\(]'

emit() { printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; }
emit_multiline() {
  {
    printf '%s<<EOF\n' "$1"
    cat
    printf 'EOF\n'
  } >> "$GITHUB_OUTPUT"
}

# Already a conventional commit, nothing to do.
if [[ $CURRENT_MSG =~ $CONVENTIONAL_RE ]]; then
  emit "status=skipped"
  exit 0
fi

# Build prompt from template.
PROMPT=$(sed \
  -e "s|__CURRENT_MSG__|$CURRENT_MSG|g" \
  -e "s|__FILE_COUNT__|$FILE_COUNT|g" \
  -e "s|__CHANGED_FILES__|$CHANGED_FILES|g" \
  -e "s|__DIFF_CONTENT__|${DIFF_CONTENT:-}|g" \
  "$PROMPT_TEMPLATE")

# Call the model.
RESPONSE=$(timeout 60 opencode run --model opencode-go/qwen3.7-max "$PROMPT" 2>/dev/null || true)
NEW_MSG=$(printf '%s' "$RESPONSE" | tr -d '`' | sed 's/^[*#>\ ]*//' | head -1 | cut -c1-72 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Fallback: model unavailable or returned nothing. Log so the run is auditable.
if [ -z "$NEW_MSG" ]; then
  echo "::warning::Model returned empty response, using file-based fallback" >&2
  FIRST_FILE=$(printf '%s' "$CHANGED_FILES" | head -1)
  case "$FIRST_FILE" in
    *.md)                      NEW_MSG="docs: update $FIRST_FILE" ;;
    *.test.*|*.spec.*)         NEW_MSG="test: update $FIRST_FILE" ;;
    *)                         NEW_MSG="chore: update $FIRST_FILE" ;;
  esac
  NEW_MSG=$(printf '%s' "$NEW_MSG" | cut -c1-72)
fi

emit "status=success"
emit_multiline new_msg <<< "$NEW_MSG"
