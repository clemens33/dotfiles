#!/bin/sh
# Tests for scripts/agy-mcp-retire.sh.
#
# Contract (the script's header): agy keeps MCP servers machine-locally, outside
# antigravity/settings.json. A retired name lives in two places, the entry in
# ~/.gemini/config/mcp_config.json and the tool cache directory
# ~/.gemini/antigravity-cli/mcp/NAME/. The script removes both on every install,
# leaves every other server, key and cache directory alone, and never fails the
# install over an absent agy, absent file or absent jq.
#
# Every target lives under a throwaway HOME. The real ~/.gemini is never a code
# path in this file; the optional real-agy check runs agy with HOME set to the
# throwaway directory.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=${AGY_RETIRE_TEST_SCRIPT:-$ROOT/scripts/agy-mcp-retire.sh}
INSTALL=$ROOT/install.conf.yaml
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-agy-mcp-retire.XXXXXX")

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

jq_true() { # jq_true <file> <filter>
    jq -e "$2" "$1" >/dev/null
}

# make_home <name>: a HOME holding an agy state that mirrors the real machine:
# open-design registered in mcp_config.json plus its cache directory, next to a
# machine-local server and an unrelated cache directory.
make_home() {
    h=$TMP_ROOT/$1
    mkdir -p "$h/.gemini/config" "$h/.gemini/antigravity-cli/mcp/open-design" "$h/.gemini/antigravity-cli/mcp/keep-me"
    cat >"$h/.gemini/config/mcp_config.json" <<'JSON'
{
  "mcpServers": {
    "open-design": {"command": "open-design-mcp", "disabled": false},
    "machine-local": {"command": "local-bin", "disabled": false}
  },
  "unrelated": "keep"
}
JSON
    printf '{}\n' >"$h/.gemini/antigravity-cli/mcp/open-design/list_files.json"
    printf '{}\n' >"$h/.gemini/antigravity-cli/mcp/keep-me/tool.json"
    printf '%s\n' "$h"
}

# stub_bin <dir> <mode>: a fake agy on PATH.
#   working  `agy mcp remove NAME` deletes the key from mcp_config.json (what
#            the real agy 1.5.3 does under a throwaway HOME) and logs the call.
#   failing  logs the call, deletes nothing, exits 1.
stub_bin() {
    mkdir -p "$1"
    cat >"$1/agy" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$1/calls"
[ "\$1 \$2" = "mcp remove" ] || exit 2
if [ "$2" = failing ]; then exit 1; fi
cfg=\$HOME/.gemini/config/mcp_config.json
jq --arg n "\$3" 'del(.mcpServers[\$n])' "\$cfg" >"\$cfg.tmp" && mv "\$cfg.tmp" "\$cfg"
EOF
    chmod +x "$1/agy"
}

run_retire() { # run_retire <home> <path-prefix-or-empty> [name]; sets RC, output in $RETIRE_OUT
    RC=0
    HOME=$1 PATH="${2:+$2:}$SAFE_PATH" sh "$SCRIPT" "${3-open-design}" >"$RETIRE_OUT" 2>&1 || RC=$?
}

RETIRE_OUT=$TMP_ROOT/retire.out

# A PATH without any real agy: the system tools plus jq, nothing else of ours.
SAFE_PATH=$TMP_ROOT/safe-bin
mkdir -p "$SAFE_PATH"
for tool in jq sh cat rm mv mkdir dirname basename mktemp printf grep sed ls chmod cp; do
    src=$(command -v "$tool" 2>/dev/null || true)
    case "$src" in /*) ln -sf "$src" "$SAFE_PATH/$tool" ;; esac
done

# --- agy works: the supported path removes the entry; the cache dir goes too ---
H1=$(make_home h1)
stub_bin "$TMP_ROOT/agy-ok" working
run_retire "$H1" "$TMP_ROOT/agy-ok"
check 'working agy: exit 0' test "$RC" -eq 0
check 'working agy: the run reports the retirement' grep -Fq 'Retired open-design' "$RETIRE_OUT"
check 'working agy: the registration is removed through agy mcp remove' \
    grep -Fqx 'mcp remove open-design' "$TMP_ROOT/agy-ok/calls"
check 'working agy: open-design is gone from mcp_config.json' \
    jq_true "$H1/.gemini/config/mcp_config.json" '.mcpServers | has("open-design") | not'
check 'working agy: the tool cache directory is gone' \
    test ! -e "$H1/.gemini/antigravity-cli/mcp/open-design"
check 'working agy: other servers and keys survive' \
    jq_true "$H1/.gemini/config/mcp_config.json" '.mcpServers["machine-local"].command == "local-bin" and .unrelated == "keep"'
check 'working agy: other cache directories survive' \
    test -f "$H1/.gemini/antigravity-cli/mcp/keep-me/tool.json"

# --- agy fails: the fallback edits the file itself ---
H2=$(make_home h2)
stub_bin "$TMP_ROOT/agy-bad" failing
run_retire "$H2" "$TMP_ROOT/agy-bad"
check 'failing agy: exit 0 (the install must not fail)' test "$RC" -eq 0
check 'failing agy: agy was tried first' grep -Fqx 'mcp remove open-design' "$TMP_ROOT/agy-bad/calls"
check 'failing agy: the fallback removes the entry from mcp_config.json' \
    jq_true "$H2/.gemini/config/mcp_config.json" '.mcpServers | has("open-design") | not'
check 'failing agy: the fallback removes the cache directory' \
    test ! -e "$H2/.gemini/antigravity-cli/mcp/open-design"
check 'failing agy: other servers and keys survive' \
    jq_true "$H2/.gemini/config/mcp_config.json" '.mcpServers["machine-local"].command == "local-bin" and .unrelated == "keep"'

# --- no agy on PATH ---
H3=$(make_home h3)
run_retire "$H3" ""
check 'no agy: exit 0' test "$RC" -eq 0
check 'no agy: the entry is removed anyway' \
    jq_true "$H3/.gemini/config/mcp_config.json" '.mcpServers | has("open-design") | not'
check 'no agy: the cache directory is removed anyway' \
    test ! -e "$H3/.gemini/antigravity-cli/mcp/open-design"
check 'no agy: the other cache directory survives' \
    test -f "$H3/.gemini/antigravity-cli/mcp/keep-me/tool.json"

# --- idempotent and absent state ---
cp "$H3/.gemini/config/mcp_config.json" "$TMP_ROOT/cfg-before"
run_retire "$H3" ""
check 'second run: exit 0' test "$RC" -eq 0
check 'second run: mcp_config.json is byte-identical' cmp -s "$TMP_ROOT/cfg-before" "$H3/.gemini/config/mcp_config.json"
H4=$TMP_ROOT/h4
mkdir -p "$H4"
run_retire "$H4" ""
check 'absent state: exit 0' test "$RC" -eq 0
check 'absent state: nothing is created' test -z "$(find "$H4" -mindepth 1 -print)"

# --- a symlinked config is never written through ---
H5=$(make_home h5)
mv "$H5/.gemini/config/mcp_config.json" "$TMP_ROOT/referent.json"
ln -s "$TMP_ROOT/referent.json" "$H5/.gemini/config/mcp_config.json"
cp "$TMP_ROOT/referent.json" "$TMP_ROOT/referent-before"
run_retire "$H5" ""
check 'symlinked config: exit 0' test "$RC" -eq 0
check 'symlinked config: the referent is untouched' cmp -s "$TMP_ROOT/referent-before" "$TMP_ROOT/referent.json"
check 'symlinked config: the registration stays, so its cache directory stays' \
    test -f "$H5/.gemini/antigravity-cli/mcp/open-design/list_files.json"

# --- invalid names are rejected before any path is built ---
H6=$(make_home h6)
for bad_name in '' '../x' 'a/b' 'Open Design' '.'; do
    run_retire "$H6" "" "$bad_name"
    check "name '$bad_name' is rejected with exit 2" test "$RC" -eq 2
done
check 'rejected names leave the state intact' \
    jq_true "$H6/.gemini/config/mcp_config.json" '.mcpServers | has("open-design")'

# --- the install runs it for open-design ---
# shellcheck disable=SC2016
check 'install.conf.yaml runs the retire step for open-design' \
    grep -Fqx '    - command: scripts/agy-mcp-retire.sh open-design' "$INSTALL"

# --- real agy (optional): the registration disappears from `agy mcp list` ---
if command -v agy >/dev/null 2>&1; then
    H7=$TMP_ROOT/h7
    mkdir -p "$H7"
    if HOME=$H7 agy mcp add open-design open-design-mcp >/dev/null 2>&1; then
        mkdir -p "$H7/.gemini/antigravity-cli/mcp/open-design"
        printf '{}\n' >"$H7/.gemini/antigravity-cli/mcp/open-design/list_files.json"
        HOME=$H7 agy mcp list 2>&1 | grep -q 'open-design' || bad 'real agy: fixture registration missing before the retire'
        RC=0
        HOME=$H7 sh "$SCRIPT" open-design >/dev/null 2>&1 || RC=$?
        check 'real agy: exit 0' test "$RC" -eq 0
        check 'real agy: agy mcp list no longer shows open-design' \
            sh -c '! HOME=$1 agy mcp list 2>&1 | grep -q open-design' _ "$H7"
        check 'real agy: mcp_config.json holds no open-design' \
            sh -c '! grep -q open-design "$1"' _ "$H7/.gemini/config/mcp_config.json"
        check 'real agy: the cache directory is gone' test ! -e "$H7/.gemini/antigravity-cli/mcp/open-design"
    else
        printf 'SKIP: real agy cannot add a server under a throwaway HOME\n'
    fi
else
    printf 'SKIP: real agy check (agy not installed)\n'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
