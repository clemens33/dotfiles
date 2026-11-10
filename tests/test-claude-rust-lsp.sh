#!/bin/sh
# Contract for the opt-in Rust language server in Claude Code (Clemens 2026-11-10).
#
# Requirement: the rust-analyzer-lsp plugin stays installed but is OFF by default
# in every Claude home; a seat opts in per launch with
# `claude --settings=$HOME/.config/ae/rust-lsp.settings.json`. The invariant is
# that a default session starts no rust-analyzer and the opt-in file flips only
# that one plugin key. Expected values are written out literally below, never
# read from the files under test. Everything runs in a throwaway HOME: no real
# home, no Claude Code process, no language server is started.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
PY=${PYTHON:-python3}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-claude-rust-lsp.XXXXXX")
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

PLUGIN='rust-analyzer-lsp@claude-plugins-official'
SETTINGS=$ROOT/claude/settings.json
OPTIN=$ROOT/claude/rust-lsp.settings.json

# --- 1. the tracked base settings turn the plugin off -----------------------------

check 'claude/settings.json sets the rust-analyzer-lsp plugin to false' \
    jq_true "$SETTINGS" --arg k "$PLUGIN" '.enabledPlugins[$k] == false'

# --- 2. the opt-in file flips only that key ---------------------------------------

check 'claude/rust-lsp.settings.json is exactly the one enabledPlugins entry, true' \
    jq_true "$OPTIN" --arg k "$PLUGIN" '. == {enabledPlugins: {($k): true}}'

# --- 3. both extra Claude homes are rendered with the plugin off ------------------

mkdir -p "$HOME_DIR/.claude-p" "$HOME_DIR/.claude-mic"
# A stale target from before this change, with the plugin on, is replaced.
for id in .claude-p .claude-mic; do
    jq -n --arg k "$PLUGIN" '{enabledPlugins: {($k): true}, runtime: "stale"}' >"$HOME_DIR/$id/settings.json"
done
HOME=$HOME_DIR sh "$ROOT/scripts/render-claude-settings.sh" >/dev/null 2>&1 || bad 'render-claude-settings.sh exited non-zero'
for id in .claude-p .claude-mic; do
    check "rendered $id settings turn the plugin off" \
        jq_true "$HOME_DIR/$id/settings.json" --arg k "$PLUGIN" '.enabledPlugins[$k] == false'
    check "rendered $id settings drop the stale runtime key" \
        jq_true "$HOME_DIR/$id/settings.json" 'has("runtime") | not'
done

# --- 4. installer wiring ----------------------------------------------------------

install_wiring() {
    "$PY" -I - "$ROOT/install.conf.yaml" <<'PY'
import sys
import yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
links = {}
for group in doc:
    if isinstance(group, dict) and "link" in group:
        links.update(group["link"])
entry = links.get("~/.config/ae/rust-lsp.settings.json")
assert isinstance(entry, dict), "no link for ~/.config/ae/rust-lsp.settings.json"
assert entry.get("path") == "claude/rust-lsp.settings.json", entry
assert entry.get("create") is True, entry
PY
}
check 'install.conf.yaml links the opt-in file to ~/.config/ae/rust-lsp.settings.json' install_wiring

# --- 5. the opt-in route is documented --------------------------------------------

check 'README documents the --settings opt-in path' \
    grep -Fq -- '--settings=$HOME/.config/ae/rust-lsp.settings.json' "$ROOT/README.md"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
