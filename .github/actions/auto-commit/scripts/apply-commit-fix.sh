#!/usr/bin/env bash
# Amend the current commit with a new message and force-push.
# Appends "[skip ci]" as a footer to the commit message so the resulting push
# does NOT re-trigger this workflow. GitHub skips workflows on push when the
# commit message contains "[skip ci]" (case-insensitive).
# Requires env: GH_TOKEN, NEW_MSG, GITHUB_REPOSITORY, GITHUB_REF_NAME

set -euo pipefail
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${NEW_MSG:?NEW_MSG is required}"

# Compare against the subject (first line) of the current commit, since the
# stored commit message may already include a [skip ci] footer from a previous
# run of this workflow.
CURRENT_HEAD_SUBJECT=$(git log -1 --pretty=%s)
if [ "$CURRENT_HEAD_SUBJECT" = "$NEW_MSG" ]; then
  echo "::notice::Commit message already up to date, skipping push"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

# Footer that tells GitHub not to trigger workflows on this push.
# The blank line separator follows the conventional-commits spec for footers.
COMMIT_MSG="${NEW_MSG}

[skip ci]"

git commit --amend -m "$COMMIT_MSG" --no-verify
git push --force-with-lease origin "$GITHUB_REF_NAME"
