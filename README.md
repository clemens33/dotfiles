# dotfiles

Personal dotfiles for Ubuntu WSL2 with fish shell + AI coding tool configuration (Claude Code, Codex CLI, OpenCode, Gemini). Uses [Dotbot](https://github.com/anishathalye/dotbot) for symlink management.

Two-layer setup:

- **Public layer** (this repo): shell/editor/git config, AI tool settings, 24 generic skills, operating doctrine (`shared/AGENTS.md`, `WORKFLOW.md`, `KNOWLEDGE.md`).
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
| OpenDesign | `open-design/compose.yaml`, `bin/open-design` | `~/.config/open-design/compose.yaml`, `~/.local/bin/open-design{,-mcp}` |
| Shared AI doctrine | `shared/AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.gemini/config/plugins/dotfiles/rules/AGENTS.md` |
| AI skills | `skills/<name>/` | `~/.claude/skills/<name>/`, `~/.agents/skills/<name>/` |

## AI operating doctrine

- **`shared/AGENTS.md`** — the contract: rules to never break (auto-loaded by every tool).
- **`WORKFLOW.md`** — triage (S/M/L bucket mandates), anti-patterns, skill cross-reference.
- **`KNOWLEDGE.md`** — field knowledge, source-tiered references (May 2026 snapshot).

See the `manage-skills` skill for the two-layer model — when to add a generic skill here vs. a domain-specific skill in the private overlay.

## OpenDesign

The public install wires a persistent local [OpenDesign](https://github.com/nexu-io/open-design)
daemon and web UI. It pulls no image and starts no container. Install and start
it explicitly:

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
open-design start       # create/start and wait until healthy
open-design stop        # stop; keep container and data
open-design restart     # recreate and wait until healthy
open-design status
open-design logs --tail 100
open-design health
open-design version
open-design down        # remove container/network; keep data volume
```

Release `0.21.1` is pinned by immutable multi-architecture index digest
`sha256:441daca881e699657bacf28e0c27b16cd6be551dfff4bd63368dd74bec581f39`.
It is deliberately outside `scripts/harness-update.sh`. To update or roll back,
change the digest in `open-design/compose.yaml`, then run
`open-design pull && open-design restart`. The persistent Docker volume is
`open-design_open_design_data`. `open-design down` never removes it. Full data
deletion is intentionally not wrapped; after separately confirming data loss,
stop the stack and explicitly remove that exact volume with
`docker volume rm open-design_open_design_data`.

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
rerunning `./install` alone cannot retire an old server. Keep or explicitly
remove the named volume according to the data-retention choice above.

## Automatic harness updates

`scripts/harness-update.sh` updates installed Claude Code, Codex, Antigravity
(`agy`), Grok, and OpenCode CLIs. Each tool is isolated: one failed update does
not skip the rest. It runs daily at 06:30 local time and writes dated logs to
`~/.local/state/harness-update/` (last 14 retained).

```bash
# Inspect current and latest versions without changing anything
scripts/harness-update.sh --check

# Update everything installed, or one tool
scripts/harness-update.sh
scripts/harness-update.sh --only codex
```

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
