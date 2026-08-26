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
# Non-interactive: CAS_CLOVER_PLUGIN_CLIENT_ID=… CAS_CLOVER_PLUGIN_CLIENT_SECRET=… \
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
    echo "configure.sh needs a terminal; use --from-env with CAS_CLOVER_PLUGIN_* set." >&2
    exit 2
  fi
  # Reuse existing values as defaults so re-running only changes what you retype.
  # shellcheck disable=SC1090
  [ -f "$ENV_FILE" ] && . "$ENV_FILE" 2>/dev/null || true

  read -r -p "Clover API URL [${CAS_CLOVER_PLUGIN_SERVER_URL:-$DEFAULT_SERVER_URL}]: " input_server
  read -r -p "Auth URL [${CAS_CLOVER_PLUGIN_AUTH_URL:-$DEFAULT_AUTH_URL}]: " input_auth
  read -r -p "Client ID [${CAS_CLOVER_PLUGIN_CLIENT_ID:+unchanged}]: " input_id
  read -r -s -p "Client Secret [${CAS_CLOVER_PLUGIN_CLIENT_SECRET:+unchanged}]: " input_secret
  echo

  CAS_CLOVER_PLUGIN_SERVER_URL="${input_server:-${CAS_CLOVER_PLUGIN_SERVER_URL:-$DEFAULT_SERVER_URL}}"
  CAS_CLOVER_PLUGIN_AUTH_URL="${input_auth:-${CAS_CLOVER_PLUGIN_AUTH_URL:-$DEFAULT_AUTH_URL}}"
  CAS_CLOVER_PLUGIN_CLIENT_ID="${input_id:-${CAS_CLOVER_PLUGIN_CLIENT_ID:-}}"
  CAS_CLOVER_PLUGIN_CLIENT_SECRET="${input_secret:-${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}}"
fi

: "${CAS_CLOVER_PLUGIN_SERVER_URL:=$DEFAULT_SERVER_URL}"
: "${CAS_CLOVER_PLUGIN_AUTH_URL:=$DEFAULT_AUTH_URL}"
: "${CAS_CLOVER_PLUGIN_CLIENT_ID:=}"
: "${CAS_CLOVER_PLUGIN_CLIENT_SECRET:=}"

if [ -z "$CAS_CLOVER_PLUGIN_CLIENT_ID" ] || [ -z "$CAS_CLOVER_PLUGIN_CLIENT_SECRET" ]; then
  echo "client_id and client_secret are required (Clover Settings > API Tokens)." >&2
  exit 2
fi

mkdir -p "$DATA"
umask 077
{
  printf 'export CAS_CLOVER_PLUGIN_SERVER_URL=%q\n'   "$CAS_CLOVER_PLUGIN_SERVER_URL"
  printf 'export CAS_CLOVER_PLUGIN_AUTH_URL=%q\n'     "$CAS_CLOVER_PLUGIN_AUTH_URL"
  printf 'export CAS_CLOVER_PLUGIN_CLIENT_ID=%q\n'    "$CAS_CLOVER_PLUGIN_CLIENT_ID"
  printf 'export CAS_CLOVER_PLUGIN_CLIENT_SECRET=%q\n' "$CAS_CLOVER_PLUGIN_CLIENT_SECRET"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "wrote $ENV_FILE (mode 600)"
echo "server: $CAS_CLOVER_PLUGIN_SERVER_URL"
echo "auth:   $CAS_CLOVER_PLUGIN_AUTH_URL"
