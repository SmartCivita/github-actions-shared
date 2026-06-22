#!/usr/bin/env bash
# Amend the current commit with a new message (subject + body) and force-push.
# Appends "[skip ci]" as a footer so the resulting push does NOT re-trigger
# this workflow. GitHub skips workflows on push when the commit message
# contains "[skip ci]" (case-insensitive).
#
# NEW_MSG may contain a subject line plus a multi-line body separated by a
# blank line. The script splits on the first blank line: everything before
# becomes the subject (-m), everything after becomes the body (-m). The
# "[skip ci]" trailer is appended as a third -m.
#
# Requires env: GH_TOKEN, NEW_MSG, GITHUB_REPOSITORY, GITHUB_REF_NAME

set -euo pipefail
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${NEW_MSG:?NEW_MSG is required}"

# Idempotency: compare against the subject (first line) of the current commit,
# since the stored commit message may already include a [skip ci] footer and
# body from a previous run of this workflow.
NEW_SUBJECT=$(printf '%s\n' "$NEW_MSG" | awk 'NF {print; exit}')
CURRENT_HEAD_SUBJECT=$(git log -1 --pretty=%s)
if [ "$CURRENT_HEAD_SUBJECT" = "$NEW_SUBJECT" ]; then
  echo "::notice::Commit message already up to date, skipping push"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# Split NEW_MSG into subject (everything up to the first blank line) and
# body (everything after, with leading/trailing blank lines trimmed).
SUBJECT=$(printf '%s\n' "$NEW_MSG" | awk 'NF {print; exit}')
BODY=$(printf '%s\n' "$NEW_MSG" | awk '
  BEGIN { found_subject = 0; printing = 0 }
  NF {
    if (!found_subject) { found_subject = 1; next }
    if (printing) { print }
    else { printing = 1; print }
    next
  }
  /^[[:space:]]*$/ {
    if (found_subject && !printing) { printing = 1; next }
  }
')

# git commit --amend with multiple -m flags joins them with blank lines, so
# the final commit message becomes:
#   <SUBJECT>
#   <blank line>
#   <BODY lines>
#   <blank line>
#   [skip ci]
if [ -n "$BODY" ]; then
  git commit --amend -m "$SUBJECT" -m "$BODY" -m "[skip ci]" --no-verify
else
  git commit --amend -m "$SUBJECT" -m "[skip ci]" --no-verify
fi

git push --force-with-lease origin "$GITHUB_REF_NAME"
