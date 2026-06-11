#!/usr/bin/env bash
# Discord notification script - secure, optimized, scalable

WEBHOOK="${DISCORD_WEBHOOK:-}"
[ -z "$WEBHOOK" ] && exit 0

TITLE="${1:-}"
[ -z "$TITLE" ] && exit 0

COLOR="${2:-5763719}"
DESCRIPTION="${3:-}"
URL="${4:-}"
EVENT_TYPE="${5:-default}"
OLD_MSG="${6:-}"
NEW_MSG="${7:-}"

REPO="${GITHUB_REPOSITORY:-}"
BRANCH="${GITHUB_REF_NAME:-}"
ACTOR="${GITHUB_ACTOR:-}"
STATUS="${STATUS:-success}"
FOOTER="${FOOTER:-GitHub Actions}"
RUN_URL="${RUN_URL:-}"

BOT_NAME="AutoCommit Bot"
BOT_AVATAR="https://avatars.githubusercontent.com/u/9919?v=4"

case "$STATUS" in
  skipped) COLOR=16776960 ;;
  failure) COLOR=15158332 ;;
esac

case "$EVENT_TYPE" in
  commit)    EMOJI="📝"; TITLE_BASE="Commit Message Fixed" ;;
  pr)        EMOJI="🔀"; TITLE_BASE="PR Description Fixed" ;;
  ci)        EMOJI="⚙️";  TITLE_BASE="CI Status Update" ;;
  issue)     EMOJI="🐛"; TITLE_BASE="Issue Updated" ;;
  release)   EMOJI="🚀"; TITLE_BASE="Release Published" ;;
  deploy)    EMOJI="📦"; TITLE_BASE="Deployment Update" ;;
  *)         EMOJI="📋"; TITLE_BASE="${TITLE}" ;;
esac

TITLE="$EMOJI $TITLE_BASE"

OLD_MSG=$(echo "$OLD_MSG" | tr '\n' ' ' | sed 's/\r//' | cut -c1-200)
NEW_MSG=$(echo "$NEW_MSG" | tr '\n' ' ' | sed 's/\r//' | cut -c1-200)

[ -z "$RUN_URL" ] && RUN_URL="https://github.com/$GITHUB_REPOSITORY/actions"
[ -z "$URL" ] && URL="$RUN_URL"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g'
}

BOT_NAME_ESC=$(jq_escape "$BOT_NAME")
BOT_AVATAR_ESC=$(jq_escape "$BOT_AVATAR")
TITLE_ESC=$(jq_escape "$TITLE")
FOOTER_ESC=$(jq_escape "$FOOTER")

[ -z "$OLD_MSG" ] && [ -z "$NEW_MSG" ] && echo "[Discord] Skipping: no changes detected" && exit 0

BRANCH_ENC=$(printf '%s' "$BRANCH" | sed 's|/|%2F|g')
BRANCH_LINK="[$BRANCH](https://github.com/$REPO/tree/$BRANCH_ENC)"
AUTHOR_LINK="[$ACTOR](https://github.com/$ACTOR)"
BRANCH_LINK_ESC=$(jq_escape "$BRANCH_LINK")
AUTHOR_LINK_ESC=$(jq_escape "$AUTHOR_LINK")

COMMIT_SHA="${8:-}"
COMMIT_LINK=""
if [ -n "$COMMIT_SHA" ] && [ "$COMMIT_SHA" != "" ]; then
  COMMIT_SHA_6=$(echo "$COMMIT_SHA" | cut -c1-6)
  COMMIT_LINK="[$COMMIT_SHA_6](https://github.com/$REPO/commit/$COMMIT_SHA)"
fi
COMMIT_LINK_ESC=$(jq_escape "$COMMIT_LINK")

PR_NUMBER="${9:-}"
PR_LINK=""
if [ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "" ]; then
  PR_LINK="[$PR_NUMBER]($URL)"
fi
PR_LINK_ESC=$(jq_escape "$PR_LINK")

if [ -n "$OLD_MSG" ] && [ -n "$NEW_MSG" ] && [ "$OLD_MSG" != "" ] && [ "$NEW_MSG" != "" ] && [ "$OLD_MSG" != "$NEW_MSG" ]; then
  OLD_ESC=$(jq_escape "$OLD_MSG")
  NEW_ESC=$(jq_escape "$NEW_MSG")
  if [ "$EVENT_TYPE" = "pr" ] && [ -n "$PR_LINK" ]; then
    FIELDS_JSON="[{\"name\":\"Branch\",\"value\":\"$BRANCH_LINK_ESC\",\"inline\":true},{\"name\":\"PR\",\"value\":\"$PR_LINK_ESC\",\"inline\":true},{\"name\":\"Author\",\"value\":\"$AUTHOR_LINK_ESC\",\"inline\":true},{\"name\":\"Before\",\"value\":\"$OLD_ESC\",\"inline\":false},{\"name\":\"After\",\"value\":\"$NEW_ESC\",\"inline\":false}]"
  elif [ -n "$COMMIT_LINK" ]; then
    FIELDS_JSON="[{\"name\":\"Branch\",\"value\":\"$BRANCH_LINK_ESC\",\"inline\":true},{\"name\":\"Commit\",\"value\":\"$COMMIT_LINK_ESC\",\"inline\":true},{\"name\":\"Author\",\"value\":\"$AUTHOR_LINK_ESC\",\"inline\":true},{\"name\":\"Before\",\"value\":\"$OLD_ESC\",\"inline\":false},{\"name\":\"After\",\"value\":\"$NEW_ESC\",\"inline\":false}]"
  else
    FIELDS_JSON="[{\"name\":\"Branch\",\"value\":\"$BRANCH_LINK_ESC\",\"inline\":true},{\"name\":\"Author\",\"value\":\"$AUTHOR_LINK_ESC\",\"inline\":true},{\"name\":\"Before\",\"value\":\"$OLD_ESC\",\"inline\":false},{\"name\":\"After\",\"value\":\"$NEW_ESC\",\"inline\":false}]"
  fi
else
  if [ "$EVENT_TYPE" = "pr" ] && [ -n "$PR_LINK" ]; then
    FIELDS_JSON="[{\"name\":\"Branch\",\"value\":\"$BRANCH_LINK_ESC\",\"inline\":true},{\"name\":\"PR\",\"value\":\"$PR_LINK_ESC\",\"inline\":true},{\"name\":\"Author\",\"value\":\"$AUTHOR_LINK_ESC\",\"inline\":true}]"
  elif [ -n "$COMMIT_LINK" ]; then
    FIELDS_JSON="[{\"name\":\"Branch\",\"value\":\"$BRANCH_LINK_ESC\",\"inline\":true},{\"name\":\"Commit\",\"value\":\"$COMMIT_LINK_ESC\",\"inline\":true},{\"name\":\"Author\",\"value\":\"$AUTHOR_LINK_ESC\",\"inline\":true}]"
  else
    FIELDS_JSON="[{\"name\":\"Branch\",\"value\":\"$BRANCH_LINK_ESC\",\"inline\":true},{\"name\":\"Author\",\"value\":\"$AUTHOR_LINK_ESC\",\"inline\":true}]"
  fi
fi

PAYLOAD="{\"username\":\"$BOT_NAME_ESC\",\"avatar_url\":\"$BOT_AVATAR_ESC\",\"embeds\":[{\"title\":\"$TITLE_ESC\",\"url\":\"$RUN_URL\",\"color\":$COLOR,\"fields\":$FIELDS_JSON,\"footer\":{\"text\":\"$FOOTER_ESC\",\"icon_url\":\"$BOT_AVATAR_ESC\"},\"timestamp\":\"$TIMESTAMP\"}]}"

echo "[Discord] Sending notification: $TITLE"
curl -sf -X POST "$WEBHOOK" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" && echo "[Discord] Notification sent" || echo "[Discord] Notification failed"