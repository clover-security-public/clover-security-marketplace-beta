#!/usr/bin/env bash
# Every marketplace entry must carry the metadata a customer reviews before
# installing: a readable name, a category, and a homepage that explains what the
# plugin runs.
#
# Components are deliberately NOT declared on the entry. Claude Code's install
# screen renders its component list from the marketplace entry, but for plugins
# in Anthropic's own catalog the inventory is resolved server-side, which is why
# semgrep shows five hook events while declaring none. Self-hosted marketplaces
# get no resolver, so declaring components here would put us alone in doing it
# (0 of 286 official and 0 of 2282 community entries declare hooks) and it would
# also make the entry, not the plugin's hooks.json, the definition Claude Code
# runs. USAGE.md is our answer to the question instead.
#
# Run from the marketplace tree root: bash tests/marketplace-metadata.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MANIFEST=".claude-plugin/marketplace.json"
FAILED=0

command -v jq >/dev/null || { echo "marketplace-metadata.sh: jq is required" >&2; exit 2; }

for name in $(jq -r '.plugins[].name' "$MANIFEST"); do
  entry=$(jq --arg name "$name" '.plugins[] | select(.name == $name)' "$MANIFEST")

  for field in displayName category homepage; do
    if [ -z "$(jq -r --arg f "$field" '.[$f] // ""' <<<"$entry")" ]; then
      echo "ERROR: $name: marketplace entry has no $field" >&2
      FAILED=1
    fi
  done

  # A declared component would silently become the definition Claude Code runs,
  # overriding the plugin's own file. Keep the entry metadata-only.
  for field in hooks skills commands agents mcpServers lspServers; do
    if [ "$(jq -r --arg f "$field" 'has($f)' <<<"$entry")" = "true" ]; then
      echo "ERROR: $name: entry declares \"$field\" — components belong in the plugin, not the catalog entry" >&2
      FAILED=1
    fi
  done

  # USAGE.md documents what the clover plugin runs, so it is that plugin's
  # homepage and only that one. The other two ship a skill and an MCP server and
  # point at the marketplace README.
  homepage=$(jq -r '.homepage // ""' <<<"$entry")
  case "$name:$homepage" in
    clover:*/blob/main/USAGE.md) ;;
    clover:*) echo "ERROR: clover's homepage must be USAGE.md (got $homepage)" >&2; FAILED=1 ;;
    *:*USAGE.md) echo "ERROR: $name must not point its homepage at USAGE.md — it documents the clover plugin's hooks" >&2; FAILED=1 ;;
  esac

  echo "OK: $name — metadata complete, no component declarations"
done

[ -f USAGE.md ] || { echo "ERROR: USAGE.md is missing — the entries' homepage points at it" >&2; FAILED=1; }

exit "$FAILED"
