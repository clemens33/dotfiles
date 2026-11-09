#!/bin/sh
# Contract for the on-demand browser MCP servers (Clemens 2026-11-09).
#
# Requirement: no harness starts a browser MCP server (chrome-devtools,
# playwright) by default; a seat opts in per launch. The invariant is that a
# default session spawns none and an opted-in seat gets the pinned definition.
#
# Expected outcomes come from the frozen oracle in the brief and the pre-change
# chrome-devtools object, written out literally below. They are never read from
# the files under test. Everything runs in a throwaway HOME: no real home, no
# browser, no MCP server process is started.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
PY=${PYTHON:-python3}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-browser-mcp.XXXXXX")
HOME_DIR=$TMP_ROOT/home

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

PASS=0
FAIL=0

ok() {
    printf 'PASS: %s\n' "$1"
    PASS=$((PASS + 1))
}

bad() {
    printf 'FAIL: %s\n' "$1" >&2
    FAIL=$((FAIL + 1))
}

check() { # check <description> <command...>
    desc=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

jq_true() { # jq_true <file> <filter...>
    jt_file=$1
    shift
    jq -e "$@" "$jt_file" >/dev/null
}

# The pre-change definition of chrome-devtools, byte for byte as a value.
CD_DEF='{"type":"stdio","command":"npx","args":["-y","chrome-devtools-mcp@1.8.0","--browser-url=http://127.0.0.1:9222","--no-usage-statistics","--no-performance-crux"],"env":{}}'
PW_DEF='{"command":"npx","args":["-y","@playwright/mcp@0.0.84"],"env":{"DISPLAY":""}}'
# The same pin as a command array (opencode shape) and as TOML args (codex).
CD_CMD='["npx","-y","chrome-devtools-mcp@1.8.0","--browser-url=http://127.0.0.1:9222","--no-usage-statistics","--no-performance-crux"]'
CD_ARGS='["-y","chrome-devtools-mcp@1.8.0","--browser-url=http://127.0.0.1:9222","--no-usage-statistics","--no-performance-crux"]'

SOURCE=$ROOT/claude/mcpServers.json
OPTIN=$ROOT/claude/browser-mcp.json
SETTINGS=$ROOT/claude/settings.json

# --- 1. the default Claude/Muse/Copilot source is empty ---------------------------

check 'claude/mcpServers.json is {}' jq_true "$SOURCE" '. == {}'

# --- 2-4. the opt-in file ----------------------------------------------------------

check 'claude/browser-mcp.json is JSON with only the mcpServers key' \
    jq_true "$OPTIN" 'keys == ["mcpServers"]'
check 'claude/browser-mcp.json holds exactly chrome-devtools and playwright' \
    jq_true "$OPTIN" '.mcpServers | keys == ["chrome-devtools", "playwright"]'
check 'chrome-devtools in the opt-in file equals the pre-change definition' \
    jq_true "$OPTIN" --argjson want "$CD_DEF" '.mcpServers["chrome-devtools"] == $want'
check 'playwright is pinned to @playwright/mcp@0.0.84 with DISPLAY empty' \
    jq_true "$OPTIN" --argjson want "$PW_DEF" '.mcpServers.playwright == $want'
no_latest() {
    ! grep -Fq '@latest' "$OPTIN"
}
check 'the opt-in file never uses @latest' no_latest

# --- 5. playwright is off by default for every Claude home -----------------------

check 'claude/settings.json disables the .mcp.json playwright server' \
    jq_true "$SETTINGS" '(.disabledMcpjsonServers // []) | index("playwright") != null'
mkdir -p "$HOME_DIR/.claude-p" "$HOME_DIR/.claude-mic"
HOME=$HOME_DIR sh "$ROOT/scripts/render-claude-settings.sh" >/dev/null 2>&1 || true
check 'rendered claude-p settings keep disabledMcpjsonServers' \
    jq_true "$HOME_DIR/.claude-p/settings.json" '(.disabledMcpjsonServers // []) | index("playwright") != null'
check 'rendered claude-mic settings keep disabledMcpjsonServers' \
    jq_true "$HOME_DIR/.claude-mic/settings.json" '(.disabledMcpjsonServers // []) | index("playwright") != null'

# --- 6-8. install proof in a throwaway HOME ---------------------------------------
# A target that already has chrome-devtools next to a machine-local server, merged
# with the TRACKED source, loses chrome-devtools and keeps the local server.

CLAUDE_T=$TMP_ROOT/claude/.claude.json
mkdir -p "$(dirname "$CLAUDE_T")"
printf '%s\n' '{"runtime":"keep","mcpServers":{"chrome-devtools":{"command":"old"},"machine-local":{"command":"local"}}}' >"$CLAUDE_T"
HOME=$HOME_DIR bash "$ROOT/scripts/mcp-merge.sh" "$CLAUDE_T" "$SOURCE" >/dev/null 2>&1 || true
check 'mcp-merge with the tracked source removes chrome-devtools and keeps the local server' \
    jq_true "$CLAUDE_T" '.runtime == "keep" and (.mcpServers | has("chrome-devtools") | not) and .mcpServers["machine-local"].command == "local"'

for spelling in mcpServers mcp_servers; do
    muse_t=$TMP_ROOT/muse-$spelling/settings.json
    mkdir -p "$(dirname "$muse_t")"
    jq -n --arg key "$spelling" '{runtime_nonce:"keep",($key):{"chrome-devtools":{command:"old"},"machine-local":{command:"local"}}}' >"$muse_t"
    HOME=$HOME_DIR sh "$ROOT/scripts/muse-settings-merge.sh" "$muse_t" "$ROOT/muse/settings.json" "$SOURCE" >/dev/null 2>&1 || true
    check "muse-settings-merge with the tracked source removes chrome-devtools ($spelling)" \
        jq_true "$muse_t" '.runtime_nonce == "keep" and (has("mcp_servers") | not) and (.mcpServers | has("chrome-devtools") | not) and .mcpServers["machine-local"].command == "local"'
done

COP_T=$TMP_ROOT/copilot/mcp-config.json
mkdir -p "$(dirname "$COP_T")"
printf '%s\n' '{"mcpServers":{"local":{"custom":true},"chrome-devtools":{"type":"local","command":"npx","args":[],"env":{},"tools":["*"]}}}' >"$COP_T"
HOME=$HOME_DIR sh -c 'bash "$1" "$2" "$3"' _ "$ROOT/scripts/copilot-mcp-merge.sh" "$COP_T" "$SOURCE" >/dev/null 2>&1 || true
check 'copilot merge with the tracked source deletes chrome-devtools and keeps the local server' \
    jq_true "$COP_T" '.mcpServers == {"local": {"custom": true}}'
COP_SRC=$TMP_ROOT/copilot-source.json
printf '%s\n' "{\"chrome-devtools\":$CD_DEF}" >"$COP_SRC"
cp "$COP_T" "$TMP_ROOT/copilot-before.json"
cop_rejects_chrome() {
    if bash "$ROOT/scripts/copilot-mcp-merge.sh" "$COP_T" "$COP_SRC" >/dev/null 2>&1; then
        return 1
    fi
    cmp -s "$COP_T" "$TMP_ROOT/copilot-before.json"
}
check 'copilot merge rejects a source that carries chrome-devtools and leaves the target alone' \
    cop_rejects_chrome

# --- 9. installer wiring -----------------------------------------------------------

install_wiring() {
    "$PY" -I - "$ROOT/install.conf.yaml" <<'PY'
import sys
import yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
links = {}
for group in doc:
    if isinstance(group, dict) and "link" in group:
        links.update(group["link"])
entry = links.get("~/.config/ae/browser-mcp.json")
assert isinstance(entry, dict), "no link for ~/.config/ae/browser-mcp.json"
assert entry.get("path") == "claude/browser-mcp.json", entry
assert entry.get("create") is True, entry
commands = [c["command"] for g in doc if isinstance(g, dict) and "shell" in g
            for c in g["shell"] if isinstance(c, dict) and "command" in c]
assert "scripts/agy-mcp-retire.sh chrome-devtools" in commands, "no agy retire step for chrome-devtools"
PY
}
check 'install.conf.yaml links the opt-in file and retires chrome-devtools from agy' install_wiring

# --- 10. per-harness defaults ------------------------------------------------------

harness_defaults() {
    "$PY" -I - "$ROOT" "$CD_ARGS" "$CD_CMD" <<'PY'
import json, re, sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib

root, want_args, want_cmd = sys.argv[1], json.loads(sys.argv[2]), json.loads(sys.argv[3])

def strip_jsonc(s):
    out, i, n, in_str = [], 0, len(s), False
    while i < n:
        c = s[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(s[i + 1]); i += 2; continue
            if c == '"':
                in_str = False
            i += 1; continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if s.startswith("//", i):
            j = s.find("\n", i); i = n if j < 0 else j; out.append(" "); continue
        if s.startswith("/*", i):
            j = s.find("*/", i + 2); i = j + 2; out.append(" "); continue
        out.append(c); i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

codex = tomllib.load(open(root + "/codex/config.toml", "rb"))["mcp_servers"]["chrome-devtools"]
assert codex.get("enabled") is False, "codex chrome-devtools must carry enabled = false: %r" % codex
assert codex["command"] == "npx" and codex["args"] == want_args, codex

oc = json.loads(strip_jsonc(open(root + "/opencode/opencode.jsonc", encoding="utf-8").read()))
srv = oc["mcp"]["servers"]["chrome-devtools"]
assert srv.get("disabled") is True and "enabled" not in srv, "opencode chrome-devtools must carry disabled: true and no enabled key: %r" % srv
assert srv["command"] == want_cmd, srv

grok = tomllib.load(open(root + "/grok/config.toml", "rb"))
assert "chrome-devtools" not in grok.get("mcp_servers", {}), "grok still declares chrome-devtools"

agy = json.load(open(root + "/antigravity/settings.json", encoding="utf-8"))
assert "chrome-devtools" not in agy.get("mcpServers", {}), "antigravity still declares chrome-devtools"
PY
}
check 'codex and opencode keep a disabled definition; grok and antigravity declare none' harness_defaults

# --- the retired names stay out of the closed sources ----------------------------

no_browser_in_defaults() {
    ! grep -Eq 'playwright' "$SOURCE" "$ROOT/codex/config.toml" "$ROOT/grok/config.toml" \
        "$ROOT/opencode/opencode.jsonc" "$ROOT/antigravity/settings.json"
}
check 'no default harness source declares playwright' no_browser_in_defaults

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
