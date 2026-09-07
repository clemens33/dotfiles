#!/usr/bin/env bash
# Claude Code status line. Reads session JSON on stdin, prints one footer line.
# Fields: https://code.claude.com/docs/en/statusline
set -euo pipefail

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
effort=$(printf '%s' "$input" | jq -r '.effort.level // ""')
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')
context=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty | floor')
cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')
cache=$(printf '%s' "$input" | jq -r '
  .prompt_cache // empty |
  if .warm == true then "warm"
  elif .warm == false then "cold"
  else empty end')

dir=$(basename "$cwd")
branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

line="🧠 ${model}"
[ -n "$effort" ] && line="${line} (${effort})"
line="${line}  📁 ${dir}"
[ -n "$branch" ] && line="${line}  🌿 ${branch}"
[ -n "$context" ] && line="${line}  ctx ${context}%"
[ -n "$cost" ] && line="${line}  $(LC_NUMERIC=C printf '$%.2f' "$cost")"
[ -n "$cache" ] && line="${line}  cache ${cache}"

printf '%s' "$line"
