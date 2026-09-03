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
| Gemini CLI | `gemini/settings.json` | `~/.gemini/settings.json` |
| Shared AI doctrine | `shared/AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.gemini/GEMINI.md` |
| AI skills | `skills/<name>/` (24 skills) | `~/.claude/skills/<name>/`, `~/.codex/skills/<name>/` |

## AI operating doctrine

- **`shared/AGENTS.md`** — the contract: rules to never break (auto-loaded by every tool).
- **`WORKFLOW.md`** — triage (S/M/L bucket mandates), anti-patterns, skill cross-reference.
- **`KNOWLEDGE.md`** — field knowledge, source-tiered references (May 2026 snapshot).

See the `manage-skills` skill for the two-layer model — when to add a generic skill here vs. a domain-specific skill in the private overlay.

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
