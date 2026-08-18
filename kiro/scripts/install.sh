#!/usr/bin/env bash
# Install the Clover Kiro drop-in into a repository.
#
#   bash kiro/scripts/install.sh /path/to/repo
#
# Kiro loads hooks from the workspace, not from an installed plugin, so the
# surface is copied into <repo>/.kiro/. Credentials are not written - create
# <repo>/.kiro/clover/env.sh afterwards (see README).
set -euo pipefail

TARGET="${1:-}"

if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
  printf 'usage: bash kiro/scripts/install.sh /path/to/repo\n' >&2
  exit 1
fi

SURFACE="$(cd "$(dirname "$0")/.." && pwd)"       # .../kiro
PACKAGE="$(cd "$SURFACE/.." && pwd)"              # the assembled plugin tree

DEST="$TARGET/.kiro"
mkdir -p "$DEST/hooks" "$DEST/clover/scripts" "$DEST/clover/bin"

cp "$SURFACE/hooks/clover.json" "$DEST/hooks/clover.json"
printf 'installed hooks\n'

cp "$SURFACE/scripts/run-hook.sh" "$DEST/clover/scripts/"
chmod +x "$DEST/clover/scripts/run-hook.sh"

if ! cp "$PACKAGE/bin/"clover-hook-* "$DEST/clover/bin/" 2>/dev/null; then
  printf 'warning: no binaries at %s/bin - copy clover-hook-<os>-<arch> into %s/clover/bin/\n' \
    "$PACKAGE" "$DEST" >&2
fi
chmod +x "$DEST/clover/bin/"* 2>/dev/null || true

if ! grep -qs 'clover/env.sh' "$TARGET/.gitignore" 2>/dev/null; then
  printf '\n# Clover credentials - never commit\n.kiro/clover/env.sh\n' >> "$TARGET/.gitignore"
fi

cat <<EOF

Installed into $TARGET

Next:
  1. Create $DEST/clover/env.sh:
       export CAS_CLOVER_PLUGIN_CLIENT_ID=...
       export CAS_CLOVER_PLUGIN_CLIENT_SECRET=...
       export CAS_CLOVER_PLUGIN_AUTH_URL=https://clover.frontegg.com
       export CAS_CLOVER_PLUGIN_SERVER_URL=https://app.cloversec.io
  2. Open $TARGET in Kiro and TRUST the workspace.
     An untrusted workspace silently disables every hook.
  3. Confirm: Output panel -> Kiro agent channel ->
     "v2 hooks loaded 3 standalone hooks from .kiro/hooks/"
EOF
