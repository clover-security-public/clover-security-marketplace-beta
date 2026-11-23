# Workspace credentials plugin templates

`codex/scripts/install.sh --workspace` builds the "Clover Kura connection"
plugin from these files: a credentials-only Codex plugin a ChatGPT workspace
admin uploads (admin.openai.com → Marketplaces → Add → Upload plugin) and sets
to Installed. Kura's binary reads its `clover-credentials.json` from the Codex
plugin cache when the environment has no credentials (`ensureCodexCredentials`).

OpenAI's upload validator requires at least one skill and both
`interface.logo` and `interface.composerIcon`, hence the placeholder skill and
the icon. The files are not named as a plugin here (`plugin.json`, not
`.codex-plugin/plugin.json`) so no agent mistakes this folder for one.
