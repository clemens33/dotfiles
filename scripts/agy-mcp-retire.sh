#!/bin/sh
# Remove a retired MCP server from Antigravity (agy) machine-local state.
#
# Usage: agy-mcp-retire.sh NAME
#
# agy keeps MCP servers outside the managed antigravity/settings.json (it
# ignores that file's mcpServers block). A server added with `agy mcp add`
# lives in two places:
#   ~/.gemini/config/mcp_config.json        the registration (.mcpServers.NAME)
#   ~/.gemini/antigravity-cli/mcp/NAME/     agy's cache of the server's tools
# Neither is touched by a Dotbot link or a merge, so a server retired from the
# repo would stay enabled on every machine that once added it. This step removes
# both on every install. Every other server, key and cache directory stays.
#
# The supported path is `agy mcp remove NAME`. If agy is absent or the call does
# not clear the entry, the script deletes the key itself with jq. It never fails
# the install over an absent agy, file or jq; only a bad NAME exits non-zero (2).
# A symlinked mcp_config.json is never written through; its cache directory is
# kept too, so a registration that stays is never left without its tool cache.
#
# Retired: open-design (2026-11-09, Clemens ruling).
set -eu

if [ "$#" -ne 1 ]; then
    printf 'usage: agy-mcp-retire.sh NAME\n' >&2
    exit 2
fi
name=$1
case "$name" in
    '' | *[!a-z0-9-]* | -*)
        printf 'agy-mcp-retire: invalid server name: %s\n' "$name" >&2
        exit 2
        ;;
esac

cfg=$HOME/.gemini/config/mcp_config.json
cache=$HOME/.gemini/antigravity-cli/mcp/$name
keep_cache=0

registered() {
    [ -f "$cfg" ] && [ ! -L "$cfg" ] &&
        jq -e --arg n "$name" '(.mcpServers // {}) | has($n)' "$cfg" >/dev/null 2>&1
}

if [ -L "$cfg" ]; then
    printf 'agy-mcp-retire: %s is a symlink; left alone, cache kept\n' "$cfg"
    keep_cache=1
elif [ -f "$cfg" ]; then
    if ! command -v jq >/dev/null 2>&1; then
        printf 'WARNING: jq not found, skipping agy MCP retirement of %s\n' "$name"
        exit 0
    fi
    if registered; then
        if command -v agy >/dev/null 2>&1; then
            agy mcp remove "$name" >/dev/null 2>&1 || true
        fi
        if registered; then
            # In-place write keeps the file's mode and inode.
            tmp=$(mktemp "${TMPDIR:-/tmp}/agy-mcp-retire.XXXXXX")
            trap 'rm -f "$tmp"' EXIT HUP INT TERM
            if jq --arg n "$name" 'del(.mcpServers[$n])' "$cfg" >"$tmp"; then
                cat "$tmp" >"$cfg"
            else
                printf 'WARNING: could not rewrite %s\n' "$cfg" >&2
            fi
            rm -f "$tmp"
            trap - EXIT HUP INT TERM
        fi
        if registered; then
            printf 'WARNING: %s is still registered in %s; cache kept\n' "$name" "$cfg" >&2
            keep_cache=1
        else
            printf 'Retired %s from %s\n' "$name" "$cfg"
        fi
    fi
fi

if [ "$keep_cache" -eq 0 ] && [ -d "$cache" ] && [ ! -L "$cache" ]; then
    rm -rf "$cache"
    printf 'Removed %s\n' "$cache"
fi
