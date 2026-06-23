#!/usr/bin/env bash
# Update a PR's title and/or body via the GitHub REST API.
# Uses GITHUB_TOKEN (preferred) or PERSONAL_ACCESS_TOKEN (fallback).
# Skips update when the body is not empty (i.e. the human already wrote one).
# Emits updated=true|false to GITHUB_OUTPUT.
# Required env: GITHUB_TOKEN, PR_NUMBER, REPOSITORY, GITHUB_OUTPUT
# Optional env: NEW_TITLE, NEW_DESCRIPTION, BODY_IS_EMPTY

set -euo pipefail
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"

# Accept any of these token env vars. Fall back in order.
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${PERSONAL_ACCESS_TOKEN:-}}}"
: "${TOKEN:?A GitHub token is required: pass GITHUB_TOKEN, GH_TOKEN, or PERSONAL_ACCESS_TOKEN}"
export GITHUB_TOKEN="$TOKEN"

emit() { printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; }

# Don't touch the PR if the body is not empty. The user has already written a
# description; we respect it.
if [ "${BODY_IS_EMPTY:-true}" != "true" ]; then
  echo "::notice::PR body is not empty; skipping title/description update to respect user's description"
  emit "updated=false"
  exit 0
fi

# Build the JSON payload. If NEW_TITLE is set, include it. If NEW_DESCRIPTION
# is set, include it as the body.
PAYLOAD='{'
if [ -n "${NEW_TITLE:-}" ]; then
  PAYLOAD="${PAYLOAD}\"title\":$(printf '%s' "$NEW_TITLE" | jq -Rs .),"
fi
if [ -n "${NEW_DESCRIPTION:-}" ]; then
  PAYLOAD="${PAYLOAD}\"body\":$(printf '%s' "$NEW_DESCRIPTION" | jq -Rs .),"
fi
# Strip trailing comma.
PAYLOAD=$(printf '%s' "$PAYLOAD" | sed 's/,$//')
PAYLOAD="${PAYLOAD}}"

# Skip if nothing to update.
if [ "$PAYLOAD" = "{}" ]; then
  echo "::notice::No title or body to update; skipping"
  emit "updated=false"
  exit 0
fi

# Call the GitHub API.
HTTP_CODE=$(curl -sS -o /tmp/pr-update-resp.json -w "%{http_code}" \
  -X PATCH \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}")

if [ "$HTTP_CODE" = "200" ]; then
  echo "::notice::PR #${PR_NUMBER} title/body updated successfully"
  emit "updated=true"
else
  echo "::error::Failed to update PR #${PR_NUMBER}. HTTP $HTTP_CODE" >&2
  cat /tmp/pr-update-resp.json >&2 || true
  exit 1
fi
rm -f /tmp/pr-update-resp.json
