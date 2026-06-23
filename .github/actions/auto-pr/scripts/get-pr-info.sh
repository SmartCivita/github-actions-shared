#!/usr/bin/env bash
# Extract pull request metadata and diff.
# Emits to GITHUB_OUTPUT:
#   pr_number, pr_title, pr_body, pr_author, pr_url, base_branch, head_branch,
#   head_sha, file_count, files, diff, body_is_empty
#
# Required env: GITHUB_OUTPUT, GITHUB_TOKEN (for gh CLI), PR_NUMBER (or derived
# from github.event.pull_request.number passed via the caller workflow).

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${PR_NUMBER:?PR_NUMBER is required}"

# Accept any of these token env vars. The action.yml passes the input as
# GH_TOKEN (and also as GITHUB_TOKEN) but the caller may also export a
# PERSONAL_ACCESS_TOKEN directly. Fall back in that order.
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-${PERSONAL_ACCESS_TOKEN:-}}}"
: "${TOKEN:?A GitHub token is required: pass GITHUB_TOKEN, GH_TOKEN, or PERSONAL_ACCESS_TOKEN}"
export GITHUB_TOKEN="$TOKEN"
export GH_TOKEN="$TOKEN"

emit() { printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; }
emit_multiline() {
  {
    printf '%s<<EOF\n' "$1"
    cat
    printf 'EOF\n'
  } >> "$GITHUB_OUTPUT"
}

# Verify gh is available.
if ! command -v gh >/dev/null 2>&1; then
  echo "::error::gh CLI not found in PATH. Install it or use a different action." >&2
  exit 1
fi

# Fetch full PR metadata via gh API. This includes title, body, base, head,
# author, and the head SHA needed for the diff.
PR_JSON=$(gh api "/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" \
  --jq '{title, body, html_url, user: .user.login, head_sha: .head.sha, base_ref: .base.ref, head_ref: .head.ref}')

PR_TITLE=$(printf '%s' "$PR_JSON" | jq -r '.title')
PR_BODY=$(printf '%s' "$PR_JSON" | jq -r '.body // ""')
PR_AUTHOR=$(printf '%s' "$PR_JSON" | jq -r '.user')
PR_URL=$(printf '%s' "$PR_JSON" | jq -r '.html_url')
HEAD_SHA=$(printf '%s' "$PR_JSON" | jq -r '.head_sha')
BASE_BRANCH=$(printf '%s' "$PR_JSON" | jq -r '.base_ref')
HEAD_BRANCH=$(printf '%s' "$PR_JSON" | jq -r '.head_ref')

# Detect whether the current body is empty / effectively empty. We use this
# to decide whether to overwrite or leave the user's description alone.
if [ -z "${PR_BODY// /}" ]; then
  BODY_IS_EMPTY="true"
else
  BODY_IS_EMPTY="false"
fi

# Compute the diff between the merge-base and the head commit. This is the
# canonical PR diff that includes all commits in the branch.
if git rev-parse --verify --quiet "${BASE_BRANCH}" >/dev/null 2>&1; then
  # BASE_BRANCH exists locally (fetched by checkout).
  DIFF_BASE="${BASE_BRANCH}"
else
  # Fallback: try fetch from origin (may fail if no network, but worth trying).
  git fetch origin "${BASE_BRANCH}" >/dev/null 2>&1 || DIFF_BASE="HEAD~1"
  DIFF_BASE="${BASE_BRANCH}"
fi

# Build a compact diff: keep +/- lines (excluding file headers --- / +++),
# cap at ~2000 chars total.
diff_content=$(git diff --no-color "${DIFF_BASE}...HEAD" 2>/dev/null \
  | grep -E '^[+-][^+-]' \
  | head -100 \
  | cut -c1-200 \
  | tr -d '\000' \
  | head -c 2000 || true)

# Fallback if diff is empty (single-commit PR with no diff against base).
if [ -z "${diff_content// /}" ]; then
  diff_content="(no textual diff available; PR may be empty or the base branch matches head)"
fi

# Changed files list.
changed_files=$(git diff --name-only "${DIFF_BASE}...HEAD" 2>/dev/null || true)
file_count=$(printf '%s\n' "$changed_files" | grep -c . || true)

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
