#!/usr/bin/env bash
# Reconcile the four public MCP names into native Copilot runtime state.
# Usage: copilot-mcp-merge.sh TARGET BARE_CLAUDE_SERVER_MAP
set -euo pipefail
if [ "$#" -ne 2 ]; then
    echo 'Usage: copilot-mcp-merge.sh TARGET SOURCE' >&2
    exit 2
fi
target=$1
source=$2
command -v jq >/dev/null 2>&1 || { echo 'copilot MCP: jq required' >&2; exit 1; }
[ ! -L "$target" ] || { echo 'copilot MCP: refusing symlink target' >&2; exit 1; }
# Source schema is deliberately closed: new public names/transports need an
# explicit adapter update rather than silently creating invalid native config.
jq -se '
    length == 1 and (.[0] |
    type == "object" and
    (keys - ["serena","context7","chrome-devtools","open-design"] | length == 0) and
    all(.[];
        type == "object" and
        (keys - ["type","command","args","env","cwd","timeout"] | length == 0) and
        ((has("type") | not) or .type == "stdio") and
        (.command | type == "string" and length > 0) and
        ((has("args") | not) or (.args | type == "array" and all(.[]; type == "string"))) and
        ((has("env") | not) or (.env | type == "object" and all(.[]; type == "string"))) and
        ((has("cwd") | not) or (.cwd | type == "string")) and
        ((has("timeout") | not) or (.timeout | type == "number" and . > 0))
    ))
' "$source" >/dev/null || { echo 'copilot MCP: unsupported source schema' >&2; exit 1; }
if [ -e "$target" ]; then
    jq -se 'length == 1 and (.[0] | type == "object" and ((has("mcpServers") | not) or (.mcpServers | type == "object")))' \
        "$target" >/dev/null || { echo 'copilot MCP: invalid target schema' >&2; exit 1; }
fi
dir=$(dirname "$target")
mkdir -p "$dir"
tmp=$(mktemp "$dir/.copilot-mcp.XXXXXX")
trap 'rm -f "$tmp"' EXIT
input=$target
[ -f "$input" ] || input=/dev/null
jq -s --slurpfile source "$source" '
    ($source[0] | with_entries(.value |= (. + {type:"local",args:(.args // []),env:(.env // {}),tools:["*"]}))) as $managed |
    (.[0] // {}) |
    .mcpServers = ((.mcpServers // {} | del(.serena,.context7,."chrome-devtools",."open-design")) + $managed)
' "$input" >"$tmp"
chmod 600 "$tmp"
if [ -f "$target" ] && cmp -s "$target" "$tmp" && [ -n "$(find "$target" -perm 600 -print)" ]; then
    exit 0
fi
mv "$tmp" "$target"
echo 'Reconciled native Copilot public MCP servers'
