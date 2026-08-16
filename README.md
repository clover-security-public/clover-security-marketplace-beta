# clover-security-marketplace-beta

Org-only **beta channel** of the Clover plugin marketplace — a private mirror of the public
marketplace (`agentic-security-marketplace`), carrying beta versions of every plugin it lists.
The whole Clover org rides this channel so builds soak here before customers ever see them.

## How content gets here

- **Automatically**, on every push to `main` in
  [`clover-hook-source`](https://github.com/clover-security-public/clover-hook-source): CI builds
  the hook binaries, assembles the channel-stamped plugin tree, and pushes it here.
- **By hand**, for quick plugin-file experiments (new hooks, skills, scripts) — direct pushes to
  `main` are allowed. Durable changes belong in `clover-hook-source`, since the next automatic
  delivery overwrites this tree.

Customers are never served from this repo. The public marketplace moves only via the manual
**Promote to public marketplaces** workflow in `clover-hook-source`.

## Installing the beta channel

Requires read access to this private repo with your own GitHub identity (`gh auth login`).
The org's managed settings carry the marketplace registration, plugin enablement, and config.
