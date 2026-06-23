#!/usr/bin/env bash
# Extract the current commit's metadata: message, changed files, and a diff
# snippet suitable for sending to a model. Emits current_msg, files,
# file_count, and diff to GITHUB_OUTPUT.
#
# The diff is a small, model-friendly view of the changes:
# - file headers (--- / +++) are stripped, only the changed lines are kept
# - both added (+) and removed (-) lines are included so the model can see
#   replacements, not just pure additions
# - output is capped at ~2000 chars to keep the prompt under token limits
# - if the diff is empty (e.g. empty commits, mode-only changes) we still emit
#   a sentinel so the model has something to work with

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

# Build a compact diff: keep +/- lines (excluding file headers --- / +++),
# cap at ~2000 chars total so the prompt stays within token limits.
diff_content=$(git show HEAD --no-color \
  | grep -E '^[+-][^+-]' \
  | head -100 \
  | cut -c1-200 \
  | tr -d '\000' \
  | head -c 2000 || true)

# If the diff is empty (e.g. commit only changed file modes, or was empty),
# emit a clear sentinel so the model doesn't think the data is missing.
if [ -z "${diff_content// /}" ]; then
  diff_content="(no textual diff available; the commit only changed file metadata, modes, or was empty)"
fi

current_msg=$(git log -1 --pretty=%s)

emit_multiline current_msg <<< "$current_msg"
emit_multiline files <<< "$changed_files"
emit "file_count=$file_count"
emit_multiline diff <<< "$diff_content"
