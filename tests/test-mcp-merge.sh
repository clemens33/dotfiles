#!/bin/sh
# Tests for scripts/mcp-merge.sh.
#
# Expected outcomes come from the script's documented contract (its header:
# additive merge, repo keys win, deletions in the source do NOT propagate,
# mode 600, jq-missing is a warned no-op) and from its install usage
# (install.conf.yaml merges claude/mcpServers.json into each identity's
# .claude.json, so runtime state written by Claude Code must survive).
# Nothing here asserts captured output of a previous run.
#
# Every target lives under a throwaway root with a fake HOME; a real
# ~/.claude.json is never a code path in this file.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=${MCP_MERGE_TEST_SCRIPT:-$ROOT/scripts/mcp-merge.sh}
REAL_SERVERS=$ROOT/claude/mcpServers.json
INSTALL=$ROOT/install.conf.yaml
BASH_BIN=$(command -v bash)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-mcp-merge.XXXXXX")

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

check() { # check <description> <condition-as-shell-word...>
    desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

# run_merge <home> <target> <servers>: sets RC, OUT, ERR.
run_merge() {
    RC=0
    HOME=$1 "$BASH_BIN" "$SCRIPT" "$2" "$3" \
        >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || RC=$?
    OUT=$(cat "$TMP_ROOT/out")
    ERR=$(cat "$TMP_ROOT/err")
}

err_has() {
    printf '%s' "$ERR" | grep -Fq -- "$1"
}

out_has() {
    printf '%s' "$OUT" | grep -Fq -- "$1"
}

# json_eq <file-a> <file-b>: deep equality modulo key order/formatting.
json_eq() {
    jq -S . "$1" >"$TMP_ROOT/canon-a" &&
        jq -S . "$2" >"$TMP_ROOT/canon-b" &&
        cmp -s "$TMP_ROOT/canon-a" "$TMP_ROOT/canon-b"
}

# jq_true <file> <filter...>: the filter holds for the document.
jq_true() {
    jt_file=$1
    shift
    jq -e "$@" "$jt_file" >/dev/null
}

mode_is_600() {
    [ -n "$(find "$1" -perm 600 -print)" ]
}

# no_temp_leftovers <dir>: no merge temp file survives in the target dir.
no_temp_leftovers() {
    [ -z "$(find "$1" -name '.claude.json.*' -print | head -n 1)" ]
}

HOME_DIR=$TMP_ROOT/home
mkdir -p "$HOME_DIR"

# Synthetic source with the same shape as claude/mcpServers.json (a map of
# server name -> definition). Deliberately not the tracked file for the
# semantic cases, so expectations are computed from this input alone.
SERVERS=$TMP_ROOT/servers.json
printf '%s\n' '{
  "alpha": {"type": "stdio", "command": "alpha-bin", "args": ["--flag"], "env": {}},
  "beta": {"type": "stdio", "command": "beta-bin", "args": [], "env": {"TOKEN": "${SOME_TOKEN}"}}
}' >"$SERVERS"

# --- fresh target -------------------------------------------------------------

FRESH_DIR=$TMP_ROOT/fresh/nested/deep
FRESH=$FRESH_DIR/.claude.json
run_merge "$HOME_DIR" "$FRESH" "$SERVERS"
check 'fresh target: exit 0' test "$RC" -eq 0
check 'fresh target: missing parent directories are created' test -f "$FRESH"
check 'fresh target: success line names the target' \
    out_has "Merged MCP servers into $FRESH"
printf '%s\n' '{"mcpServers": {
  "alpha": {"type": "stdio", "command": "alpha-bin", "args": ["--flag"], "env": {}},
  "beta": {"type": "stdio", "command": "beta-bin", "args": [], "env": {"TOKEN": "${SOME_TOKEN}"}}
}}' >"$TMP_ROOT/fresh-expected.json"
check 'fresh target: document is exactly {mcpServers: <source>}' \
    json_eq "$FRESH" "$TMP_ROOT/fresh-expected.json"
check 'fresh target: mode 0600' mode_is_600 "$FRESH"
check 'fresh target: no temp file left behind' no_temp_leftovers "$FRESH_DIR"

# The environment is never expanded into the file: a placeholder stays a
# placeholder, so no ambient secret value is written.
canary_target=$TMP_ROOT/canary/.claude.json
RC=0
HOME=$HOME_DIR SOME_TOKEN=canary-secret-value "$BASH_BIN" "$SCRIPT" \
    "$canary_target" "$SERVERS" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || RC=$?
check 'placeholders are not expanded from the environment' \
    jq_true "$canary_target" '.mcpServers.beta.env.TOKEN == "${SOME_TOKEN}"'
check 'the ambient secret value reaches neither file nor output' \
    test -z "$(grep -l 'canary-secret-value' "$canary_target" \
        "$TMP_ROOT/out" "$TMP_ROOT/err" 2>/dev/null)"

# --- additive merge into existing runtime state -------------------------------

EXISTING=$TMP_ROOT/existing/.claude.json
mkdir -p "$(dirname "$EXISTING")"
printf '%s\n' '{
  "hasCompletedOnboarding": true,
  "projects": {"/some/repo": {"hasTrustDialogAccepted": true, "allowedTools": ["Bash"]}},
  "mcpServers": {
    "alpha": {"type": "stdio", "command": "STALE", "env": {"OLD_ONLY": "drop-me"}},
    "machine-local": {"type": "stdio", "command": "local-bin", "args": []}
  }
}' >"$EXISTING"
chmod 644 "$EXISTING"
run_merge "$HOME_DIR" "$EXISTING" "$SERVERS"
check 'existing target: exit 0' test "$RC" -eq 0
check 'repo definition wins on a name collision' \
    jq_true "$EXISTING" '.mcpServers.alpha.command == "alpha-bin"'
# The win is whole-value (documented `(existing + repo)`), not a deep merge:
# a key present only in the stale definition must not survive.
check 'repo win replaces the whole definition (no deep merge)' \
    jq_true "$EXISTING" '(.mcpServers.alpha.env | has("OLD_ONLY")) | not'
check 'a machine-local server the repo does not know survives' \
    jq_true "$EXISTING" '.mcpServers["machine-local"].command == "local-bin"'
check 'a repo-only server is added' \
    jq_true "$EXISTING" '.mcpServers.beta.command == "beta-bin"'
check 'unrelated top-level runtime keys survive verbatim' \
    jq_true "$EXISTING" '.hasCompletedOnboarding == true'
check 'the projects subtree (owned by the trust merge) survives verbatim' \
    jq_true "$EXISTING" '.projects == {"/some/repo": {"hasTrustDialogAccepted": true, "allowedTools": ["Bash"]}}'
check 'an existing 0644 file is tightened to 0600' mode_is_600 "$EXISTING"

mode_negative_control() {
    cp "$EXISTING" "$TMP_ROOT/world-readable.json"
    chmod 644 "$TMP_ROOT/world-readable.json"
    ! mode_is_600 "$TMP_ROOT/world-readable.json"
}
check 'negative control rejects mode 0644' mode_negative_control

# Documented caveat: deleting a server from the source does not remove it.
printf '%s\n' '{"alpha": {"type": "stdio", "command": "alpha-bin", "args": ["--flag"], "env": {}}}' \
    >"$TMP_ROOT/servers-shrunk.json"
run_merge "$HOME_DIR" "$EXISTING" "$TMP_ROOT/servers-shrunk.json"
check 'a server deleted from the source stays installed (additive caveat)' \
    jq_true "$EXISTING" '.mcpServers | has("beta")'

# Existing documents with no usable mcpServers member.
for shape in 'absent:{"other": "keep"}' 'null:{"other": "keep", "mcpServers": null}'; do
    shape_name=${shape%%:*}
    shape_doc=${shape#*:}
    shape_target=$TMP_ROOT/shape-$shape_name/.claude.json
    mkdir -p "$(dirname "$shape_target")"
    printf '%s\n' "$shape_doc" >"$shape_target"
    run_merge "$HOME_DIR" "$shape_target" "$SERVERS"
    check "mcpServers $shape_name: merged servers appear, other keys kept" \
        jq_true "$shape_target" '.other == "keep" and (.mcpServers | keys == ["alpha", "beta"])'
done

# --- idempotency ---------------------------------------------------------------

cp "$FRESH" "$TMP_ROOT/first-merge"
run_merge "$HOME_DIR" "$FRESH" "$SERVERS"
check 'second merge is byte-identical' cmp -s "$TMP_ROOT/first-merge" "$FRESH"

byte_comparison_negative_control() {
    cp "$TMP_ROOT/first-merge" "$TMP_ROOT/changed-merge"
    printf '\n' >>"$TMP_ROOT/changed-merge"
    ! cmp -s "$TMP_ROOT/first-merge" "$TMP_ROOT/changed-merge"
}
check 'negative control detects changed merge bytes' \
    byte_comparison_negative_control

# Empty source object: nothing added, nothing taken.
printf '%s\n' '{}' >"$TMP_ROOT/servers-empty.json"
run_merge "$HOME_DIR" "$EXISTING" "$TMP_ROOT/servers-empty.json"
check 'empty source keeps every installed server' \
    jq_true "$EXISTING" '.mcpServers | keys == ["alpha", "beta", "machine-local"]'
EMPTY_FRESH=$TMP_ROOT/empty-fresh/.claude.json
run_merge "$HOME_DIR" "$EMPTY_FRESH" "$TMP_ROOT/servers-empty.json"
printf '%s\n' '{"mcpServers": {}}' >"$TMP_ROOT/empty-expected.json"
check 'empty source on a fresh target writes an empty mcpServers' \
    json_eq "$EMPTY_FRESH" "$TMP_ROOT/empty-expected.json"

# --- failure paths change nothing ----------------------------------------------

run_merge "$HOME_DIR" "$EXISTING" "$TMP_ROOT/absent-servers.json"
check 'missing source: exit 1' test "$RC" -eq 1
check 'missing source: the error names the file on stderr' \
    err_has "ERROR: MCP server definitions not found: $TMP_ROOT/absent-servers.json"

GHOST=$TMP_ROOT/ghost/deep/.claude.json
run_merge "$HOME_DIR" "$GHOST" "$TMP_ROOT/absent-servers.json"
check 'missing source: no target and no parent directory is created' \
    test ! -e "$TMP_ROOT/ghost"

fails_without_touching() { # fails_without_touching <target> <servers>
    cp "$1" "$TMP_ROOT/before-failure"
    RC=0
    HOME=$HOME_DIR "$BASH_BIN" "$SCRIPT" "$1" "$2" \
        >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || RC=$?
    [ "$RC" -ne 0 ] &&
        cmp -s "$TMP_ROOT/before-failure" "$1" &&
        no_temp_leftovers "$(dirname "$1")" &&
        ! grep -Fq 'Merged MCP servers into' "$TMP_ROOT/out"
}

BAD_TARGET=$TMP_ROOT/bad-target/.claude.json
mkdir -p "$(dirname "$BAD_TARGET")"
printf 'not json {\n' >"$BAD_TARGET"
check 'malformed target JSON: fails, bytes unchanged, no leftovers' \
    fails_without_touching "$BAD_TARGET" "$SERVERS"

GOOD_TARGET=$TMP_ROOT/good-target/.claude.json
mkdir -p "$(dirname "$GOOD_TARGET")"
printf '%s\n' '{"other": "keep"}' >"$GOOD_TARGET"
printf 'not json {\n' >"$TMP_ROOT/servers-malformed.json"
check 'malformed source JSON: fails, target unchanged, no leftovers' \
    fails_without_touching "$GOOD_TARGET" "$TMP_ROOT/servers-malformed.json"

printf '%s\n' '["not", "a", "server", "map"]' >"$TMP_ROOT/servers-array.json"
check 'source that is not a name->definition map: fails, target unchanged' \
    fails_without_touching "$GOOD_TARGET" "$TMP_ROOT/servers-array.json"

# --- missing jq is a visible no-op ----------------------------------------------

mkdir -p "$TMP_ROOT/empty-path"
NOJQ_TARGET=$TMP_ROOT/no-jq/.claude.json
RC=0
PATH=$TMP_ROOT/empty-path HOME=$HOME_DIR "$BASH_BIN" "$SCRIPT" \
    "$NOJQ_TARGET" "$SERVERS" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || RC=$?
OUT=$(cat "$TMP_ROOT/out")
check 'missing jq: exit 0' test "$RC" -eq 0
check 'missing jq: warning names the skipped target' \
    out_has "WARNING: jq not found, skipping MCP merge for $NOJQ_TARGET"
check 'missing jq: nothing is written' test ! -e "$NOJQ_TARGET"

cp "$GOOD_TARGET" "$TMP_ROOT/no-jq-before"
PATH=$TMP_ROOT/empty-path HOME=$HOME_DIR "$BASH_BIN" "$SCRIPT" \
    "$GOOD_TARGET" "$SERVERS" >/dev/null 2>&1 || true
check 'missing jq: an existing target is left byte-identical' \
    cmp -s "$TMP_ROOT/no-jq-before" "$GOOD_TARGET"

# --- symlink safety --------------------------------------------------------------
# mcp-merge has no symlink guard (its sibling claude-trust-merge refuses
# outright). The invariant pinned here is the safety floor both behaviours
# share: the merge must never write THROUGH a link into its referent. The
# exit status is deliberately not pinned, so adding the sibling's guard
# later does not break this suite.

LINK_DIR=$TMP_ROOT/linked
mkdir -p "$LINK_DIR"
printf '%s\n' '{"mcpServers": {}, "referent": "do-not-touch"}' >"$LINK_DIR/real.json"
cp "$LINK_DIR/real.json" "$LINK_DIR/real-before.json"
ln -s real.json "$LINK_DIR/.claude.json"
HOME=$HOME_DIR "$BASH_BIN" "$SCRIPT" "$LINK_DIR/.claude.json" "$SERVERS" \
    >/dev/null 2>&1 || true
check 'a symlinked target is never written through' \
    cmp -s "$LINK_DIR/real-before.json" "$LINK_DIR/real.json"

# --- quoting: a target path containing spaces ------------------------------------

SPACED=$TMP_ROOT/'dir with spaces'/.claude.json
run_merge "$HOME_DIR" "$SPACED" "$SERVERS"
check 'target path with spaces merges cleanly' \
    jq_true "$SPACED" '.mcpServers.alpha.command == "alpha-bin"'

# --- the tracked source the installer actually merges ----------------------------

TRACKED=$TMP_ROOT/tracked/.claude.json
run_merge "$HOME_DIR" "$TRACKED" "$REAL_SERVERS"
jq '{mcpServers: .}' "$REAL_SERVERS" >"$TMP_ROOT/tracked-expected.json"
check 'the tracked claude/mcpServers.json lands verbatim on a fresh target' \
    json_eq "$TRACKED" "$TMP_ROOT/tracked-expected.json"

# $HOME must stay literal in the tracked Dotbot commands.
# shellcheck disable=SC2016
installer_wires_mcp_merge() {
    grep -Fqx \
        '    - command: scripts/mcp-merge.sh "$HOME/.claude.json" claude/mcpServers.json' \
        "$1" &&
        grep -Fqx \
            '    - command: scripts/mcp-merge.sh "$HOME/.claude2/.claude.json" claude/mcpServers.json' \
            "$1"
}
check 'Dotbot install merges the tracked source into both identities' \
    installer_wires_mcp_merge "$INSTALL"

installer_wiring_negative_control() {
    sed '/scripts\/mcp-merge\.sh/d' "$INSTALL" \
        >"$TMP_ROOT/install-without-mcp.yaml"
    ! installer_wires_mcp_merge "$TMP_ROOT/install-without-mcp.yaml"
}
check 'negative control detects missing Dotbot MCP wiring' \
    installer_wiring_negative_control

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
