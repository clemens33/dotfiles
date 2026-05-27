# dotfiles

Personal dotfiles for Ubuntu WSL2 with fish shell + AI coding tool configuration (Claude Code, Codex CLI, OpenCode, Gemini). Uses [Dotbot](https://github.com/anishathalye/dotbot) for symlink management.

Two-layer setup:

- **Public layer** (this repo): shell/editor/git config, AI tool settings, 24 generic skills, operating doctrine (`shared/AGENTS.md`, `WORKFLOW.md`, `KNOWLEDGE.md`).
- **Private overlay** (`dotfiles-mic/`, optional git submodule): org-specific skills + agents. Only fetched on machines with auth to the private repo.

## Prerequisites

Install these before bootstrapping:

```bash
# Neovim (extracted AppImage — WSL2 has no FUSE)
curl -LO https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.appimage
chmod u+x nvim-linux-x86_64.appimage
./nvim-linux-x86_64.appimage --appimage-extract
mv squashfs-root/usr ~/.local/nvim && rm -rf squashfs-root nvim-linux-x86_64.appimage
ln -sf ~/.local/nvim/bin/nvim ~/.local/bin/nvim

# CLI tools (via nix or apt)
# ripgrep, fd-find (apt: `ln -s $(which fdfind) ~/.local/bin/fd`), fzf, bat, delta, tmux

# WSL clipboard
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

### Nerd Font (Windows side)

LazyVim requires a Nerd Font. Install **JetBrainsMono Nerd Font**:

1. Download from https://github.com/ryanoasis/nerd-fonts/releases — get `JetBrainsMono.zip`
2. Extract and install the `.ttf` files on Windows (right-click → Install for all users)
3. Update Windows Terminal `settings.json` — set the font for your WSL profile:

```json
{
    "guid": "{your-wsl-profile-guid}",
    "font": {
        "face": "JetBrainsMono Nerd Font"
    }
}
```

## What's included

| Config | Source | Symlinks to |
|--------|--------|-------------|
| Fish shell | `config.fish`, `fish/functions/` | `~/.config/fish/` |
| Neovim (LazyVim) | `nvim/` | `~/.config/nvim/` |
| tmux | `tmux.conf` | `~/.tmux.conf` |
| Git | `gitconfig`, `gitconfig-mic` | `~/.gitconfig` |
| Vim (legacy) | `vimrc` | `~/.vimrc` |
| Bash aliases | `bash_aliases` | `~/.bash_aliases` |
| Claude Code config | `claude/settings.json`, `claude/mcpServers.json` | `~/.claude/` |
| Codex CLI config | `codex/config.toml` | `~/.codex/config.toml` |
| OpenCode config | `opencode/config.json` | `~/.config/opencode/config.json` |
| Gemini CLI config | `gemini/settings.json` | `~/.gemini/settings.json` |
| Shared AI doctrine | `shared/AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.gemini/GEMINI.md` |
| AI skills | `skills/<name>/` (24 skills) | `~/.claude/skills/<name>/`, `~/.codex/skills/<name>/` |

### AI operating doctrine

- **`shared/AGENTS.md`** — the contract: rules to never break (auto-loaded by every tool).
- **`WORKFLOW.md`** — triage (S/M/L bucket mandates), anti-patterns, skill cross-reference.
- **`KNOWLEDGE.md`** — field knowledge, source-tiered references (May 2026 snapshot).

### Managing skills

See the `manage-skills` skill for the two-layer model — when to add a generic skill here vs. a domain-specific skill in the private overlay.

### Neovim plugins (beyond LazyVim defaults)

- **darcula-dark** — JetBrains Darcula theme with treesitter support
- **claudecode.nvim** — Claude Code IDE integration (`<leader>a` prefix)
- **diffview.nvim** — interactive git diff viewer (`<leader>gd`)
- **copilot.lua** — GitHub Copilot inline completion
- **basedpyright** — Python LSP (via LazyVim Python extra)
- **ruff** — Python formatting/linting

## Git config

Uses conditional includes — auto-switches to work config (`gitconfig-mic`) when in `~/projects/mic/`. Delta is configured as the git pager with side-by-side diffs.
