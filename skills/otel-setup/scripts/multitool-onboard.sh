#!/usr/bin/env bash
# multitool-onboard.sh — interactively obtain a MultiTool API key without
# exposing the user's password, the cleartext API key, or the session JWT to
# any caller (including a parent Claude Code session).
#
# The script reads credentials directly from the user's terminal (`read -s`
# for password input), keeps the session JWT in shell-local variables, and
# writes only the API key to the env file using `printf` (no `echo`, no
# command logging). The single line printed to stdout on success is:
#
#   OK: MULTI_API_KEY written to <path>
#
# Run this with the `!` prefix in Claude Code so it executes in your real
# terminal (TTY required for hidden password input).

set -euo pipefail

API_BASE="${MULTI_API_BASE:-https://api.multitool.run/api/v1}"
MODE=""
KEY_NAME=""
ENV_FILE=".env"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: multitool-onboard.sh (--signup | --login) --key-name NAME [--env-file PATH]

  --signup            Create a new MultiTool account.
  --login             Use an existing MultiTool account.
  --key-name NAME     Display name for the API key (shown in the MultiTool UI).
  --env-file PATH     Where to write MULTI_API_KEY=... (default: ./.env).
  -h, --help          Show this help.

Environment:
  MULTI_API_BASE      Override the API base URL (default: https://api.multitool.run/api/v1).

USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --signup)     MODE="signup"; shift ;;
    --login)      MODE="login"; shift ;;
    --key-name)   KEY_NAME="${2:?--key-name needs a value}"; shift 2 ;;
    --env-file)   ENV_FILE="${2:?--env-file needs a value}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1" ;;
  esac
done

[[ -z "$MODE" ]]     && { usage >&2; die "must pass --signup or --login"; }
[[ -z "$KEY_NAME" ]] && { usage >&2; die "must pass --key-name"; }

command -v curl >/dev/null 2>&1 || die "curl is required but not found on PATH"
command -v jq   >/dev/null 2>&1 || die "jq is required but not found on PATH"

[[ -t 0 ]] || die "stdin is not a TTY — run this with the '!' prefix in Claude Code so password input is hidden"

# ---------------------------------------------------------------------------
# Prompt for credentials. Password is hidden via `read -s`.
# ---------------------------------------------------------------------------

printf 'Email: ' >&2
IFS= read -r EMAIL
[[ -n "$EMAIL" ]] || die "email is required"

printf 'Password: ' >&2
IFS= read -rs PASSWORD
printf '\n' >&2
[[ -n "$PASSWORD" ]] || die "password is required"

if [[ "$MODE" == "signup" ]]; then
  printf 'Confirm password: ' >&2
  IFS= read -rs PASSWORD_CONFIRM
  printf '\n' >&2
  [[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]] || die "passwords do not match"
  unset PASSWORD_CONFIRM

  printf 'Type "yes" to accept the MultiTool Terms of Service: ' >&2
  IFS= read -r TOS_REPLY
  [[ "$TOS_REPLY" == "yes" ]] || die "Terms of Service must be accepted to create an account"
fi

# ---------------------------------------------------------------------------
# Authenticate. Body and response are piped through jq — never printed.
# ---------------------------------------------------------------------------

if [[ "$MODE" == "signup" ]]; then
  AUTH_PATH="/users"
  AUTH_BODY=$(jq -nc \
    --arg email "$EMAIL" \
    --arg password "$PASSWORD" \
    '{email: $email, password: $password, tos_accepted: true}')
else
  AUTH_PATH="/users/login"
  AUTH_BODY=$(jq -nc \
    --arg email "$EMAIL" \
    --arg password "$PASSWORD" \
    '{email: $email, password: $password}')
fi

unset PASSWORD

AUTH_RESPONSE=$(curl -sS -X POST "$API_BASE$AUTH_PATH" \
  -H 'Content-Type: application/json' \
  -d "$AUTH_BODY") || die "request to $AUTH_PATH failed (network or TLS error)"

unset AUTH_BODY

# Some endpoints wrap responses in {data: ...}; try both shapes.
JWT=$(printf '%s' "$AUTH_RESPONSE" | jq -r '.token // .data.token // empty')
if [[ -z "$JWT" ]]; then
  ERR_TYPE=$(printf '%s' "$AUTH_RESPONSE" | jq -r '.errors[0].error // .error // "Unknown"')
  ERR_MSG=$(printf  '%s' "$AUTH_RESPONSE" | jq -r '.errors[0].message // (.message | tostring) // ""')
  if [[ "$MODE" == "signup" ]]; then
    die "signup failed: ${ERR_TYPE}${ERR_MSG:+ — $ERR_MSG}"
  else
    die "login failed: ${ERR_TYPE}${ERR_MSG:+ — $ERR_MSG}"
  fi
fi
unset AUTH_RESPONSE

auth_header=(-H "Authorization: Bearer $JWT")

# ---------------------------------------------------------------------------
# Pick or create a workspace.
# ---------------------------------------------------------------------------

WS_LIST=$(curl -sS "${auth_header[@]}" "$API_BASE/workspaces") \
  || die "failed to list workspaces"

WS_COUNT=$(printf '%s' "$WS_LIST" | jq -r '(.workspaces // .data.workspaces // []) | length')

if [[ "$WS_COUNT" == "0" ]]; then
  printf 'No workspaces exist yet. Display name for a new workspace: ' >&2
  IFS= read -r WS_NAME
  [[ -n "$WS_NAME" ]] || die "workspace name is required"

  WS_CREATE_BODY=$(jq -nc --arg name "$WS_NAME" '{display_name: $name}')
  WS_RESPONSE=$(curl -sS -X POST "${auth_header[@]}" \
    -H 'Content-Type: application/json' \
    -d "$WS_CREATE_BODY" \
    "$API_BASE/workspaces") || die "failed to create workspace"
  WORKSPACE_ID=$(printf '%s' "$WS_RESPONSE" | jq -r '.id // .data.id // empty')
  [[ -n "$WORKSPACE_ID" ]] || die "workspace create returned no id"
elif [[ "$WS_COUNT" == "1" ]]; then
  WORKSPACE_ID=$(printf '%s' "$WS_LIST" | jq -r '(.workspaces // .data.workspaces)[0].id')
else
  printf 'You have multiple workspaces. Pick one:\n' >&2
  printf '%s' "$WS_LIST" | jq -r \
    '(.workspaces // .data.workspaces) | to_entries[] | "  \(.key + 1)) \(.value.display_name) (id=\(.value.id))"' >&2
  printf 'Enter number: ' >&2
  IFS= read -r WS_PICK
  WORKSPACE_ID=$(printf '%s' "$WS_LIST" \
    | jq -r --argjson n "$WS_PICK" '(.workspaces // .data.workspaces)[$n - 1].id // empty')
  [[ -n "$WORKSPACE_ID" ]] || die "invalid workspace selection"
fi
unset WS_LIST WS_RESPONSE WS_CREATE_BODY WS_NAME WS_PICK

# ---------------------------------------------------------------------------
# Mint the API key. The cleartext token is captured into a local variable and
# never echoed.
# ---------------------------------------------------------------------------

KEY_BODY=$(jq -nc --arg name "$KEY_NAME" '{display_name: $name}')
KEY_RESPONSE=$(curl -sS -X POST "${auth_header[@]}" \
  -H 'Content-Type: application/json' \
  -d "$KEY_BODY" \
  "$API_BASE/workspaces/$WORKSPACE_ID/api-keys") \
  || die "failed to create API key"
unset KEY_BODY

# Try both wrapped and unwrapped shapes.
API_KEY=$(printf '%s' "$KEY_RESPONSE" | jq -r '
  (.api_key_data.api_key // .data.api_key_data.api_key // empty)
')
if [[ -z "$API_KEY" ]]; then
  ERR_TYPE=$(printf '%s' "$KEY_RESPONSE" | jq -r '.errors[0].error // .error // "Unknown"')
  ERR_MSG=$(printf  '%s' "$KEY_RESPONSE" | jq -r '.errors[0].message // (.message | tostring) // ""')
  die "API key creation failed: ${ERR_TYPE}${ERR_MSG:+ — $ERR_MSG}"
fi
unset KEY_RESPONSE JWT auth_header

# ---------------------------------------------------------------------------
# Persist the key. Use printf (not echo) and chmod 600.
# ---------------------------------------------------------------------------

ENV_DIR=$(dirname -- "$ENV_FILE")
[[ -d "$ENV_DIR" ]] || mkdir -p -- "$ENV_DIR"

if [[ -f "$ENV_FILE" ]]; then
  # Strip any prior MULTI_API_KEY line so we don't leave a stale value behind.
  tmp=$(mktemp)
  grep -v -E '^MULTI_API_KEY=' -- "$ENV_FILE" > "$tmp" || true
  mv -- "$tmp" "$ENV_FILE"
fi

umask 077
printf 'MULTI_API_KEY=%s\n' "$API_KEY" >> "$ENV_FILE"
chmod 600 -- "$ENV_FILE" 2>/dev/null || true
unset API_KEY

printf 'OK: MULTI_API_KEY written to %s\n' "$ENV_FILE"
