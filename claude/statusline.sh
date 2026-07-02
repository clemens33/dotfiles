#!/usr/bin/env bash
# Claude Code status line. Reads session JSON on stdin, prints one footer line.
# Fields: https://docs.claude.com/en/docs/claude-code/statusline
set -euo pipefail

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
effort=$(printf '%s' "$input" | jq -r '.effort.level // ""')
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')

dir=$(basename "$cwd")
branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

line="🧠 ${model}"
[ -n "$effort" ] && line="${line} (${effort})"
line="${line}  📁 ${dir}"
[ -n "$branch" ] && line="${line}  🌿 ${branch}"

printf '%s' "$line"
