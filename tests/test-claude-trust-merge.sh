#!/bin/sh
# Tests for scripts/claude-trust-merge.sh.
#
# Expected outcomes come from the script's documented contract (its header:
# additive, only ever sets hasTrustDialogAccepted to true, every other key
# preserved, re-running is safe and order-independent) and from the prefix
# rule it states in prose: a project is flagged when it IS a listed root or
# lies UNDER one, and nothing outside the listed roots is ever touched.
# Nothing here asserts captured output of a previous run.
#
# Every target lives under a throwaway root with a fake HOME (which is also
# what ~ expands against); a real ~/.claude.json is never a code path here.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=${CLAUDE_TRUST_MERGE_TEST_SCRIPT:-$ROOT/scripts/claude-trust-merge.sh}
MCP_SCRIPT=$ROOT/scripts/mcp-merge.sh
REAL_PATHS=$ROOT/claude/trusted-paths.txt
INSTALL=$ROOT/install.conf.yaml
BASH_BIN=$(command -v bash)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-claude-trust-merge.XXXXXX")

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

# run_trust <home> <target> <paths-file>: sets RC, OUT, ERR.
run_trust() {
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

# flagged <file> <project-key>
flagged() {
    jq -e --arg k "$2" '.projects[$k].hasTrustDialogAccepted == true' \
        "$1" >/dev/null
}

# unflagged <file> <project-key>: the flag is absent or not true.
unflagged() {
    jq -e --arg k "$2" '.projects[$k].hasTrustDialogAccepted != true' \
        "$1" >/dev/null
}

mode_is_600() {
    [ -n "$(find "$1" -perm 600 -print)" ]
}

# no_temp_leftovers <dir>: neither merge temp nor seed file survives.
no_temp_leftovers() {
    [ -z "$(find "$1" -name '.claude.json.*' -print | head -n 1)" ]
}

HOME_DIR=$TMP_ROOT/home
mkdir -p "$HOME_DIR"

PATHS=$TMP_ROOT/paths.txt
printf '%s\n' '/trusted/root' '/also/trusted' >"$PATHS"

# --- fresh target ---------------------------------------------------------------

FRESH_DIR=$TMP_ROOT/fresh/nested/deep
FRESH=$FRESH_DIR/.claude.json
run_trust "$HOME_DIR" "$FRESH" "$PATHS"
check 'fresh target: exit 0' test "$RC" -eq 0
check 'fresh target: missing parent directories are created' test -f "$FRESH"
check 'fresh target: success line counts the listed paths' \
    out_has "Pre-accepted trust for 2 path(s) in $FRESH"
printf '%s\n' '{"projects": {
  "/trusted/root": {"hasTrustDialogAccepted": true},
  "/also/trusted": {"hasTrustDialogAccepted": true}
}}' >"$TMP_ROOT/fresh-expected.json"
check 'fresh target: each listed root is created holding only the flag' \
    json_eq "$FRESH" "$TMP_ROOT/fresh-expected.json"
check 'fresh target: mode 0600' mode_is_600 "$FRESH"
check 'fresh target: no temp or seed file left behind' \
    no_temp_leftovers "$FRESH_DIR"

# --- the prefix rule --------------------------------------------------------------
# One existing document exercising every side of the boundary at once.

PREFIX=$TMP_ROOT/prefix/.claude.json
mkdir -p "$(dirname "$PREFIX")"
printf '%s\n' '{
  "mcpServers": {"alpha": {"command": "alpha-bin"}},
  "projects": {
    "/trusted/root": {"hasTrustDialogAccepted": false, "allowedTools": ["Bash"], "note": "keep-me"},
    "/trusted/root/repo": {"note": "child"},
    "/trusted/root/repo/deeper/still": {},
    "/trusted/root-evil": {"hasTrustDialogAccepted": false},
    "/trusted/root2": {},
    "/trusted": {},
    "/Trusted/root/repo": {},
    "/elsewhere/entirely": {"hasTrustDialogAccepted": true}
  }
}' >"$PREFIX"
chmod 644 "$PREFIX"
run_trust "$HOME_DIR" "$PREFIX" "$PATHS"
check 'prefix fixture: exit 0' test "$RC" -eq 0
check 'the listed root itself flips false to true' flagged "$PREFIX" '/trusted/root'
check 'a repo directly under a listed root is flagged' \
    flagged "$PREFIX" '/trusted/root/repo'
check 'a deeper descendant is flagged' \
    flagged "$PREFIX" '/trusted/root/repo/deeper/still'
# The boundary that keeps this from trusting everything ever opened: a mere
# string prefix shares characters with the root but is not under it.
check 'a sibling sharing a string prefix is NOT flagged' \
    unflagged "$PREFIX" '/trusted/root-evil'
check 'a numerically suffixed sibling is NOT flagged' \
    unflagged "$PREFIX" '/trusted/root2'
check 'the parent of a listed root is NOT flagged' unflagged "$PREFIX" '/trusted'
check 'matching is case-sensitive' unflagged "$PREFIX" '/Trusted/root/repo'
check 'other keys inside a flagged entry survive verbatim' \
    jq_true "$PREFIX" '.projects["/trusted/root"] == {"hasTrustDialogAccepted": true, "allowedTools": ["Bash"], "note": "keep-me"}'
check 'other keys inside a newly flagged child survive' \
    jq_true "$PREFIX" '.projects["/trusted/root/repo"].note == "child"'
check 'an unlisted entry keeps its explicit false' \
    jq_true "$PREFIX" '.projects["/trusted/root-evil"].hasTrustDialogAccepted == false'
check 'an unlisted entry never gains the flag key' \
    jq_true "$PREFIX" '(.projects["/trusted/root2"] | has("hasTrustDialogAccepted")) | not'
check 'trust given elsewhere by hand is never revoked' \
    flagged "$PREFIX" '/elsewhere/entirely'
check 'no project anywhere in the document holds an invented false' \
    jq_true "$PREFIX" '[.projects[] | .hasTrustDialogAccepted] | map(select(. == false)) == [false]'
check 'the mcpServers subtree (owned by the MCP merge) survives verbatim' \
    jq_true "$PREFIX" '.mcpServers == {"alpha": {"command": "alpha-bin"}}'
check 'the second listed root is created alongside existing state' \
    flagged "$PREFIX" '/also/trusted'
check 'an existing 0644 file is tightened to 0600' mode_is_600 "$PREFIX"

flagged_negative_control() {
    jq '.projects["/trusted/root"].hasTrustDialogAccepted = false' "$PREFIX" \
        >"$TMP_ROOT/flag-negative.json"
    ! flagged "$TMP_ROOT/flag-negative.json" '/trusted/root'
}
check 'negative control: the flag probe rejects false' flagged_negative_control

# --- paths-file parsing ------------------------------------------------------------
# Comments, blanks, whitespace, duplicates, ~ expansion. HOME carries spaces
# so expansion and quoting are exercised together.

SPACED_HOME=$TMP_ROOT/'home with spaces'
mkdir -p "$SPACED_HOME"
MESSY=$TMP_ROOT/paths-messy.txt
# The ~ below must reach the FILE unexpanded: expanding it is the script's
# job, and that expansion is exactly what is under test.
# shellcheck disable=SC2088
printf '%s\n' \
    '# a full-line comment' \
    '' \
    '~/proj-one   ' \
    '   ~/proj-two # trailing comment' \
    '~' \
    '~/proj-one' \
    '/abs/root' \
    '/keep~tilde-inside' \
    '   ' >"$MESSY"
printf '\t%s\t\n' '/tabbed/root' >>"$MESSY"
PARSED=$TMP_ROOT/parsed/.claude.json
run_trust "$SPACED_HOME" "$PARSED" "$MESSY"
check 'messy list: exit 0' test "$RC" -eq 0
# shellcheck disable=SC2088 # prose label naming the syntax under test
check '~/x expands against HOME, trailing space trimmed' \
    flagged "$PARSED" "$SPACED_HOME/proj-one"
check 'leading space and trailing comment are stripped' \
    flagged "$PARSED" "$SPACED_HOME/proj-two"
check 'a bare ~ expands to HOME itself' flagged "$PARSED" "$SPACED_HOME"
check 'an absolute path passes through unchanged' flagged "$PARSED" '/abs/root'
check 'a ~ that is not leading is left alone' \
    flagged "$PARSED" '/keep~tilde-inside'
check 'tab padding is trimmed' flagged "$PARSED" '/tabbed/root'
check 'comments, blanks and duplicates yield exactly the real roots' \
    jq_true "$PARSED" '(.projects | keys | length) == 6'
check 'no #-fragment ever becomes a project key' \
    jq_true "$PARSED" '[.projects | keys[] | select(contains("#"))] == []'

# A list with nothing usable in it.
printf '%s\n' '# only comments' '' '   ' >"$TMP_ROOT/paths-empty.txt"
EMPTY_FRESH=$TMP_ROOT/empty-fresh/.claude.json
run_trust "$HOME_DIR" "$EMPTY_FRESH" "$TMP_ROOT/paths-empty.txt"
printf '%s\n' '{"projects": {}}' >"$TMP_ROOT/empty-expected.json"
check 'empty list on a fresh target writes empty projects, counts 0' \
    json_eq "$EMPTY_FRESH" "$TMP_ROOT/empty-expected.json"
check 'empty list: success line counts 0' out_has 'Pre-accepted trust for 0 path(s)'

cp "$PREFIX" "$TMP_ROOT/prefix-before-empty.json"
run_trust "$HOME_DIR" "$PREFIX" "$TMP_ROOT/paths-empty.txt"
check 'empty list leaves an existing document semantically unchanged' \
    json_eq "$PREFIX" "$TMP_ROOT/prefix-before-empty.json"

# Existing documents whose projects member needs creating.
for shape in 'absent:{"other": "keep"}' 'null:{"other": "keep", "projects": null}'; do
    shape_name=${shape%%:*}
    shape_doc=${shape#*:}
    shape_target=$TMP_ROOT/shape-$shape_name/.claude.json
    mkdir -p "$(dirname "$shape_target")"
    printf '%s\n' "$shape_doc" >"$shape_target"
    run_trust "$HOME_DIR" "$shape_target" "$PATHS"
    check "projects $shape_name: roots appear flagged, other keys kept" \
        jq_true "$shape_target" '.other == "keep" and .projects["/trusted/root"].hasTrustDialogAccepted == true and .projects["/also/trusted"].hasTrustDialogAccepted == true'
done

# --- idempotency and order-independence with the MCP merge -------------------------

cp "$FRESH" "$TMP_ROOT/first-merge"
run_trust "$HOME_DIR" "$FRESH" "$PATHS"
check 'second merge is byte-identical' cmp -s "$TMP_ROOT/first-merge" "$FRESH"

# install runs mcp-merge then trust-merge on the same file; both headers
# promise the composition converges in either order.
SERVERS=$TMP_ROOT/servers.json
printf '%s\n' '{"alpha": {"type": "stdio", "command": "alpha-bin"}}' >"$SERVERS"
ORDER_A=$TMP_ROOT/order-a/.claude.json
ORDER_B=$TMP_ROOT/order-b/.claude.json
HOME=$HOME_DIR "$BASH_BIN" "$MCP_SCRIPT" "$ORDER_A" "$SERVERS" >/dev/null 2>&1 &&
    run_trust "$HOME_DIR" "$ORDER_A" "$PATHS"
run_trust "$HOME_DIR" "$ORDER_B" "$PATHS"
HOME=$HOME_DIR "$BASH_BIN" "$MCP_SCRIPT" "$ORDER_B" "$SERVERS" >/dev/null 2>&1 || RC=$?
check 'mcp-then-trust and trust-then-mcp converge on the same document' \
    json_eq "$ORDER_A" "$ORDER_B"
check 'the converged document carries both merges' \
    jq_true "$ORDER_A" '.mcpServers.alpha.command == "alpha-bin" and .projects["/trusted/root"].hasTrustDialogAccepted == true'

# --- failure paths change nothing ---------------------------------------------------

run_trust "$HOME_DIR" "$PREFIX" "$TMP_ROOT/absent-paths.txt"
check 'missing paths file: exit 1' test "$RC" -eq 1
check 'missing paths file: the error names the file on stderr' \
    err_has "ERROR: trusted paths list not found: $TMP_ROOT/absent-paths.txt"

GHOST=$TMP_ROOT/ghost/deep/.claude.json
run_trust "$HOME_DIR" "$GHOST" "$TMP_ROOT/absent-paths.txt"
check 'missing paths file: no target and no parent directory is created' \
    test ! -e "$TMP_ROOT/ghost"

fails_without_touching() { # fails_without_touching <target> <paths-file>
    cp "$1" "$TMP_ROOT/before-failure"
    RC=0
    HOME=$HOME_DIR "$BASH_BIN" "$SCRIPT" "$1" "$2" \
        >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || RC=$?
    [ "$RC" -ne 0 ] &&
        cmp -s "$TMP_ROOT/before-failure" "$1" &&
        no_temp_leftovers "$(dirname "$1")" &&
        ! grep -Fq 'Pre-accepted trust' "$TMP_ROOT/out"
}

BAD_TARGET=$TMP_ROOT/bad-target/.claude.json
mkdir -p "$(dirname "$BAD_TARGET")"
printf 'not json {\n' >"$BAD_TARGET"
check 'malformed target JSON: fails, bytes unchanged, no leftovers' \
    fails_without_touching "$BAD_TARGET" "$PATHS"

# Claude Code project entries are objects; anything else must fail loudly
# rather than be silently rewritten into a trust decision.
ODD_TARGET=$TMP_ROOT/odd-target/.claude.json
mkdir -p "$(dirname "$ODD_TARGET")"
printf '%s\n' '{"projects": {"/trusted/root": "not-an-object"}}' >"$ODD_TARGET"
check 'a non-object project entry: fails, bytes unchanged, no leftovers' \
    fails_without_touching "$ODD_TARGET" "$PATHS"

# Symlink and non-regular targets are refused outright: Claude Code rewrites
# this file by rename, so a link could never survive it anyway.
LINK_DIR=$TMP_ROOT/linked
mkdir -p "$LINK_DIR"
printf '%s\n' '{"projects": {}, "referent": "do-not-touch"}' >"$LINK_DIR/real.json"
cp "$LINK_DIR/real.json" "$LINK_DIR/real-before.json"
ln -s real.json "$LINK_DIR/.claude.json"
run_trust "$HOME_DIR" "$LINK_DIR/.claude.json" "$PATHS"
check 'symlink target: exit 1' test "$RC" -eq 1
check 'symlink target: error says why' \
    err_has 'is a symlink; Claude Code state files must be regular files'
check 'symlink target: the link itself is left in place' \
    test -L "$LINK_DIR/.claude.json"
check 'symlink target: the referent is byte-identical' \
    cmp -s "$LINK_DIR/real-before.json" "$LINK_DIR/real.json"

DIR_TARGET=$TMP_ROOT/dir-target/.claude.json
mkdir -p "$DIR_TARGET"
run_trust "$HOME_DIR" "$DIR_TARGET" "$PATHS"
check 'directory target: exit 1' test "$RC" -eq 1
check 'directory target: error says why' err_has 'exists but is not a regular file'
check 'directory target: no temp file dropped inside it' \
    test -z "$(find "$DIR_TARGET" -type f -print | head -n 1)"

# --- missing jq is a visible no-op ----------------------------------------------------

mkdir -p "$TMP_ROOT/empty-path"
NOJQ_TARGET=$TMP_ROOT/no-jq/.claude.json
RC=0
PATH=$TMP_ROOT/empty-path HOME=$HOME_DIR "$BASH_BIN" "$SCRIPT" \
    "$NOJQ_TARGET" "$PATHS" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || RC=$?
OUT=$(cat "$TMP_ROOT/out")
check 'missing jq: exit 0' test "$RC" -eq 0
check 'missing jq: warning names the skipped target' \
    out_has "WARNING: jq not found, skipping trust merge for $NOJQ_TARGET"
check 'missing jq: nothing is written' test ! -e "$NOJQ_TARGET"

cp "$PREFIX" "$TMP_ROOT/no-jq-before.json"
PATH=$TMP_ROOT/empty-path HOME=$HOME_DIR "$BASH_BIN" "$SCRIPT" \
    "$PREFIX" "$PATHS" >/dev/null 2>&1 || true
check 'missing jq: an existing target is left byte-identical' \
    cmp -s "$TMP_ROOT/no-jq-before.json" "$PREFIX"

# --- the tracked list the installer actually merges -------------------------------------

TRACKED=$TMP_ROOT/tracked/.claude.json
run_trust "$HOME_DIR" "$TRACKED" "$REAL_PATHS"
check 'tracked list: success line counts its 7 roots' \
    out_has 'Pre-accepted trust for 7 path(s)'
check 'tracked list: every root lands expanded against HOME and flagged' \
    jq_true "$TRACKED" --arg home "$HOME_DIR" '
        (.projects | keys | length) == 7 and
        ([.projects[] | .hasTrustDialogAccepted] | all(. == true)) and
        (.projects | has($home + "/projects")) and
        (.projects | has($home + "/projects/clemens33/dotfiles")) and
        (.projects | has($home + "/projects/mic/ai"))'
check 'tracked list: HOME itself is deliberately not a root' \
    jq_true "$TRACKED" --arg home "$HOME_DIR" '(.projects | has($home)) | not'

# $HOME must stay literal in the tracked Dotbot commands.
# shellcheck disable=SC2016
installer_wires_trust_merge() {
    grep -Fqx \
        '    - command: scripts/claude-trust-merge.sh "$HOME/.claude.json" claude/trusted-paths.txt' \
        "$1" &&
        grep -Fqx \
            '    - command: scripts/claude-trust-merge.sh "$HOME/.claude2/.claude.json" claude/trusted-paths.txt' \
            "$1" &&
        grep -Fqx \
            '    - command: scripts/claude-trust-merge.sh "$HOME/.claude-p/.claude.json" claude/trusted-paths.txt' \
            "$1"
}
check 'Dotbot install merges the tracked list into all identities' \
    installer_wires_trust_merge "$INSTALL"

installer_wiring_negative_control() {
    sed '/scripts\/claude-trust-merge\.sh/d' "$INSTALL" \
        >"$TMP_ROOT/install-without-trust.yaml"
    ! installer_wires_trust_merge "$TMP_ROOT/install-without-trust.yaml"
}
check 'negative control detects missing Dotbot trust wiring' \
    installer_wiring_negative_control

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
