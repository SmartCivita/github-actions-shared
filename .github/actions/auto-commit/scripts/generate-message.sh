#!/usr/bin/env bash
# Generate a conventional commit message using opencode.
# Emits raw_response (the model's full text output) to GITHUB_OUTPUT.
# Fails with exit 1 if the model returns nothing, so the workflow stops loudly
# instead of silently producing a degraded commit message.
# Usage: generate-message.sh <prompt-template-file>
# Requires env: CURRENT_MSG, CHANGED_FILES, FILE_COUNT, DIFF_CONTENT, OPENCODE_API_KEY, GITHUB_OUTPUT

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${CURRENT_MSG:?CURRENT_MSG is required}"
: "${CHANGED_FILES:?CHANGED_FILES is required}"
: "${FILE_COUNT:?FILE_COUNT is required}"
: "${OPENCODE_API_KEY:?OPENCODE_API_KEY is required}"

PROMPT_TEMPLATE="${1:?usage: generate-message.sh <prompt-template-file>}"
[[ -f "$PROMPT_TEMPLATE" ]] || { echo "::error::Prompt template not found: $PROMPT_TEMPLATE" >&2; exit 1; }

# Verify opencode is installed and reachable.
if ! command -v opencode >/dev/null 2>&1; then
  echo "::error::opencode CLI not found in PATH. Install it from https://opencode.ai" >&2
  exit 1
fi

# Build prompt from template.
PROMPT=$(sed \
  -e "s|__CURRENT_MSG__|$CURRENT_MSG|g" \
  -e "s|__FILE_COUNT__|$FILE_COUNT|g" \
  -e "s|__CHANGED_FILES__|$CHANGED_FILES|g" \
  -e "s|__DIFF_CONTENT__|${DIFF_CONTENT:-}|g" \
  "$PROMPT_TEMPLATE")

echo "::group::Calling opencode to generate commit message"

# Call the model. Capture stdout, allow non-zero exit (we validate after).
set +e
RAW_RESPONSE=$(timeout 60 opencode run --model opencode-go/qwen3.7-max "$PROMPT" 2>/tmp/opencode.err)
RC=$?
set -e

echo "::endgroup::"

if [ $RC -ne 0 ]; then
  echo "::error::opencode run failed with exit code $RC" >&2
  echo "::error::stderr from opencode:" >&2
  cat /tmp/opencode.err >&2 || true
  rm -f /tmp/opencode.err
  exit 1
fi
rm -f /tmp/opencode.err

if [ -z "${RAW_RESPONSE// /}" ]; then
  echo "::error::opencode returned an empty response" >&2
  exit 1
fi

{
  printf 'raw_response<<EOF\n'
  printf '%s\n' "$RAW_RESPONSE"
  printf 'EOF\n'
} >> "$GITHUB_OUTPUT"
