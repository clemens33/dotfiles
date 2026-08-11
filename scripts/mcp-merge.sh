#!/usr/bin/env bash
# Merge the base MCP server set into a Claude Code state file.
#
# Usage: mcp-merge.sh <path/to/.claude.json> <path/to/mcpServers.json>
#
# .claude.json holds runtime state (onboarding flags, per-project MCP approvals)
# and is rewritten by Claude Code via write-then-rename, so it can NOT be a
# symlink — hence merge instead of link.
#
# The merge is ADDITIVE with repo keys winning: `(existing + repo)`. It is
# therefore order-independent — a later pass (e.g. the private overlay's
# gateway injection) is not clobbered by this one, and re-running ./install in
# any order converges. CAVEAT: deleting a server from mcpServers.json does not
# remove it from an existing .claude.json — do that with `claude mcp remove`.
set -euo pipefail

target="$1"
servers="$2"

if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found, skipping MCP merge for $target"
    exit 0
fi

if [ ! -f "$servers" ]; then
    echo "ERROR: MCP server definitions not found: $servers" >&2
    exit 1
fi

dir="$(dirname "$target")"
mkdir -p "$dir"

# Temp file in the TARGET directory (not shared /tmp): no cross-install
# collisions, no pre-created-symlink redirect, and mv stays on one filesystem.
tmp="$(mktemp "$dir/.claude.json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

if [ -f "$target" ]; then
    jq --slurpfile mcp "$servers" '.mcpServers = ((.mcpServers // {}) + $mcp[0])' "$target" > "$tmp"
else
    jq -n --slurpfile mcp "$servers" '{mcpServers: $mcp[0]}' > "$tmp"
fi

# Deliberate mode: this file carries session/runtime state. Best-effort only —
# Claude Code recreates it under the process umask on its own rewrites.
chmod 600 "$tmp"
mv "$tmp" "$target"
trap - EXIT

echo "Merged MCP servers into $target"
