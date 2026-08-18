# Clover for Kiro

Clover security review inside [Kiro](https://kiro.dev), AWS's spec-driven
agentic IDE (and the Kiro CLI). Same binary and same `/Hooks/*` backend as the
Claude Code and Cursor surfaces — only the event plumbing differs, and it lives
in `cmd/clover-hook/agent_kiro.go`, not in these scripts.

## Why Kiro fits

Kiro writes its plan to disk as a **spec** —
`.kiro/specs/<feature>/{requirements,bugfix,design,tasks}.md` — and runs tasks
from it, firing a **blocking `PreTaskExec`** immediately before implementation.
That gives Clover a real plan artifact plus the closest analogue to Claude's
`ExitPlanMode` gate on any non-Claude agent.

| Trigger | Subcommand | Blocks |
|---|---|---|
| `UserPromptSubmit` | `kiro-log-prompt` | no |
| `PostFileSave` on `.kiro/specs/**/*.md` | `kiro-capture-spec` | no |
| `PreTaskExec` | `kiro-pre-task` | **yes** |

Kiro's decision contract is the exit code, not JSON: exit 0 proceeds (stdout is
appended to the model's context), a non-zero exit blocks and hands **stderr** to
the model. There is no "allow" to emit, so the "decision only when blocking"
invariant holds by silence. Because *any* non-zero exit blocks, every error path
exits 0.

## Install

Kiro loads hooks from the workspace rather than from an installed plugin, so the
surface is copied into the repository:

```bash
bash kiro/scripts/install.sh /path/to/repo
```

That writes:

```
<repo>/.kiro/
  hooks/clover.json              # the three hooks above
  clover/
    scripts/run-hook.sh          # resolves the platform binary, loads env.sh, exec
    bin/clover-hook-<os>-<arch>
    env.sh                       # credentials — you create this, gitignored
```

Then create `<repo>/.kiro/clover/env.sh` with the four `CAS_CLOVER_PLUGIN_*`
values, open the repo in Kiro, and **trust the workspace** — an untrusted
workspace silently turns every hook into a no-op, logged only at debug level.

Confirm with the Output panel → Kiro agent channel:
`[KiroAgent] v2 hooks loaded 3 standalone hooks from .kiro/hooks/`.

## When a new Kiro build changes its payload

Field naming has changed between builds and `PreTaskExec`'s shape is
undocumented, so the adapter accepts every spelling seen so far (`file_path`,
`filePath`, `path`, `spec_path`, `specPath`, `tool_input.specPath`) and falls
back to the most recently modified spec directory when an event names none. A
rename is therefore additive rather than breaking.

To see what a new build actually sends, run with `CLOVER_DEBUG=1` and read the
diagnostics log — the adapter records the event name and the spec it resolved.

## Known constraints

- **The IDE delivers an empty `prompt`**
  ([kirodotdev/Kiro#7500](https://github.com/kirodotdev/Kiro/issues/7500)), so
  prompt audit is a no-op there and posts nothing rather than a blank row; the
  CLI delivers the real text. Spec review is unaffected — the plan is read from
  disk.
- **Kiro does not close the hook's stdin.** A read to EOF hangs the turn until
  the hook times out, so Kiro's subcommands set `readsOneJSONValue` and stop at
  the end of the payload.
- **Every hook renders a chat card.** Kiro emits it at the engine level before
  the command runs; no setting or schema field suppresses it. All hooks are
  named `Clover Security`, the command and its output are never rendered, and
  the card collapses to a one-line summary when the turn ends.
- **Spec tasks can run concurrently**, so `PreTaskExec` may fire in parallel.
  The approved-plan-hash short-circuit in `runPlanReview` dedupes the common
  case.
- **`CodingAgentType` has no `Kiro` member** in Leaf yet, and the endpoints
  reject an unknown enum string, so activity is recorded as `Other`. Set
  `CLOVER_KIRO_CODING_AGENT=Kiro` (or change `kiroDefaultCodingAgent`) in the
  same release that adds the enum value.
- **Powers cannot carry hooks.** Kiro's power installer copies only `POWER.md`,
  `mcp.json` and `steering/`. A Clover *power* can ship steering and an MCP
  server; the hooks ship as this drop-in.

## Debugging

`CLOVER_DEBUG=1` in `env.sh` for diagnostics, `CLOVER_KIRO_OBSERVE=1` to
downgrade the `PreTaskExec` gate to observe-only during a staged rollout, and
`CLOVER_HOOK_BIN` to point at a locally built binary.
