#!/usr/bin/env bash
# Extract the current commit's metadata: message, changed files, and a small
# diff snippet. Emits current_msg, files, file_count, and diff to GITHUB_OUTPUT.

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"

emit() { printf '%s\n' "$1" >> "$GITHUB_OUTPUT"; }
emit_multiline() {
  {
    printf '%s<<EOF\n' "$1"
    cat
    printf 'EOF\n'
  } >> "$GITHUB_OUTPUT"
}

# diff-tree against HEAD itself works even on single-commit repos where
# HEAD~1 does not exist.
changed_files=$(git diff-tree --no-commit-id --name-only -r HEAD || true)
file_count=$(printf '%s\n' "$changed_files" | grep -c . || true)
diff_content=$(git show HEAD --unified=0 --no-color | grep -E '^\+[^+]' | head -20 || true)
current_msg=$(git log -1 --pretty=%s)

emit_multiline current_msg <<< "$current_msg"
emit_multiline files <<< "$changed_files"
emit "file_count=$file_count"
emit_multiline diff <<< "$diff_content"
