# CLAUDE.md

@shared/AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. The shared AGENTS.md above carries the cross-tool operating doctrine; the sections below describe the repo itself.

## Overview

Personal dotfiles for Ubuntu WSL with fish shell on Windows host. Uses Dotbot for symlink management. Also bundles AI coding tool configuration (Claude Code, Codex, OpenCode, Gemini) and a shared skill set.

## Commands

```bash
# Install/update all dotfiles (creates symlinks to home directory)
./install

# Test dotbot config without applying
./dotbot/bin/dotbot -d . -c install.conf.yaml --dry-run
```

## Architecture

**Dotbot** manages symlinks via `install.conf.yaml`:
- Shell/editor/git/WSL utility links (`~/.config/fish/`, `~/.gitconfig`, `~/.vimrc`, …)
- Fish functions directory is symlinked entirely (`fish/functions/` → `~/.config/fish/functions/`)
- AI tool instructions: `shared/AGENTS.md` → `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`, `~/.gemini/GEMINI.md`
- AI tool settings: `claude/`, `codex/`, `opencode/`, `gemini/` configs
- Per-skill symlinks into `~/.claude/skills/` and `~/.codex/skills/` (NOT a directory symlink, so an optional private overlay can contribute its own skills into the same target)

**AI skill layers:** the 24 generic skills in `skills/` are the public layer. A private overlay (`dotfiles-mic/`, optional git submodule) can add domain-specific skills + agents on machines with access to it. The wrapper `./install` script handles both layers — public always, private only if submodule is populated. See the **manage-skills** skill for the two-layer model.

**Fish shell** (`config.fish`):
- MIC k8s functions loaded from `fish/functions/mic/` via `fish_function_path`
- PATH includes: `~/.local/bin`, `~/bin`, nvm, go
- fnm for node version management
- `gh copilot` aliases: `g` (shell), `ghg` (gh), `gitg` (git)

**Git config** uses conditional includes:
- Default: personal (`clemens33`)
- In `~/projects/mic/`: auto-switches to work config (`gitconfig-mic`)

**K8s functions** (prefix conventions):
- `kc*` - kubectl wrappers (e.g., `kcml`, `kcda`)
- `ac*` - ArgoCD wrappers
- `aw*` - Argo Workflows wrappers

Suffixes indicate environment: `ml` (ML dev), `da` (Analytics dev), `et` (EMEA test), `ep` (EMEA prod), `at` (AMER test), `ap` (AMER prod)
