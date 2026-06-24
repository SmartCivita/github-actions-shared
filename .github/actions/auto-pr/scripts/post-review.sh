#!/usr/bin/env bash
# Generate a code review using opencode run and post it as a comment
# on the pull request. We use a tool-less custom agent (same as
# generate-pr-description.sh) so the model just answers the prompt.
#
# Emits comment_id to GITHUB_OUTPUT so the workflow can reference it.
# Required env: GITHUB_TOKEN, OPENCODE_API_KEY, PR_NUMBER, REPOSITORY,
# DIFF_CONTENT, CHANGED_FILES, FILE_COUNT, GITHUB_OUTPUT

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${OPENCODE_API_KEY:?OPENCODE_API_KEY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${DIFF_CONTENT:?DIFF_CONTENT is required}"
: "${CHANGED_FILES:?CHANGED_FILES is required}"
: "${FILE_COUNT:?FILE_COUNT is required}"

# Accept any of these token env vars. Fall back in order.
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${PERSONAL_ACCESS_TOKEN:-}}}"
: "${TOKEN:?A GitHub token is required: pass GITHUB_TOKEN, GH_TOKEN, or PERSONAL_ACCESS_TOKEN}"
export GITHUB_TOKEN="$TOKEN"

if ! command -v opencode >/dev/null 2>&1; then
  echo "::error::opencode CLI not found in PATH." >&2
  exit 1
fi

# Install the tool-less custom agent.
AGENT_SRC="${GITHUB_ACTION_PATH:-.}/review-agent.md"
AGENT_DEST_DIR="${GITHUB_WORKSPACE:-$PWD}/.opencode/agents"
mkdir -p "$AGENT_DEST_DIR"
cp "$AGENT_SRC" "$AGENT_DEST_DIR/review.md"

# Build a short prompt for the review. The model is told to respond
# directly with the review body (no preamble, no "here is the review").
PROMPT="You are a senior code reviewer. Write a focused, actionable review
for the following pull request diff. Output ONLY the review body
(no preamble, no labels, no signatures).

RULES:
- Start with a one-line summary of what the PR does
- Group findings by severity: Critical, Suggestions, Optional
- If there is nothing important to flag, output a single short
  approval message (1-2 sentences)
- Use markdown formatting
- Be concise: aim for 8-15 lines total
- Do not make code changes, do not run commands, just write the review

PR: $PR_NUMBER
FILES CHANGED ($FILE_COUNT):
$CHANGED_FILES

DIFF:
$DIFF_CONTENT"

echo "::group::Calling opencode to generate review"

RAW_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -f "$RAW_FILE" "$ERR_FILE" "$AGENT_DEST_DIR/review.md" "$AGENT_DEST_DIR"' EXIT

set +e
OPENCODE_DISABLE_AUTOUPDATE=true \
OPENCODE_DISABLE_MODELS_FETCH=true \
timeout 300 opencode run --pure --agent review --model opencode-go/qwen3.7-max "$PROMPT" \
  >"$RAW_FILE" 2>"$ERR_FILE"
RC=$?
set -e

REVIEW_BODY=$(cat "$RAW_FILE")
ERR_OUTPUT=$(cat "$ERR_FILE")

echo "::endgroup::"

if [ "$RC" -ne 0 ] || [ -z "${REVIEW_BODY// /}" ]; then
  echo "::warning::opencode review generation failed (rc=$RC). Skipping review comment." >&2
  [ -n "$ERR_OUTPUT" ] && printf '%s\n' "$ERR_OUTPUT" >&2
  exit 0
fi

# Post the review as a comment on the PR via the GitHub REST API.
# Use the issue comment endpoint (PRs share it with issues).
PAYLOAD=$(jq -n --arg body "$REVIEW_BODY" '{body: $body}')
HTTP_CODE=$(curl -sS -o /tmp/review-resp.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments")

if [ "$HTTP_CODE" = "201" ]; then
  COMMENT_ID=$(jq -r '.id' /tmp/review-resp.json)
  COMMENT_URL=$(jq -r '.html_url' /tmp/review-resp.json)
  echo "::notice::Review comment posted: $COMMENT_URL"
  printf 'comment_id=%s\n' "$COMMENT_ID" >> "$GITHUB_OUTPUT"
  printf 'comment_url=%s\n' "$COMMENT_URL" >> "$GITHUB_OUTPUT"
else
  echo "::warning::Failed to post review comment (HTTP $HTTP_CODE): $(cat /tmp/review-resp.json)" >&2
fi
rm -f /tmp/review-resp.json
