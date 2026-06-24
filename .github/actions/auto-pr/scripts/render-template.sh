#!/usr/bin/env bash
# Substitute placeholders in a template file using bash parameter
# expansion. This is the only safe way to interpolate user-controlled
# content (like a code diff) into a template, because sed has many
# special characters that can appear in diffs.
#
# Usage: render-template.sh <template-file> [key=value ...]
#
# The template uses Python-style {KEY} placeholders. Output is the
# rendered template written to stdout.
#
# Example:
#   render-template.sh template.txt PR_NUMBER=42 TITLE="feat: add x"
#
# The script is robust to any character in the values: backslashes,
# pipes, slashes, percent signs, newlines, and even sequences that
# look like sed replacement operators. None of them are interpreted.

set -euo pipefail

template="${1:?usage: render-template.sh <template-file> [key=value ...]}"
shift

[[ -f "$template" ]] || { echo "::error::Template not found: $template" >&2; exit 1; }

# Read the template as a single string so we preserve newlines.
content=$(cat "$template")

# Apply each KEY=VALUE substitution. bash parameter expansion is
# purely text-based, so any character in $value is preserved verbatim.
for kv in "$@"; do
  key="${kv%%=*}"
  value="${kv#*=}"
  # The placeholder syntax in the template is {KEY}. We replace
  # every occurrence with the value of $value. We use bash's printf
  # %s to do the substitution because it doesn't interpret format
  # specifiers in the value (unlike $value direct expansion in some
  # contexts).
  content="${content//\{$key\}/$value}"
done

printf '%s' "$content"
