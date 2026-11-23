#!/usr/bin/env bash
# Install Clover for Codex.
#
# Developer install (one-time Codex hook trust remains):
#   curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/codex/scripts/install.sh | bash
#
# Administrator-managed install (system hooks are trusted by policy):
#   curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/codex/scripts/install.sh | bash -s -- --managed
#
# Beta marketplace install:
#   curl -fsSL https://raw.githubusercontent.com/clover-security-public/clover-security-marketplace-beta/main/codex/scripts/install.sh | bash -s -- --beta
#
# ChatGPT workspace rollout (builds the credentials plugin the admin uploads):
#   curl -fsSL https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main/codex/scripts/install.sh | bash -s -- --workspace
#
# Single-tenant or BYOC Clover, with any mode (the auth host defaults to auth.
# beside the API host):
#   ... | bash -s -- --server-url https://api.<your-host> [--auth-url https://<auth-host>]
set -euo pipefail

MODE="developer"
CHANNEL="public"

# Single-tenant and BYOC tenants run Clover on their own host: --server-url
# names its API, and the auth host follows it (api. -> auth.) unless
# --auth-url names another. Interactive runs ask for both, defaulting to the
# shared https://api.cloversec.io.
SERVER_URL_ARG=""
AUTH_URL_ARG=""
usage() { printf 'usage: install.sh [--managed | --workspace] [--beta] [--server-url URL] [--auth-url URL]\n'; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --managed) MODE="managed" ;;
    --workspace) MODE="workspace" ;;
    --beta) CHANNEL="beta" ;;
    --server-url|--auth-url)
      [ "$#" -ge 2 ] || { printf 'clover: %s needs a URL\n' "$1" >&2; exit 2; }
      if [ "$1" = "--server-url" ]; then SERVER_URL_ARG="$2"; else AUTH_URL_ARG="$2"; fi
      shift
      ;;
    --server-url=*) SERVER_URL_ARG="${1#*=}" ;;
    --auth-url=*) AUTH_URL_ARG="${1#*=}" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'clover: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# check_url <name> <value>: an https URL with a host, or exit before anything
# is installed or built.
check_url() {
  case "$2" in
    https://?*) ;;
    *) printf 'clover: %s must be an https URL (got %s)\n' "$1" "$2" >&2; exit 2 ;;
  esac
}
[ -z "$SERVER_URL_ARG" ] || check_url "--server-url" "$SERVER_URL_ARG"
[ -z "$AUTH_URL_ARG" ] || check_url "--auth-url" "$AUTH_URL_ARG"

case "$CHANNEL" in
  beta)
    DEFAULT_MARKETPLACE_URL="https://raw.githubusercontent.com/clover-security-public/clover-security-marketplace-beta/main"
    DEFAULT_MARKETPLACE_GIT_URL="https://github.com/clover-security-public/clover-security-marketplace-beta.git"
    MARKETPLACE_NAME="clover-security-beta"
    ;;
  *)
    DEFAULT_MARKETPLACE_URL="https://raw.githubusercontent.com/clover-security-public/agentic-security-marketplace/main"
    DEFAULT_MARKETPLACE_GIT_URL="https://github.com/clover-security-public/agentic-security-marketplace.git"
    MARKETPLACE_NAME="clover-security"
    ;;
esac
MARKETPLACE_URL="${CLOVER_SECURITY_KURA_PLUGIN_MARKETPLACE_URL:-${CLOVER_MARKETPLACE_URL:-$DEFAULT_MARKETPLACE_URL}}"
MARKETPLACE_GIT_URL="${CLOVER_SECURITY_KURA_PLUGIN_MARKETPLACE_GIT_URL:-${CLOVER_MARKETPLACE_GIT_URL:-$DEFAULT_MARKETPLACE_GIT_URL}}"
PLUGIN_ID="clover@${MARKETPLACE_NAME}"

command -v curl >/dev/null || { printf 'clover: curl is required\n' >&2; exit 1; }

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
  darwin*) OS="darwin" ;;
  linux*) OS="linux" ;;
  *) printf 'clover: this installer currently supports macOS and Linux (got %s)\n' "$OS" >&2; exit 1 ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) printf 'clover: unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
esac
BINARY_NAME="clover-hook-${OS}-${ARCH}"

TREE=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../managed/requirements.toml.template" ]; then
    TREE="$(cd "$SCRIPT_DIR/../.." && pwd)"
  fi
fi

obtain() {
  if [ -n "$TREE" ] && [ -f "$TREE/$1" ]; then
    cp "$TREE/$1" "$2"
  else
    curl -fsSL "$MARKETPLACE_URL/$1" -o "$2" \
      || { printf 'clover: failed to download %s\n' "$MARKETPLACE_URL/$1" >&2; return 1; }
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum < "$1" | awk '{print $1}'
  else
    shasum -a 256 < "$1" | awk '{print $1}'
  fi
}

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

stage_runtime() {
  STAGE="$1"
  mkdir -p "$STAGE/bin" "$STAGE/.codex-plugin" "$STAGE/.claude-plugin"
  obtain ".codex-plugin/plugin.json" "$STAGE/.codex-plugin/plugin.json"
  obtain ".claude-plugin/plugin.json" "$STAGE/.claude-plugin/plugin.json"
  obtain "bin/checksums.sha256" "$STAGE/checksums.sha256"
  obtain "bin/$BINARY_NAME" "$STAGE/bin/clover-hook"

  EXPECTED="$(awk -v name="$BINARY_NAME" '{ file=$2; sub(/\r$/, "", file); sub(/^\*/, "", file); if (file == name) print $1 }' "$STAGE/checksums.sha256" | head -1)"
  [ -n "$EXPECTED" ] || { printf 'clover: %s is missing from checksums.sha256\n' "$BINARY_NAME" >&2; exit 1; }
  ACTUAL="$(sha256_of "$STAGE/bin/clover-hook")"
  [ "$EXPECTED" = "$ACTUAL" ] || { printf 'clover: checksum mismatch for %s\n' "$BINARY_NAME" >&2; exit 1; }
  chmod +x "$STAGE/bin/clover-hook"
}

credential_file() {
  if [ "$OS" = "darwin" ]; then
    printf '%s\n' "${CLOVER_CODEX_DATA_DIR:-${HOME}/Library/Application Support/Clover/Codex}/env.sh"
  else
    printf '%s\n' "${CLOVER_CODEX_DATA_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/clover/codex}/env.sh"
  fi
}

# auth_url_for <api url>: Clover's auth host beside its API host
# (https://api.X -> https://auth.X); the shared auth host for any other name.
auth_url_for() {
  case "$1" in
    https://api.*) printf 'https://auth.%s\n' "${1#https://api.}" ;;
    *) printf 'https://auth.cloversec.io\n' ;;
  esac
}

configure_credentials() {
  ENV_FILE="$1"
  if [ -f "$ENV_FILE" ] && {
    { grep -Eq '^export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=.+$' "$ENV_FILE" \
      && grep -Eq '^export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=.+$' "$ENV_FILE"; } \
      || { grep -Eq '^export CAS_CLOVER_PLUGIN_CLIENT_ID=.+$' "$ENV_FILE" \
        && grep -Eq '^export CAS_CLOVER_PLUGIN_CLIENT_SECRET=.+$' "$ENV_FILE"; }
  } && [ -z "${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-}${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:-}${CAS_CLOVER_PLUGIN_CLIENT_ID:-}${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}${SERVER_URL_ARG}${AUTH_URL_ARG}" ]; then
    chmod 600 "$ENV_FILE"
    printf 'clover: preserving credentials in %s\n' "$ENV_FILE"
    return
  fi

  CLIENT_ID="${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID:-${CAS_CLOVER_PLUGIN_CLIENT_ID:-}}"
  CLIENT_SECRET="${CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET:-${CAS_CLOVER_PLUGIN_CLIENT_SECRET:-}}"
  SERVER_URL="${SERVER_URL_ARG:-${CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL:-${CAS_CLOVER_PLUGIN_SERVER_URL:-}}}"
  AUTH_URL="${AUTH_URL_ARG:-${CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL:-${CAS_CLOVER_PLUGIN_AUTH_URL:-}}}"

  if { [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; } \
    && [ -z "${CLOVER_SECURITY_KURA_PLUGIN_NO_PROMPT:-${CLOVER_NO_PROMPT:-}}" ] \
    && { exec 3<>/dev/tty; } 2>/dev/null; then
    printf 'Clover credentials (Clover Settings > API Tokens)\n' >&3
    printf 'Client ID: ' >&3
    IFS= read -r CLIENT_ID <&3 || CLIENT_ID=""
    printf 'Client secret: ' >&3
    IFS= read -rs CLIENT_SECRET <&3 || CLIENT_SECRET=""
    printf '\n' >&3
    if [ -z "$SERVER_URL" ]; then
      printf 'Clover API URL [https://api.cloversec.io]: ' >&3
      IFS= read -r SERVER_URL <&3 || SERVER_URL=""
    fi
    if [ -z "$AUTH_URL" ]; then
      SUGGESTED_AUTH_URL="$(auth_url_for "${SERVER_URL:-https://api.cloversec.io}")"
      printf 'Auth URL [%s]: ' "$SUGGESTED_AUTH_URL" >&3
      IFS= read -r AUTH_URL <&3 || AUTH_URL=""
    fi
    exec 3>&- 2>/dev/null || true
  fi
  SERVER_URL="${SERVER_URL:-https://api.cloversec.io}"
  SERVER_URL="${SERVER_URL%/}"
  AUTH_URL="${AUTH_URL:-$(auth_url_for "$SERVER_URL")}"
  AUTH_URL="${AUTH_URL%/}"
  check_url "the Clover API URL" "$SERVER_URL"
  check_url "the auth URL" "$AUTH_URL"
  if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    printf 'clover: client credentials are required; set CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID and CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET or run interactively\n' >&2
    exit 1
  fi

  mkdir -p "$(dirname "$ENV_FILE")"
  umask 077
  {
    printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_ID=%q\n' "$CLIENT_ID"
    printf 'export CLOVER_SECURITY_KURA_PLUGIN_CLIENT_SECRET=%q\n' "$CLIENT_SECRET"
    printf 'export CLOVER_SECURITY_KURA_PLUGIN_AUTH_URL=%q\n' "$AUTH_URL"
    printf 'export CLOVER_SECURITY_KURA_PLUGIN_SERVER_URL=%q\n' "$SERVER_URL"
    # Compatibility for binaries and existing automation using the old names.
    printf 'export CAS_CLOVER_PLUGIN_CLIENT_ID=%q\n' "$CLIENT_ID"
    printf 'export CAS_CLOVER_PLUGIN_CLIENT_SECRET=%q\n' "$CLIENT_SECRET"
    printf 'export CAS_CLOVER_PLUGIN_AUTH_URL=%q\n' "$AUTH_URL"
    printf 'export CAS_CLOVER_PLUGIN_SERVER_URL=%q\n' "$SERVER_URL"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

run_doctor() {
  WRAPPER="$1"
  RESULT="$(printf '{"cwd":".","session_id":"codex-install-check"}\n' | "$WRAPPER" codex-doctor)"
  case "$RESULT" in
    *'"ok":true'*) printf 'clover: backend verification succeeded\n' ;;
    *) printf 'clover: backend verification failed: %s\n' "$RESULT" >&2; exit 1 ;;
  esac
}

# A ChatGPT workspace import never runs this installer on members' machines, so
# the admin runs it once: it verifies the credentials with the doctor, then
# packs them into the "Clover Kura connection" plugin (templates in
# codex/workspace-credentials/) that the admin uploads and sets to Installed.
# Kura reads its clover-credentials.json from each member's plugin cache.
if [ "$MODE" = "workspace" ]; then
  command -v zip >/dev/null || { printf 'clover: zip is required\n' >&2; exit 1; }
  STAGE="$TEMP_DIR/runtime"
  stage_runtime "$STAGE"
  configure_credentials "$TEMP_DIR/env.sh"
  export CLAUDE_PLUGIN_ROOT="$STAGE"
  export CLAUDE_PLUGIN_DATA="$TEMP_DIR/data"
  mkdir -p "$CLAUDE_PLUGIN_DATA"
  # shellcheck disable=SC1091
  . "$TEMP_DIR/env.sh"
  run_doctor "$STAGE/bin/clover-hook"

  json_string() {
    local value=${1//\\/\\\\}
    value=${value//\"/\\\"}
    printf '"%s"' "$value"
  }
  # Every build is a newer version, so a re-upload always replaces the last one.
  VERSION="0.1.$(date +%Y%m%d%H%M)"
  PLUGIN="$TEMP_DIR/clover-credentials"
  mkdir -p "$PLUGIN/.codex-plugin" "$PLUGIN/skills/kura-connection" "$PLUGIN/assets"
  obtain "codex/workspace-credentials/plugin.json" "$TEMP_DIR/plugin.json"
  sed "s/@VERSION@/$VERSION/" "$TEMP_DIR/plugin.json" > "$PLUGIN/.codex-plugin/plugin.json"
  obtain "codex/workspace-credentials/SKILL.md" "$PLUGIN/skills/kura-connection/SKILL.md"
  obtain "codex/workspace-credentials/clover-icon.svg" "$PLUGIN/assets/clover-icon.svg"
  printf '{\n  "client_id": %s,\n  "client_secret": %s,\n  "server_url": %s,\n  "auth_url": %s\n}\n' \
    "$(json_string "$CLIENT_ID")" "$(json_string "$CLIENT_SECRET")" \
    "$(json_string "$SERVER_URL")" "$(json_string "$AUTH_URL")" > "$PLUGIN/clover-credentials.json"
  chmod 600 "$PLUGIN/clover-credentials.json"

  DOWNLOADS="$HOME/Downloads"
  [ -d "$DOWNLOADS" ] || DOWNLOADS="$PWD"
  OUT="${CLOVER_CODEX_WORKSPACE_ZIP:-$DOWNLOADS/clover-credentials-$VERSION.zip}"
  mkdir -p "$(dirname "$OUT")"
  rm -f "$OUT"
  (cd "$PLUGIN" && zip -qrXD "$OUT" .)
  chmod 600 "$OUT"
  printf 'clover: built %s\n' "$OUT"
  printf 'clover: upload it in admin.openai.com: Marketplaces > Add > Upload plugin, then set "Clover Kura connection" to Installed\n'
  printf 'clover: the zip holds the client secret; delete it after uploading\n'
  exit 0
fi

if [ "$MODE" = "developer" ]; then
  command -v codex >/dev/null || { printf 'clover: Codex CLI is required\n' >&2; exit 1; }

  if ! codex plugin marketplace add "$MARKETPLACE_GIT_URL" >/dev/null 2>&1; then
    : # Older Codex versions can report an existing marketplace as an error.
  fi
  codex plugin marketplace upgrade "$MARKETPLACE_NAME" >/dev/null
  codex plugin add "$PLUGIN_ID" >/dev/null

  DATA_DIR="${CODEX_HOME:-${HOME}/.codex}/plugins/data/clover-${MARKETPLACE_NAME}"
  STAGE="$TEMP_DIR/runtime"
  stage_runtime "$STAGE"
  mkdir -p "$DATA_DIR/bin"
  install -m 755 "$STAGE/bin/clover-hook" "$DATA_DIR/bin/clover-hook"
  VERSION="$(awk -F'"' '/"version"[[:space:]]*:/ { print $4; exit }' "$STAGE/.codex-plugin/plugin.json")"
  printf '%s\n' "$VERSION" > "$DATA_DIR/bin/.version"
  configure_credentials "$DATA_DIR/env.sh"
  export CLAUDE_PLUGIN_ROOT="$STAGE"
  export CLAUDE_PLUGIN_DATA="$DATA_DIR"
  # shellcheck disable=SC1090,SC1091
  . "$DATA_DIR/env.sh"
  run_doctor "$DATA_DIR/bin/clover-hook"

  printf 'clover: installed %s\n' "$PLUGIN_ID"
  printf 'clover: final one-time step: start Codex and choose "Trust all and continue" when it reports 4 new or changed hooks\n'
  printf 'clover: if the prompt does not appear, run /hooks and confirm all 4 Clover hooks are active\n'
  exit 0
fi

SYSTEM_DIR="${CLOVER_CODEX_SYSTEM_DIR:-/opt/clover/codex}"
REQUIREMENTS_FILE="${CLOVER_CODEX_REQUIREMENTS_FILE:-/etc/codex/requirements.toml}"
if [ -e "$REQUIREMENTS_FILE" ] && ! grep -q '^# Clover Codex managed hooks$' "$REQUIREMENTS_FILE"; then
  printf 'clover: refusing to overwrite existing %s\n' "$REQUIREMENTS_FILE" >&2
  printf 'clover: merge codex/managed/requirements.toml.template into your organization requirements instead\n' >&2
  exit 1
fi

STAGE="$TEMP_DIR/runtime"
stage_runtime "$STAGE"
obtain "codex/managed/run-hook.sh" "$STAGE/run-hook.sh"
chmod +x "$STAGE/run-hook.sh"
obtain "codex/managed/requirements.toml.template" "$TEMP_DIR/requirements.toml.template"
sed "s|@CLOVER_CODEX_MANAGED_DIR@|$SYSTEM_DIR|g" "$TEMP_DIR/requirements.toml.template" > "$TEMP_DIR/requirements.toml"
configure_credentials "$(credential_file)"

as_root() {
  if [ "${CLOVER_CODEX_NO_SUDO:-}" = "1" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

as_root install -d -m 755 "$SYSTEM_DIR/bin" "$SYSTEM_DIR/.claude-plugin" "$(dirname "$REQUIREMENTS_FILE")"
as_root install -m 755 "$STAGE/bin/clover-hook" "$SYSTEM_DIR/bin/clover-hook"
as_root install -m 755 "$STAGE/run-hook.sh" "$SYSTEM_DIR/run-hook.sh"
as_root install -m 644 "$STAGE/.claude-plugin/plugin.json" "$SYSTEM_DIR/.claude-plugin/plugin.json"
as_root install -m 644 "$TEMP_DIR/requirements.toml" "$REQUIREMENTS_FILE"

run_doctor "$SYSTEM_DIR/run-hook.sh"
printf 'clover: managed Codex hooks installed in %s\n' "$SYSTEM_DIR"
printf 'clover: hooks are trusted by administrator policy; restart Codex to load them\n'
