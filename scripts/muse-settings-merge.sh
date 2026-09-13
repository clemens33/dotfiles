#!/bin/sh
# Merge managed Muse settings and MCP servers into Muse's runtime state file.
#
# Usage: muse-settings-merge.sh <target> <settings.json> <mcpServers.json>
#
# Managed settings and managed MCP names win. MCP merging stays additive, like
# scripts/mcp-merge.sh, because Muse can add machine-local servers to this same
# file; a later install must not erase them. Legacy mcp_servers entries are
# folded into mcpServers before the unsafe snake_case key is removed.
set -eu

target=$1
settings=$2
servers=$3

if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found, skipping Muse settings merge for $target"
    exit 0
fi

if [ ! -f "$settings" ]; then
    echo "ERROR: Muse settings not found: $settings" >&2
    exit 1
fi

if [ ! -f "$servers" ]; then
    echo "ERROR: MCP server definitions not found: $servers" >&2
    exit 1
fi

dir=$(dirname "$target")
mkdir -p "$dir"
tmp=$(mktemp "$dir/.muse-settings.XXXXXX")
trap 'rm -f "$tmp"' EXIT

if [ -f "$target" ]; then
    jq --slurpfile managed "$settings" --slurpfile mcp "$servers" '
        (.mcp_servers // {}) as $legacy_mcp |
        (.mcpServers // {}) as $existing_mcp |
        (del(.mcp_servers) + $managed[0]) |
        .mcpServers = ($legacy_mcp + $existing_mcp + $mcp[0])
    ' "$target" >"$tmp"
else
    jq -n --slurpfile managed "$settings" --slurpfile mcp "$servers" '
        $managed[0] | .mcpServers = $mcp[0]
    ' >"$tmp"
fi

if ! jq -e 'has("mcp_servers") | not' "$tmp" >/dev/null; then
    echo "ERROR: refusing Muse settings with both MCP key spellings" >&2
    exit 1
fi

chmod 600 "$tmp"
mv "$tmp" "$target"
trap - EXIT

echo "Merged managed settings into $target"
