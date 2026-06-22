#!/bin/bash

set -e

cd /home/pochidev/code/SmartCivita/ERP

echo "=== Testing Diff Content (General Script) ==="
echo ""

echo "=== Current commits ==="
git log --oneline -3

echo ""
CURRENT_MSG=$(git log -1 --pretty=format:"%s")
echo "Current message: $CURRENT_MSG"

if echo "$CURRENT_MSG" | grep -qE '^Merge'; then
    echo "IS_MERGE=true"
    PARENT_COUNT=$(git cat-file -p HEAD | grep -c "^parent ")

    if [ "$PARENT_COUNT" -ge 2 ] && git rev-parse HEAD~2 >/dev/null 2>&1; then
        echo "Using HEAD~2 HEAD~1"
        CHANGED_FILES=$(git diff --name-only HEAD~2 HEAD~1 | tr '\n' ',' | sed 's/,$//')
        FILE_COUNT=$(git diff --name-only HEAD~2 HEAD~1 | wc -l | tr -d ' ')
        DIFF_CONTENT=$(git diff HEAD~2 HEAD~1 | grep -E '^\+[^+]' | head -30 | tr '\n' ' ')
    else
        echo "Using HEAD~1 HEAD"
        CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD | tr '\n' ',' | sed 's/,$//')
        FILE_COUNT=$(git diff --name-only HEAD~1 HEAD | wc -l | tr -d ' ')
        DIFF_CONTENT=$(git diff HEAD~1 HEAD | grep -E '^\+[^+]' | head -30 | tr '\n' ' ')
    fi
else
    echo "IS_MERGE=false"
    CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD | tr '\n' ',' | sed 's/,$//')
    FILE_COUNT=$(git diff --name-only HEAD~1 HEAD | wc -l | tr -d ' ')
    DIFF_CONTENT=$(git diff HEAD~1 HEAD | grep -E '^\+[^+]' | head -30 | tr '\n' ' ')
fi

echo ""
echo "Changed files: $CHANGED_FILES"
echo "File count: $FILE_COUNT"
echo ""
echo "DIFF_CONTENT=$DIFF_CONTENT"

echo ""
echo "=== TEST COMPLETE ==="
