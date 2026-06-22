#!/usr/bin/env bash
# Amend the current commit with a new message and force-push.
# Requires env: GH_TOKEN, NEW_MSG, GITHUB_REPOSITORY, GITHUB_REF_NAME

set -euo pipefail
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${NEW_MSG:?NEW_MSG is required}"

CURRENT_HEAD_MSG=$(git log -1 --pretty=%s)
if [ "$CURRENT_HEAD_MSG" = "$NEW_MSG" ]; then
  echo "::notice::Commit message already up to date, skipping push"
  exit 0
fi

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

git commit --amend -m "$NEW_MSG" --no-verify
git push --force-with-lease origin "$GITHUB_REF_NAME"
