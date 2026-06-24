#!/usr/bin/env bash
# Extract pull request metadata and diff using curl (no gh dependency).
# Emits to GITHUB_OUTPUT:
#   pr_number, pr_title, pr_body, pr_author, pr_url, base_branch, head_branch,
#   head_sha, file_count, files, diff, body_is_empty
#
# Required env: GITHUB_OUTPUT, PR_NUMBER
# Optional env: GITHUB_TOKEN | GH_TOKEN | PERSONAL_ACCESS_TOKEN (one of them)

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${PR_NUMBER:?PR_NUMBER is required}"

# Accept any of these token env vars. The action.yml passes the input as
# GH_TOKEN (and also as GITHUB_TOKEN) but the caller may also export a
# PERSONAL_ACCESS_TOKEN directly. Fall back in that order.
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${PERSONAL_ACCESS_TOKEN:-}}}"
: "${TOKEN:?A GitHub token is required: pass GITHUB_TOKEN, GH_TOKEN, or PERSONAL_ACCESS_TOKEN}"
export GITHUB_TOKEN="$TOKEN"

emit() { printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; }
emit_multiline() {
  {
    printf '%s<<EOF\n' "$1"
    cat
    printf 'EOF\n'
  } >> "$GITHUB_OUTPUT"
}

# Use curl directly to avoid the gh CLI dependency. Self-hosted runners
# don't always have gh preinstalled, and we only need one endpoint.
API_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}"

HTTP_CODE=$(curl -sS -o /tmp/pr-info-resp.json -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "User-Agent: auto-pr-action" \
  "$API_URL")

if [ "$HTTP_CODE" != "200" ]; then
  echo "::error::Failed to fetch PR #${PR_NUMBER}. HTTP ${HTTP_CODE}" >&2
  cat /tmp/pr-info-resp.json >&2 || true
  exit 1
fi

PR_JSON=$(cat /tmp/pr-info-resp.json)
rm -f /tmp/pr-info-resp.json

PR_TITLE=$(printf '%s' "$PR_JSON" | jq -r '.title')
PR_BODY=$(printf '%s' "$PR_JSON" | jq -r '.body // ""')
PR_AUTHOR=$(printf '%s' "$PR_JSON" | jq -r '.user.login')
PR_URL=$(printf '%s' "$PR_JSON" | jq -r '.html_url')
HEAD_SHA=$(printf '%s' "$PR_JSON" | jq -r '.head.sha')
BASE_BRANCH=$(printf '%s' "$PR_JSON" | jq -r '.base.ref')
HEAD_BRANCH=$(printf '%s' "$PR_JSON" | jq -r '.head.ref')

# Detect whether the current body is empty / effectively empty. We use this
# to decide whether to overwrite or leave the user's description alone.
if [ -z "${PR_BODY// /}" ]; then
  BODY_IS_EMPTY="true"
else
  BODY_IS_EMPTY="false"
fi

# Compute the diff between the merge-base and the head commit. The base
# branch may or may not exist locally (depends on checkout strategy), so we
# try several fallbacks.
DIFF_BASE=""
if [ -n "$BASE_BRANCH" ] && git rev-parse --verify --quiet "origin/${BASE_BRANCH}" >/dev/null 2>&1; then
  DIFF_BASE="origin/${BASE_BRANCH}"
elif [ -n "$BASE_BRANCH" ] && git rev-parse --verify --quiet "${BASE_BRANCH}" >/dev/null 2>&1; then
  DIFF_BASE="${BASE_BRANCH}"
else
  # Last resort: try to fetch the base branch.
  if git fetch origin "${BASE_BRANCH}" >/dev/null 2>&1; then
    DIFF_BASE="origin/${BASE_BRANCH}"
  else
    # Use the merge-base with HEAD as a final fallback.
    DIFF_BASE=$(git merge-base HEAD origin/"${BASE_BRANCH}" 2>/dev/null || echo "HEAD~1")
  fi
fi

# Build a compact diff: keep +/- lines (excluding file headers --- / +++),
# cap at ~2000 chars total. We wrap the pipe in a subshell with `set +e` to
# tolerate SIGPIPE errors when downstream commands like `head` close the
# pipe early (this is normal, not a real failure, but with `set -o pipefail`
# it would otherwise abort the script).
diff_content=$(set +e; git diff --no-color "${DIFF_BASE}...HEAD" 2>/dev/null \
  | grep -E '^[+-][^+-]' \
  | head -100 \
  | cut -c1-200 \
  | tr -d '\000' \
  | head -c 2000)

# Fallback if diff is empty (single-commit PR with no diff against base).
if [ -z "${diff_content// /}" ]; then
  diff_content="(no textual diff available; PR may be empty or the base branch matches head)"
fi

# Changed files list. Wrap in a subshell with `set +e` to tolerate SIGPIPE
# from `grep` when the input is empty.
changed_files=$(set +e; git diff --name-only "${DIFF_BASE}...HEAD" 2>/dev/null)
file_count=$(set +e; printf '%s\n' "$changed_files" | grep -c .)

emit_multiline pr_title <<< "$PR_TITLE"
emit_multiline pr_body <<< "$PR_BODY"
emit_multiline pr_url <<< "$PR_URL"
emit "pr_author=$PR_AUTHOR"
emit "pr_number=$PR_NUMBER"
emit "head_sha=$HEAD_SHA"
emit_multiline base_branch <<< "$BASE_BRANCH"
emit_multiline head_branch <<< "$HEAD_BRANCH"
emit "file_count=$file_count"
emit_multiline files <<< "$changed_files"
emit_multiline diff <<< "$diff_content"
emit "body_is_empty=$BODY_IS_EMPTY"
