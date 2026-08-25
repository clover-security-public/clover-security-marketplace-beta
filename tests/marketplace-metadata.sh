#!/usr/bin/env bash
# Marketplace entries must carry the metadata a customer reviews before
# installing, and the components they declare must be exactly what the plugin
# ships.
#
# Why declare components at all: Claude Code renders the install screen's
# "Will install" list from the marketplace ENTRY — it has not cloned the plugin
# yet. Only Anthropic's own curated catalog gets that list resolved server-side
# (the same plugin listed in claude-community shows "Component summary not
# available for remote plugin" while its claude-plugins-official listing lists
# every skill), and the official catalog has no application process. For a
# self-hosted marketplace the entry is the only input, so declaring here is the
# only way a customer sees the hooks before installing.
#
# Why it has to match: where an entry and the plugin's own hooks.json both
# define hooks for an event, the ENTRY wins (verified on Claude Code 2.1.239,
# .240, .241 — one fire, the entry's command). A drifted entry would therefore
# change what actually runs as well as mislead the install screen. Byte-equality
# also means a future CLI that merges instead of overriding is a no-op for us.
#
# Run from the marketplace tree root: bash tests/marketplace-metadata.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

MANIFEST=".claude-plugin/marketplace.json"
FAILED=0

command -v jq >/dev/null || { echo "marketplace-metadata.sh: jq is required" >&2; exit 2; }

# The clover plugin is the repo root, so its hooks file sits under claude/;
# every other plugin owns its own directory.
hooks_file_for() { case "$1" in clover) echo "claude/hooks/hooks.json" ;; *) echo "$1/hooks/hooks.json" ;; esac; }
plugin_root_for() { case "$1" in clover) echo "." ;; *) echo "$1" ;; esac; }

for name in $(jq -r '.plugins[].name' "$MANIFEST"); do
  entry=$(jq --arg name "$name" '.plugins[] | select(.name == $name)' "$MANIFEST")
  root=$(plugin_root_for "$name")
  hooks_file=$(hooks_file_for "$name")

  # --- metadata ---------------------------------------------------------------
  for field in displayName category homepage; do
    if [ -z "$(jq -r --arg f "$field" '.[$f] // ""' <<<"$entry")" ]; then
      echo "ERROR: $name: marketplace entry has no $field" >&2
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

  # --- hooks: declared, and identical to what the plugin ships -----------------
  if [ "$(jq -r 'has("hooks")' <<<"$entry")" != "true" ]; then
    echo "ERROR: $name: entry declares no \"hooks\" — the install screen would show no inventory. Mirror $hooks_file into the entry." >&2
    FAILED=1
  elif [ ! -f "$hooks_file" ]; then
    echo "ERROR: $name: entry declares hooks but $hooks_file does not exist" >&2
    FAILED=1
  else
    declared=$(jq -S '.hooks' <<<"$entry")
    shipped=$(jq -S '.hooks' "$hooks_file")
    if [ "$declared" != "$shipped" ]; then
      echo "ERROR: $name: entry hooks differ from $hooks_file — the entry wins at runtime, so this changes behaviour AND misleads the install screen" >&2
      diff <(echo "$shipped") <(echo "$declared") >&2 || true
      FAILED=1
    fi
  fi

  # --- skills: every declared path exists -------------------------------------
  while IFS= read -r skill; do
    [ -n "$skill" ] || continue
    if [ ! -f "$root/${skill#./}/SKILL.md" ]; then
      echo "ERROR: $name: declared skill $skill has no SKILL.md under $root" >&2
      FAILED=1
    fi
  done < <(jq -r '(.skills // []) | .[]' <<<"$entry")

  # --- mcpServers: the entry repeats the plugin's own path, never a copy -------
  # Claude's MCP resolution here is deliberately delicate (see the shared
  # Claude/Cursor directory checks in validate.yml): the manifest-declared
  # claude-mcp.json is what overrides the root .mcp.json down to a single
  # registered server. The entry repeats that path rather than inlining the
  # server, so the install screen gets a row without a third declaration
  # entering the merge.
  entry_mcp=$(jq -r '.mcpServers // ""' <<<"$entry")
  manifest_mcp=$(jq -r '.mcpServers // ""' "$root/.claude-plugin/plugin.json")
  if [ -n "$manifest_mcp" ] && [ "$entry_mcp" != "$manifest_mcp" ]; then
    echo "ERROR: $name: entry mcpServers ($entry_mcp) must repeat the plugin manifest's path ($manifest_mcp)" >&2
    FAILED=1
  fi
  if [ -n "$entry_mcp" ] && [ ! -f "$root/${entry_mcp#./}" ]; then
    echo "ERROR: $name: entry mcpServers points at $entry_mcp, which does not exist under $root" >&2
    FAILED=1
  fi

  echo "OK: $name — metadata complete, hooks match $hooks_file"
done

[ -f USAGE.md ] || { echo "ERROR: USAGE.md is missing — the clover entry's homepage points at it" >&2; FAILED=1; }

exit "$FAILED"
