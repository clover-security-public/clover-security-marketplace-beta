#!/usr/bin/env bash
#
# Clover Devin plugin — credential setup.
#
# Claude Code prompts for these four values at `claude plugin install` time via
# the manifest's userConfig block. Devin's plugin manifest has no equivalent, so
# the same four values are collected here and written to the data dir, which the
# hooks source when the environment does not already carry them.
#
# Interactive:     devin/scripts/configure.sh
# Non-interactive: CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=… CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=… \
#                    devin/scripts/configure.sh --from-env
set -euo pipefail

DATA="${CLOVER_DEVIN_DATA:-${HOME}/.devin/clover}"
ENV_FILE="$DATA/env.sh"

DEFAULT_SERVER_URL="https://api.cloversec.io"
DEFAULT_AUTH_URL="https://clover.frontegg.com"

FROM_ENV=false
[ "${1:-}" = "--from-env" ] && FROM_ENV=true

if [ "$FROM_ENV" = false ]; then
  if [ ! -t 0 ]; then
    echo "configure.sh needs a terminal; use --from-env with CLOVER_SECURITY_KURA_PLUGIN_* set." >&2
    exit 2
  fi
  # Reuse existing values as defaults so re-running only changes what you retype.
  # shellcheck disable=SC1090
  [ -f "$ENV_FILE" ] && . "$ENV_FILE" 2>/dev/null || true
  # An env.sh written before the prefix rename exports CAS_CLOVER_PLUGIN_*;
  # carry those values over as defaults for the new names.
  : "${CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL:=${CAS_CLOVER_PLUGIN_SERVER_URL:-}}"
  : "${CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL:=${CAS_CLOVER_PLUGIN_AUTH_URL:-}}"
  : "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:=${CAS_CLOVER_PLUGIN_CLIENT_ID:-}}"
  : "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:=${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}}"

  read -r -p "Clover API URL [${CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL:-$DEFAULT_SERVER_URL}]: " input_server
  read -r -p "Auth URL [${CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL:-$DEFAULT_AUTH_URL}]: " input_auth
  read -r -p "Client ID [${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:+unchanged}]: " input_id
  read -r -s -p "Client Secret [${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:+unchanged}]: " input_secret
  echo

  CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL="${input_server:-${CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL:-$DEFAULT_SERVER_URL}}"
  CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL="${input_auth:-${CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL:-$DEFAULT_AUTH_URL}}"
  CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID="${input_id:-${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}}"
  CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET="${input_secret:-${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:-}}"
fi

: "${CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL:=$DEFAULT_SERVER_URL}"
: "${CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL:=$DEFAULT_AUTH_URL}"
: "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:=}"
: "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:=}"

if [ -z "$CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID" ] || [ -z "$CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET" ]; then
  echo "client_id and client_secret are required (Clover Settings > API Tokens)." >&2
  exit 2
fi

mkdir -p "$DATA"
umask 077
{
  printf 'export CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL=%q\n'   "$CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL"
  printf 'export CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL=%q\n'     "$CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL"
  printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=%q\n'    "$CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID"
  printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=%q\n' "$CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "wrote $ENV_FILE (mode 600)"
echo "server: $CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL"
echo "auth:   $CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL"
