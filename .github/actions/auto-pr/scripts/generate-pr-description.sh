#!/usr/bin/env bash
# Generate a PR title + description using opencode run with a tool-less
# custom agent. Mirrors the approach used in auto-commit:
# - --pure disables external plugins
# - OPENCODE_DISABLE_AUTOUPDATE / _DISABLE_MODELS_FETCH skip startup network calls
# - The custom agent (no tools) ensures the model just answers the prompt
# - timeout 300 tolerates slow providers
#
# Emits raw_response to GITHUB_OUTPUT.
# Required env: PR_NUMBER, BASE_BRANCH, HEAD_BRANCH, AUTHOR, CURRENT_TITLE,
# CURRENT_BODY, CHANGED_FILES, FILE_COUNT, DIFF_CONTENT, OPENCODE_API_KEY,
# GITHUB_OUTPUT
# Required arg: path to the prompt template file

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${OPENCODE_API_KEY:?OPENCODE_API_KEY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${BASE_BRANCH:?BASE_BRANCH is required}"
: "${HEAD_BRANCH:?HEAD_BRANCH is required}"
: "${AUTHOR:?AUTHOR is required}"
: "${CURRENT_TITLE:?CURRENT_TITLE is required}"
: "${CHANGED_FILES:?CHANGED_FILES is required}"
: "${FILE_COUNT:?FILE_COUNT is required}"

PROMPT_TEMPLATE="${1:?usage: generate-pr-description.sh <prompt-template-file>}"
[[ -f "$PROMPT_TEMPLATE" ]] || { echo "::error::Prompt template not found: $PROMPT_TEMPLATE" >&2; exit 1; }

if ! command -v opencode >/dev/null 2>&1; then
  echo "::error::opencode CLI not found in PATH. Install it from https://opencode.ai" >&2
  exit 1
fi

# Install the tool-less custom agent in the working directory so opencode
# discovers it. Same approach as auto-commit.
AGENT_SRC="${GITHUB_ACTION_PATH:-.}/pr-description-agent.md"
AGENT_DEST_DIR="${GITHUB_WORKSPACE:-$PWD}/.opencode/agents"
mkdir -p "$AGENT_DEST_DIR"
cp "$AGENT_SRC" "$AGENT_DEST_DIR/pr-description.md"

# Render the prompt template using bash parameter expansion. This is the
# only safe way to interpolate user-controlled content (like a code diff
# with pipes, slashes, backslashes, percent signs, etc.).
RENDER_SCRIPT="${GITHUB_ACTION_PATH:-.}/scripts/render-template.sh"
PROMPT=$(bash "$RENDER_SCRIPT" "$PROMPT_TEMPLATE" \
  "PR_NUMBER=$PR_NUMBER" \
  "BASE_BRANCH=$BASE_BRANCH" \
  "HEAD_BRANCH=$HEAD_BRANCH" \
  "AUTHOR=$AUTHOR" \
  "CURRENT_TITLE=$CURRENT_TITLE" \
  "CURRENT_BODY=${CURRENT_BODY:-}" \
  "FILE_COUNT=$FILE_COUNT" \
  "CHANGED_FILES=$CHANGED_FILES" \
  "DIFF_CONTENT=${DIFF_CONTENT:-}")

echo "::group::Calling opencode to generate PR title and description"

RAW_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -rf "$RAW_FILE" "$ERR_FILE" "$AGENT_DEST_DIR"' EXIT

set +e
OPENCODE_DISABLE_AUTOUPDATE=true \
OPENCODE_DISABLE_MODELS_FETCH=true \
timeout 300 opencode run --pure --agent pr-description --model opencode-go/qwen3.7-max "$PROMPT" \
  >"$RAW_FILE" 2>"$ERR_FILE"
RC=$?
set -e

RAW_RESPONSE=$(cat "$RAW_FILE")
ERR_OUTPUT=$(cat "$ERR_FILE")

echo "::endgroup::"

case "$RC" in
  0) ;;
  124)
    echo "::error::opencode run timed out after 300s." >&2
    [ -n "$ERR_OUTPUT" ] && { echo "::error::stderr:" >&2; printf '%s\n' "$ERR_OUTPUT" >&2; }
    exit 1
    ;;
  137)
    echo "::error::opencode killed (OOM)." >&2
    exit 1
    ;;
  *)
    echo "::error::opencode run failed with exit code $RC" >&2
    [ -n "$ERR_OUTPUT" ] && { echo "::error::stderr:" >&2; printf '%s\n' "$ERR_OUTPUT" >&2; }
    exit 1
    ;;
esac

if [ -z "${RAW_RESPONSE// /}" ]; then
  echo "::error::opencode returned an empty response" >&2
  exit 1
fi

{
  printf 'raw_response<<EOF\n'
  printf '%s\n' "$RAW_RESPONSE"
  printf 'EOF\n'
} >> "$GITHUB_OUTPUT"
