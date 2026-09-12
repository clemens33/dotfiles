# dotfiles

Personal dotfiles for Ubuntu WSL2 with fish shell + AI coding tool configuration (Claude Code, Codex CLI, OpenCode, Gemini). Uses [Dotbot](https://github.com/anishathalye/dotbot) for symlink management.

Two-layer setup:

- **Public layer** (this repo): shell/editor/git config, AI tool settings, the generic skills, operating doctrine (`shared/AGENTS.md`, `WORKFLOW.md`, `KNOWLEDGE.md`).
- **Private overlay** (`dotfiles-mic/`, optional git submodule): org-specific skills + agents + private git/shell config. Only fetched on machines with auth to the private repo.

## Prerequisites

```bash
# CLI tools (apt or nix): ripgrep, fd-find, fzf, bat, delta, tmux, jq

# WSL clipboard helper
curl -sLo /tmp/win32yank.zip https://github.com/equalsraf/win32yank/releases/download/v0.1.1/win32yank-x64.zip
cd /tmp && unzip -o win32yank.zip win32yank.exe && chmod +x win32yank.exe && mv win32yank.exe ~/.local/bin/
```

## Bootstrap

Public install — no private overlay:

```bash
git clone https://github.com/clemens33/dotfiles.git ~/projects/clemens33/dotfiles
cd ~/projects/clemens33/dotfiles
./install
```

The install script initializes only the public `dotbot` submodule. The private `dotfiles-mic` submodule is **not** auto-initialized — public clones work without auth to the private repo.

### Optional: enable the private overlay

If you have access to the private `dotfiles-mic` repo:

```bash
cd ~/projects/clemens33/dotfiles
git submodule update --init dotfiles-mic
./install
```

The wrapper install script detects the overlay submodule and runs its Dotbot pass automatically when present.

## What's included

| Config | Source | Symlinks to |
|---|---|---|
| Fish shell | `config.fish`, `fish/functions/` | `~/.config/fish/` |
| tmux | `tmux.conf` | `~/.tmux.conf` |
| Git | `gitconfig` | `~/.gitconfig` |
| Vim | `vimrc` | `~/.vimrc` |
| Bash aliases | `bash_aliases` | `~/.bash_aliases` |
| Claude Code | `claude/settings.json`, `claude/mcpServers.json` | `~/.claude/` |
| Codex CLI | `codex/config.toml` | `~/.codex/config.toml` |
| OpenCode | `opencode/config.json` | `~/.config/opencode/config.json` |
| Antigravity CLI (`agy`) | `antigravity/settings.json` | `~/.gemini/antigravity-cli/settings.json` |
| OpenDesign | `open-design/compose.yaml`, `open-design/Dockerfile`, `bin/open-design` | `~/.config/open-design/compose.yaml`, `~/.config/open-design/Dockerfile`, `~/.local/bin/open-design{,-mcp}` |
| DeepSeek Harness (`dsh`, pilot) | `deepseek-harness/` | `~/.local/bin/dsh`; the patch layers, the `dsh-tui` profile and the agent preset are managed **copies** under `~/.dsh`, not links |
| AI skills | `skills/<name>/` | `~/.claude/skills/<name>/`, `~/.agents/skills/<name>/` |

The AI contract is the one exception: it is **rendered**, not symlinked. See
[How the contract reaches each tool](#how-the-contract-reaches-each-tool).

## AI operating doctrine

- **`shared/AGENTS.md`** — the contract: rules to never break (auto-loaded by every tool).
- **`WORKFLOW.md`** — triage (S/M/L bucket mandates), anti-patterns, skill cross-reference.
- **`KNOWLEDGE.md`** — field knowledge, source-tiered references (May 2026 snapshot).

See the `manage-skills` skill for the two-layer model — when to add a generic skill here vs. a domain-specific skill in the private overlay.

### How the contract reaches each tool

`scripts/render-contract.sh` concatenates `shared/AGENTS.md` with the private
overlay's `dotfiles-mic/AGENTS-MIC.md`, when that submodule is checked out, and
writes the result as a **regular file** into every harness identity:

```
~/.claude/CLAUDE.md                                ~/.codex/AGENTS.md
~/.claude2/CLAUDE.md                               ~/.config/opencode/AGENTS.md
~/.claude-mic/CLAUDE.md                            ~/.gemini/config/plugins/dotfiles/rules/AGENTS.md
~/.dsh/AGENTS.md
```

`./install` runs the renderer; nothing links to `shared/AGENTS.md` any more. The
renderer creates no identity of its own — it skips any whose directory is
missing. `./install` is what provisions them: the public pass creates
`~/.claude2` and `~/.dsh`, the private overlay's pass creates `~/.claude-mic`. So
a public-only clone has no `~/.claude-mic`, and the renderer simply skips it —
as it does for `~/.dsh` on a machine where the DeepSeek Harness pilot has been
rolled back.

Concatenation rather than a second file, because it is the only portable
option. Measured 2026-09-09: of the five harnesses, only Claude Code reads an
instruction file one level *above* a git root, and only under the name
`CLAUDE.md`; Codex, Grok, `agy` and OpenCode read nothing above the repo root.
Directory-scoped org rules therefore cannot be made to work everywhere, so the
org half ships inside the file each tool already loads.

- **Regenerate**: `./install`, or `scripts/render-contract.sh` on its own. The
  private overlay's Dotbot pass runs the renderer a second time on purpose:
  `~/.claude-mic` is created *in* that pass, so only the second call can reach
  it. Do not "tidy" that duplicate away — a clean machine would then need two
  `./install` runs. Re-rendering the other five targets is a no-op.
- **Check for drift**: `scripts/render-contract.sh --check` lists stale targets,
  exits 1, and writes nothing. The daily harness updater runs it as its
  `contract` step and only reports — it never re-renders behind your back.
- **Never edit a target.** Each one opens with a generated-file header; edits
  are lost on the next install. Edit the source, then re-run `./install`.
- **Without the private overlay** the render is public-only. A public clone
  installs and works with no missing pieces.
- **Grok is unchanged**: `grok/AGENTS.md` → `~/.grok/AGENTS.md` stays a symlink
  because of grok's 10k-char rules cap, and grok picks the full contract up
  through its Claude-compatible read of `~/.claude/CLAUDE.md`.

## OpenDesign

The public install wires a persistent local [OpenDesign](https://github.com/nexu-io/open-design)
daemon and web UI. It builds no image and starts no container. Install and start
it explicitly — `open-design install` builds the local image first, so a clean
machine never starts against a missing one:

```bash
./install
open-design install
open-design open
```

Open `http://127.0.0.1:7456`. This trusted local setup disables OpenDesign's API
authentication and binds the published port strictly to `127.0.0.1`; it is not
reachable on the LAN. Do not change the bind address without restoring
authentication and TLS in front of the service.

Common operations:

```bash
open-design build       # build the local image from the pinned base digest
open-design start       # create/start and wait until healthy
open-design stop        # stop; keep container and data
open-design restart     # recreate and wait until healthy
open-design status
open-design logs --tail 100
open-design health
open-design version
open-design down        # remove container/network; keep both named volumes
```

### Installing a design-system package

`sync-package` installs a finished OpenDesign design-system package — a
directory holding `manifest.json`, `DESIGN.md` and `tokens.css` — into the
daemon's persistent storage:

```bash
open-design sync-package /path/to/package
open-design cli design-systems show user:<id>
```

The command is generic: the id, and everything else about the package, comes
from its `manifest.json`. It streams the directory into the container (no repo
is ever mounted), places it under `/app/.od/design-system-sources/<id>`, and on
the first run asks OpenDesign's own local-install API to add it to the catalog.
Later runs replace the files in place, so the catalog entry and its id survive.

It only ever touches a package it installed itself. A source directory without
its marker file, or a catalog entry pointing somewhere else, is refused rather
than overwritten. If the transfer, the install call, or the post-install
validation fails, the previous package is moved back and the catalog entry this
run created is removed.

This is a **pinned-version compatibility surface**. The package format belongs
to the OpenDesign release named above, not to a stable interchange standard:
`manifest.json` is validated against that release's
`design-systems/_schema/manifest.schema.ts`. When the pinned digest moves,
re-validate a package before trusting a sync.

`import-design-system` is a different thing and stays as it was: it runs
OpenDesign's own importer, which scans a source tree and emits its own canonical
package. Use it for a foreign project; use `sync-package` when you already have
a package you want installed verbatim.

### Image, updates, and data

The container image is a thin local derivative, `open-design-vela:0.21.1-vela0.0.33`,
built by `open-design/Dockerfile` from release `0.21.1` pinned by immutable
multi-architecture index digest
`sha256:441daca881e699657bacf28e0c27b16cd6be551dfff4bd63368dd74bec581f39`.
The Dockerfile is COPY-free and builds with no build context at all: a Docker
build context cannot follow the Dotbot symlink that installs it, and widening
the context to this checkout would ship the whole repo to the daemon.

It is deliberately outside `scripts/harness-update.sh`. To update or roll back,
change the `FROM` digest in `open-design/Dockerfile`, then run
`open-design build && open-design restart`. Nothing is pulled by tag and no
lifecycle command rebuilds, so the running image only ever changes when you
build it.

Two named Docker volumes hold all state and both survive `open-design down`:

| Volume | Holds |
|---|---|
| `open-design_open_design_data` | Projects, artifacts, design systems (`/app/.od`) |
| `open-design_open_design_vela_data` | The container home, including the Vela sign-in (`/home/open-design`) |

Full data deletion is intentionally not wrapped. After separately confirming
data loss, stop the stack and explicitly remove the exact volume you mean, e.g.
`docker volume rm open-design_open_design_data`. Sign out in the UI before
deleting the Vela volume — see below.

### Vela sign-in

Upstream's published image ships the daemon but never bundles the Vela CLI, so
on the official image the UI's **Sign in to OpenDesign** fails with
`vela binary not found; install vela or configure VELA_BIN`
(nexu-io/open-design issue #5700; Docker/Compose is only partially supported
upstream). `open-design/Dockerfile` is the local answer: it adds Alpine
`gcompat` plus the exact `@powerformer/vela-cli` 0.0.33 that tag 0.21.1 pins,
and fails the build if `vela --version` is not `0.0.33`.

Signing in is still a human device activation. OpenDesign prints an activation
URL and user code; opening the link and approving it happens on your own device,
and nothing in this repo logs in for you. The container is headless, so its own
attempt to open a browser fails by design — use the URL the UI shows.

The resulting session is a bearer credential on disk in the container home —
the daemon reports its config at `/home/open-design/.amr/config.json` — inside
`open-design_open_design_vela_data`. Treat that volume as secret material: do
not export, back up, or copy it, and do not move it between machines.
`open-design down` deliberately leaves the authenticated session in place so a
restart does not force a new sign-in. When retiring it, sign out in the UI
first, then remove the volume explicitly.

Import one local design-system package without mounting a repository or home
directory:

```bash
open-design import-design-system ./path/to/brand --name "Brand" --json
```

The wrapper streams only that directory to a unique container `/tmp` path,
imports it in `hybrid` mode, then removes the exact temporary path. A current
package centers on `DESIGN.md` and can add `manifest.json`, compiled
`tokens.css`, component fixtures, assets, and provenance/evidence. Legacy
directories containing only `DESIGN.md` remain compatible.

`open-design-mcp` is registered as a managed stdio MCP server for Claude Code,
Codex, OpenCode, and Grok. ae-launched seats inherit their underlying harness's
same user configuration; ae needs no separate MCP entry. Antigravity (`agy`)
currently ignores the managed settings file's `mcpServers` block. Register it
machine-locally with `agy mcp add open-design open-design-mcp`; clean-install
registration remains a known gap.
OpenDesign 0.21.1 does not support Docker/Compose MCP snippets or shared HTTP
transport upstream, so this setup uses a locally tested `docker exec -i` stdio
compatibility bridge. Muse Code 1.0.3 exposes no MCP client configuration and is
not integrated.

Direction matters: a host harness can call OpenDesign's MCP to read projects and
write artifacts. The isolated container cannot launch host Claude/Codex/OpenCode
binaries. Generation initiated in the OpenDesign UI therefore needs its own BYOK
provider configured in OpenDesign; host subscriptions and credentials are not
mounted or copied into it.

To uninstall, run `open-design down`, revert the managed config entries and
links, and remove `open-design` explicitly from every existing Claude identity
state file (`~/.claude.json`, `~/.claude2/.claude.json`, and
`~/.claude-mic/.claude.json` when present). The Claude merge is additive, so
rerunning `./install` alone cannot retire an old server. Sign out in the UI
before retiring the Vela volume, then keep or explicitly remove each named
volume according to the data-retention choice above.

## DeepSeek Harness pilot

A pinned, local-only pilot of DeepSeek Harness (`dsh`), kept deliberately
separate from the daily toolchain: OpenCode with GLM 5.3 Flash stays the
default, and the pilot has no ae profile and no autostart.

```bash
dsh                      # interactive terminal harness
dsh headless "run the tests"
dsh web                  # browser surface, only when named
```

Plain `dsh` enters the managed terminal profile. `dsh web` is the browser
surface and is never selected implicitly; every official launcher form
(`--profile`, `plugin`, `--help`, `--version`) passes through untouched, and an
unrecognised first token fails with usage rather than guessing a surface.

The terminal surface is **community code**: the official release ships no
first-party TUI, so `@deepseek-harness-tui/dsh-tui` is composed over the
official runtime at an exact pinned version. It holds full agent-host authority,
and the standing boundary is that it never points at MIC or customer code.

It is a developer preview that promises breaking changes, so the release
candidate is pinned by `deepseek-harness/package-lock.json` and
`scripts/harness-update.sh` only ever reports on it. The four shared MCP servers
reach it through a managed agent preset rather than a profile patch, because
both surfaces expose model-facing tools only from a preset. The preset, the
three patch layers, and the terminal profile are installed as copies rather than
symlinks, so nothing the harness writes can reach back into this repo. Setup,
why the profile installer is a separately pinned pnpm, the lifecycle-script
policy, the copied-preset drift check, and rollback are all in
[`deepseek-harness/README.md`](deepseek-harness/README.md).

## Automatic harness updates

`scripts/harness-update.sh` updates installed Claude Code, Codex, Antigravity
(`agy`), Grok, and OpenCode CLIs, and reports on the pinned DeepSeek Harness
pilot without ever upgrading it. Each tool is isolated: one failed update does
not skip the rest. It runs daily at 06:30 local time and writes dated logs to
`~/.local/state/harness-update/` (last 14 retained).

```bash
# Inspect current and latest versions without changing anything
scripts/harness-update.sh --check

# Update everything installed, or one tool
scripts/harness-update.sh
scripts/harness-update.sh --only codex

# Report instruction files that drifted from the rendered contract
scripts/harness-update.sh --only contract

# Report the pinned DeepSeek Harness pilot: version, lock, preset drift, MCP
scripts/harness-update.sh --only dsh --check
```

`contract` is a step, not a CLI: it runs `render-contract.sh --check` and names
any target that no longer matches. It never renders — `./install` does that.

`ae` is excluded by default because session glue is version-pinned. Its
checksum-verified upgrader remains opt-in and requires an explicit calver:

```bash
AE_VERSION=YYYY.M.D scripts/harness-update.sh --include-ae
```

On macOS, `./install` links and loads the launch agent. Reload or unload it with:

```bash
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/at.clemens.harness-update.plist"
launchctl bootout gui/$(id -u)/at.clemens.harness-update
```

On Linux with systemd, `./install` links and enables the user timer. WSL
installations without systemd skip it.

```bash
systemctl --user daemon-reload
systemctl --user enable --now harness-update.timer
```

Native installers replace versioned files atomically, so already-running CLI
processes keep their old executable until restarted. On macOS, OpenCode is
updated in the mise-managed Node LTS global; Linux also supports the default
fnm/nvm Node alias. Switching Node versions leaves that global install behind
and requires reinstalling it for the new version.
