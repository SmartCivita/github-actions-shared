#!/usr/bin/env bash
# Extract commit metadata and emit as GitHub Actions step outputs.
# Outputs: is_merge, current_msg, files, file_count, diff

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

# Skip merge commits: rewriting them is destructive and not worth the risk.
if [ "$(git rev-list --parents -n 1 HEAD | wc -w)" -gt 2 ]; then
  emit "is_merge=true"
  exit 0
fi

# diff-tree against HEAD itself works even on single-commit repos.
changed_files=$(git diff-tree --no-commit-id --name-only -r HEAD || true)
file_count=$(printf '%s\n' "$changed_files" | grep -c . || true)
diff_content=$(git show HEAD --unified=0 --no-color | grep -E '^\+[^+]' | head -20 || true)
current_msg=$(git log -1 --pretty=%s)

emit "is_merge=false"
emit_multiline current_msg <<< "$current_msg"
emit_multiline files <<< "$changed_files"
emit "file_count=$file_count"
emit_multiline diff <<< "$diff_content"
