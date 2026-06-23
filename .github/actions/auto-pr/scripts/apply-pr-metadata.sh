#!/usr/bin/env bash
# Apply PR metadata via the GitHub REST API:
# - add requested reviewers (default: JosephRiosHenao, overridable via REVIEWERS)
# - set the PR author as the assignee (overridable via ASSIGNEE; pass "false" to skip)
# - add labels (comma-separated, from NEW_LABELS)
#
# Each operation is best-effort: failures are logged with ::warning:: but do
# not abort the script, so a single failed call doesn't lose the others.
# Emits metadata_status=success|partial|failed to GITHUB_OUTPUT.
# Required env: GITHUB_TOKEN, PR_NUMBER, REPOSITORY, PR_AUTHOR, GITHUB_OUTPUT

set -euo pipefail
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_AUTHOR:?PR_AUTHOR is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"

# Accept any of these token env vars. The action.yml passes the input as
# GITHUB_TOKEN (and also as GH_TOKEN) but the caller may also export a
# PERSONAL_ACCESS_TOKEN directly. Fall back in that order.
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${PERSONAL_ACCESS_TOKEN:-}}}"
: "${TOKEN:?A GitHub token is required: pass GITHUB_TOKEN, GH_TOKEN, or PERSONAL_ACCESS_TOKEN}"
export GITHUB_TOKEN="$TOKEN"

emit() { printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; }

# Use a temp file to capture responses, since we may run several API calls.
RESP=$(mktemp)
trap 'rm -f "$RESP"' EXIT

success_count=0
total_count=0

# 1. Add requested reviewers.
REVIEWERS="${REVIEWERS:-JosephRiosHenao}"
if [ -n "$REVIEWERS" ]; then
  total_count=$((total_count + 1))
  REVIEWERS_JSON=$(printf '%s' "$REVIEWERS" | tr ',' '\n' | jq -R . | jq -s .)
  HTTP_CODE=$(curl -sS -o "$RESP" -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "{\"reviewers\":${REVIEWERS_JSON}}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/requested_reviewers")

  if [ "$HTTP_CODE" = "201" ]; then
    echo "::notice::Reviewers requested: $REVIEWERS"
    success_count=$((success_count + 1))
  else
    echo "::warning::Failed to add reviewers (HTTP $HTTP_CODE): $(cat "$RESP")"
  fi
fi

# 2. Set the PR author as the assignee.
ASSIGNEE="${ASSIGNEE:-$PR_AUTHOR}"
if [ "$ASSIGNEE" != "false" ] && [ -n "$ASSIGNEE" ]; then
  total_count=$((total_count + 1))
  HTTP_CODE=$(curl -sS -o "$RESP" -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "{\"assignees\":[\"${ASSIGNEE}\"]}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/assignees")

  if [ "$HTTP_CODE" = "201" ]; then
    echo "::notice::Assignee set: $ASSIGNEE"
    success_count=$((success_count + 1))
  else
    echo "::warning::Failed to set assignee (HTTP $HTTP_CODE): $(cat "$RESP")"
  fi
fi

# 3. Add labels.
if [ -n "${NEW_LABELS:-}" ]; then
  total_count=$((total_count + 1))
  LABELS_JSON=$(printf '%s' "$NEW_LABELS" | tr ',' '\n' | jq -R . | jq -s 'unique')
  HTTP_CODE=$(curl -sS -o "$RESP" -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    -d "{\"labels\":${LABELS_JSON}}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/labels")

  if [ "$HTTP_CODE" = "200" ]; then
    echo "::notice::Labels added: $NEW_LABELS"
    success_count=$((success_count + 1))
  else
    echo "::warning::Failed to add labels (HTTP $HTTP_CODE): $(cat "$RESP")"
  fi
fi

# Summary status.
if [ "$success_count" -eq "$total_count" ]; then
  emit "metadata_status=success"
elif [ "$success_count" -eq 0 ]; then
  emit "metadata_status=failed"
else
  emit "metadata_status=partial"
fi
