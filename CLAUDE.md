# CLAUDE.md

The contract loads via `~/.claude/CLAUDE.md`.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. The sections below describe the repo itself.

## Overview

Personal dotfiles for Ubuntu WSL (Windows host) and macOS (Apple Silicon), fish shell on both. Uses Dotbot for symlink management. Also bundles AI coding tool configuration (Claude Code, Codex, OpenCode, Gemini) and a shared skill set. macOS package manifest lives in `macos/Brewfile`; migration playbook in `~/MAC-MIGRATION.md`.

## Commands

```bash
# Install/update all dotfiles (creates symlinks to home directory)
./install

# Test dotbot config without applying
./dotbot/bin/dotbot -d . -c install.conf.yaml --dry-run

# macOS only: install/update the host toolchain
brew bundle --file macos/Brewfile
```

## Architecture

**Dotbot** manages symlinks via `install.conf.yaml`:
- Shell/editor/git/WSL utility links (`~/.config/fish/`, `~/.gitconfig`, `~/.vimrc`, …)
- Fish functions directory is symlinked entirely (`fish/functions/` → `~/.config/fish/functions/`)
- AI tool instructions: `shared/AGENTS.md` → `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.gemini/config/plugins/dotfiles/rules/AGENTS.md`; Grok gets a short `grok/AGENTS.md` pointer → `~/.grok/AGENTS.md` (10k-char rules cap) and loads the full contract via its Claude-compat reading of `~/.claude/CLAUDE.md`
- AI tool settings: `claude/`, `codex/`, `opencode/`, `antigravity/`, `grok/` configs (Grok reads `~/.claude/skills/`, `~/.claude/agents/`, and `~/.claude/settings.json` permissions natively — no per-skill symlinks needed). Gemini CLI was retired by Google 2026-06-18; Antigravity CLI (`agy`) replaces it: rules/skills under `~/.gemini/config/`, settings and runtime state under `~/.gemini/antigravity-cli/`
- Per-skill symlinks into `~/.claude/skills/` and `~/.agents/skills/` for Codex (NOT a directory symlink, so an optional private overlay can contribute its own skills into the same target); Antigravity's `~/.gemini/config/skills` links to `~/.claude/skills`

**AI skill layers:** the generic skills in `skills/` are the public layer. A private overlay (`dotfiles-mic/`, optional git submodule) can add domain-specific skills + agents on machines with access to it. The wrapper `./install` script handles both layers — public always, private only if submodule is populated. See the **manage-skills** skill for the two-layer model.

**Fish shell** (`config.fish`):
- PATH includes: `~/.local/bin`, `~/bin`, nvm, go
- fnm for node version management
- `gh copilot` aliases: `g` (shell), `ghg` (gh), `gitg` (git)
- Loads `~/.config/fish/functions-mic/` when present (provided by the private overlay)

**Git config** uses conditional includes:
- Default: personal (`clemens33`)
- `[includeIf "gitdir:~/projects/mic/"]` references `~/.gitconfig-mic`, installed only when the private overlay is present. Silently no-op without overlay.
