#!/usr/bin/env bash
# Generate a conventional commit message using opencode.
# Emits raw_response (the model's full text output) to GITHUB_OUTPUT.
# Fails with exit 1 if the model returns nothing or times out, so the workflow
# stops loudly instead of silently producing a degraded commit message.
# Usage: generate-message.sh <prompt-template-file>
# Requires env: CURRENT_MSG, CHANGED_FILES, FILE_COUNT, DIFF_CONTENT, OPENCODE_API_KEY, GITHUB_OUTPUT

set -euo pipefail
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set}"
: "${CURRENT_MSG:?CURRENT_MSG is required}"
: "${CHANGED_FILES:?CHANGED_FILES is required}"
: "${FILE_COUNT:?FILE_COUNT is required}"
: "${OPENCODE_API_KEY:?OPENCODE_API_KEY is required}"

PROMPT_TEMPLATE="${1:?usage: generate-message.sh <prompt-template-file>}"
[[ -f "$PROMPT_TEMPLATE" ]] || { echo "::error::Prompt template not found: $PROMPT_TEMPLATE" >&2; exit 1; }

# Verify opencode is installed and reachable.
if ! command -v opencode >/dev/null 2>&1; then
  echo "::error::opencode CLI not found in PATH. Install it from https://opencode.ai" >&2
  exit 1
fi

# Build prompt from template.
PROMPT=$(sed \
  -e "s|__CURRENT_MSG__|$CURRENT_MSG|g" \
  -e "s|__FILE_COUNT__|$FILE_COUNT|g" \
  -e "s|__CHANGED_FILES__|$CHANGED_FILES|g" \
  -e "s|__DIFF_CONTENT__|${DIFF_CONTENT:-}|g" \
  "$PROMPT_TEMPLATE")

echo "::group::Calling opencode to generate commit message"

# Call the model.
# - --pure disables external plugins. The default plugin set (warp-notifications,
#   copilot, LSPs, MCPs) is geared for interactive TUI use and can hang for
#   minutes in headless CI environments trying to fetch provider lists.
# - OPENCODE_DISABLE_AUTOUPDATE / _DISABLE_MODELS_FETCH skip the network calls
#   opencode does on startup (autoupdate check, fetching model lists from
#   models.dev). In a CI runner these can hang for minutes waiting on a flaky
#   network. The model is provided explicitly via --model so we don't need
#   the fetched list.
# - timeout 300 (5 min) tolerates large diffs on slow providers.
# - keep stdout and stderr in separate files so we can report them on failure.
RAW_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -f "$RAW_FILE" "$ERR_FILE"' EXIT

set +e
OPENCODE_DISABLE_AUTOUPDATE=true \
OPENCODE_DISABLE_MODELS_FETCH=true \
timeout 300 opencode run --pure --model opencode-go/qwen3.7-max "$PROMPT" \
  >"$RAW_FILE" 2>"$ERR_FILE"
RC=$?
set -e

RAW_RESPONSE=$(cat "$RAW_FILE")
ERR_OUTPUT=$(cat "$ERR_FILE")

echo "::endgroup::"

# Detect known transient/infrastructure failure modes from stderr before
# branching on the exit code. This produces actionable messages instead of
# generic "exit code N" errors.
if [ -n "$ERR_OUTPUT" ]; then
  if [[ "$ERR_OUTPUT" == *"certificate"* || "$ERR_OUTPUT" == *"x509"* || "$ERR_OUTPUT" == *"tls"* || "$ERR_OUTPUT" == *"SSL_"* ]]; then
    echo "::error::opencode hit a TLS/certificate error. The runner's trust store may be missing the CA chain for the model API." >&2
    echo "::error::Fix on the runner: install/update ca-certificates and ensure SSL_CERT_FILE/SSL_CERT_DIR point to a valid bundle." >&2
    echo "::error::stderr: $ERR_OUTPUT" >&2
    exit 1
  fi
  if [[ "$ERR_OUTPUT" == *"timeout"* || "$ERR_OUTPUT" == *"context deadline"* || "$ERR_OUTPUT" == *"connection refused"* || "$ERR_OUTPUT" == *"no such host"* || "$ERR_OUTPUT" == *"network"* || "$ERR_OUTPUT" == *"unreachable"* ]]; then
    echo "::error::opencode hit a network/timeout error reaching the model API." >&2
    echo "::error::stderr: $ERR_OUTPUT" >&2
    exit 1
  fi
fi

# Distinguish failure modes for clearer logs.
case "$RC" in
  0)   ;;
  124)
    echo "::error::opencode run timed out after 300s. Likely causes:" >&2
    echo "::error::  - Provider slowness on this model" >&2
    echo "::error::  - opencode waiting for interactive input (login prompt, TTY)" >&2
    echo "::error::  - Network issue reaching the model API" >&2
    [ -n "$ERR_OUTPUT" ] && { echo "::error::stderr from opencode:" >&2; printf '%s\n' "$ERR_OUTPUT" >&2; }
    [ -n "$RAW_RESPONSE" ] && echo "::error::First 200 bytes of stdout: ${RAW_RESPONSE:0:200}" >&2
    exit 1
    ;;
  137)
    echo "::error::opencode was killed (signal 9, OOM). Run on a runner with more memory." >&2
    [ -n "$ERR_OUTPUT" ] && { echo "::error::stderr from opencode:" >&2; printf '%s\n' "$ERR_OUTPUT" >&2; }
    exit 1
    ;;
  *)
    echo "::error::opencode run failed with exit code $RC" >&2
    [ -n "$ERR_OUTPUT" ] && { echo "::error::stderr from opencode:" >&2; printf '%s\n' "$ERR_OUTPUT" >&2; }
    [ -n "$RAW_RESPONSE" ] && echo "::error::First 200 bytes of stdout: ${RAW_RESPONSE:0:200}" >&2
    exit 1
    ;;
esac

if [ -z "${RAW_RESPONSE// /}" ]; then
  echo "::error::opencode returned an empty response" >&2
  [ -n "$ERR_OUTPUT" ] && { echo "::error::stderr from opencode:" >&2; printf '%s\n' "$ERR_OUTPUT" >&2; }
  exit 1
fi

{
  printf 'raw_response<<EOF\n'
  printf '%s\n' "$RAW_RESPONSE"
  printf 'EOF\n'
} >> "$GITHUB_OUTPUT"
