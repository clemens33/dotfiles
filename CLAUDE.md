# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles for Ubuntu WSL with fish shell on Windows host. Uses Dotbot for symlink management.

## Commands

```bash
# Install/update all dotfiles (creates symlinks to home directory)
./install

# Test dotbot config without applying
./dotbot/bin/dotbot -d . -c install.conf.yaml --dry-run
```

## Architecture

**Dotbot** manages symlinks via `install.conf.yaml`:
- Links configs to `~/.config/fish/`, `~/.gitconfig`, `~/.vimrc`, etc.
- Fish functions directory is symlinked entirely (`fish/functions/` → `~/.config/fish/functions/`)

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
