#!/bin/sh
# Exercise the launcher with a fake HOME and a recording Muse executable.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=${MUSE2_TEST_SCRIPT:-$ROOT/bin/muse2}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-muse2.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

PASS=0
FAIL=0
check() {
    desc=$1
    shift
    if "$@"; then
        printf 'PASS: %s\n' "$desc"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n' "$desc" >&2
        FAIL=$((FAIL + 1))
    fi
}

STUBS=$TMP_ROOT/bin
NO_MUSE=$TMP_ROOT/no-muse
CASE_HOME=$TMP_ROOT/home\ with\ spaces
mkdir -p "$STUBS" "$NO_MUSE" "$CASE_HOME/.config/muse" \
    "$CASE_HOME/.config/gh" "$CASE_HOME/.config/git" \
    "$CASE_HOME/.config/fish" "$CASE_HOME/.config-muse2/fish"
for tool in mkdir ln; do
    executable=$(command -v "$tool")
    ln -s "$executable" "$STUBS/$tool"
    ln -s "$executable" "$NO_MUSE/$tool"
done

cat >"$STUBS/muse" <<'EOF'
#!/bin/sh
printf '%s\n' "$XDG_CONFIG_HOME" >"$RECORD_DIR/xdg"
printf '%s\n' "${MUSE_AUTH_PATH-unset}" >"$RECORD_DIR/auth-path"
printf '%s\0' "$@" >"$RECORD_DIR/args"
printf 'muse stdout\n'
printf 'muse stderr\n' >&2
exit "${STUB_STATUS:-0}"
EOF
chmod 755 "$STUBS/muse"
printf 'account 1\n' >"$CASE_HOME/.config/muse/account-marker"
printf '{"contributor_mode_enabled":true}\n' >"$CASE_HOME/.config/muse/settings.json"
printf '{}\n' >"$CASE_HOME/.config/muse/trust.json"
printf 'keep real entry\n' >"$CASE_HOME/.config-muse2/fish/marker"
printf 'config file\n' >"$CASE_HOME/.config/config with spaces"
printf 'hidden file\n' >"$CASE_HOME/.config/.hidden"
ln -s "$CASE_HOME/missing-source" "$CASE_HOME/.config/dangling"
ln -s "$CASE_HOME/custom-git" "$CASE_HOME/.config-muse2/git"

run() {
    run_path=$1
    run_status=$2
    shift 2
    RC=0
    env -i HOME="$CASE_HOME" PATH="$run_path" RECORD_DIR="$TMP_ROOT" \
        XDG_CONFIG_HOME="$TMP_ROOT/inherited-xdg" STUB_STATUS="$run_status" \
        MUSE_AUTH_PATH="$CASE_HOME/.config/muse/auth.json" \
        /bin/sh "$SCRIPT" "$@" >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || RC=$?
}

is_link_to() {
    [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]
}

is_real_dir() {
    [ -d "$1" ] && [ ! -L "$1" ]
}

file_is() {
    [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]
}

err_has() {
    grep -Fq -- "$1" "$TMP_ROOT/err"
}

run "$STUBS" 0 exec --flag 'argument with spaces' '' '*?[x]' 'line
break'
printf '%s\0' exec --flag 'argument with spaces' '' '*?[x]' 'line
break' >"$TMP_ROOT/expected-args"
check 'successful Muse exit passes through' test "$RC" -eq 0
check 'XDG_CONFIG_HOME points at account 2 even when inherited' \
    file_is "$TMP_ROOT/xdg" "$CASE_HOME/.config-muse2"
check 'inherited download authentication path is cleared' \
    file_is "$TMP_ROOT/auth-path" unset
check 'arguments preserve spaces, empty strings, globs and newlines' \
    cmp -s "$TMP_ROOT/expected-args" "$TMP_ROOT/args"
check 'Muse stdout passes through' file_is "$TMP_ROOT/out" 'muse stdout'
check 'Muse stderr passes through' file_is "$TMP_ROOT/err" 'muse stderr'
check 'account 2 Muse directory is real, never linked to account 1' \
    is_real_dir "$CASE_HOME/.config-muse2/muse"
check 'account 1 content stays unchanged' \
    file_is "$CASE_HOME/.config/muse/account-marker" 'account 1'
check 'account 2 does not inherit contributor consent' \
    test ! -e "$CASE_HOME/.config-muse2/muse/settings.json"
check 'account 2 starts with its own trust decisions' \
    test ! -e "$CASE_HOME/.config-muse2/muse/trust.json"
check 'gh config points at normal config' \
    is_link_to "$CASE_HOME/.config-muse2/gh" "$CASE_HOME/.config/gh"
check 'config file with spaces points at normal config' \
    is_link_to "$CASE_HOME/.config-muse2/config with spaces" "$CASE_HOME/.config/config with spaces"
check 'hidden config entry points at normal config' \
    is_link_to "$CASE_HOME/.config-muse2/.hidden" "$CASE_HOME/.config/.hidden"
check 'dangling source symlink is mirrored' \
    is_link_to "$CASE_HOME/.config-muse2/dangling" "$CASE_HOME/.config/dangling"
check 'pre-existing real entry is preserved' \
    file_is "$CASE_HOME/.config-muse2/fish/marker" 'keep real entry'
check 'pre-existing dangling destination symlink is preserved' \
    is_link_to "$CASE_HOME/.config-muse2/git" "$CASE_HOME/custom-git"

printf 'account 2\n' >"$CASE_HOME/.config-muse2/muse/account-marker"
mkdir "$CASE_HOME/.config/new-tool"
rm "$CASE_HOME/.config/.hidden"
run "$STUBS" 23 login
check 'non-zero Muse exit passes through' test "$RC" -eq 23
check 'new normal config entry is linked on next launch' \
    is_link_to "$CASE_HOME/.config-muse2/new-tool" "$CASE_HOME/.config/new-tool"
check 'removed source does not delete an existing link' \
    is_link_to "$CASE_HOME/.config-muse2/.hidden" "$CASE_HOME/.config/.hidden"
check 'pre-existing account 2 content is preserved' \
    file_is "$CASE_HOME/.config-muse2/muse/account-marker" 'account 2'

run "$NO_MUSE" 0
check 'missing Muse exits non-zero' test "$RC" -ne 0
check 'missing Muse gives a clear error' err_has 'muse2: muse is not on PATH'

# An empty normal config is valid; unmatched globs must not become links.
CASE_HOME=$TMP_ROOT/empty-home
mkdir -p "$CASE_HOME"
run "$STUBS" 0
check 'missing normal config directory is accepted' test "$RC" -eq 0
check 'empty normal config still creates a real Muse directory' \
    is_real_dir "$CASE_HOME/.config-muse2/muse"
check 'unmatched globs do not create links' \
    test "$(find "$CASE_HOME/.config-muse2" -type l | wc -l | tr -d ' ')" -eq 0

# Refuse aliases that would put the second login in another account's directory.
CASE_HOME=$TMP_ROOT/aliased-home
mkdir -p "$CASE_HOME/.config/muse" "$CASE_HOME/.config-muse2"
ln -s "$CASE_HOME/.config/muse" "$CASE_HOME/.config-muse2/muse"
run "$STUBS" 0
check 'linked Muse directory is refused' test "$RC" -ne 0
check 'linked Muse directory stays untouched' \
    is_link_to "$CASE_HOME/.config-muse2/muse" "$CASE_HOME/.config/muse"

CASE_HOME=$TMP_ROOT/aliased-root
mkdir -p "$CASE_HOME/.config"
ln -s "$CASE_HOME/.config" "$CASE_HOME/.config-muse2"
run "$STUBS" 0
check 'linked account config root is refused' test "$RC" -ne 0
check 'linked account config root stays untouched' \
    is_link_to "$CASE_HOME/.config-muse2" "$CASE_HOME/.config"

# Another launch can create a link after the existence check. The link command
# must not follow that new directory link and write inside the normal config.
CASE_HOME=$TMP_ROOT/racing-home
RACE_STUBS=$TMP_ROOT/racing-bin
mkdir -p "$CASE_HOME/.config/gh" "$RACE_STUBS"
ln -s "$STUBS/muse" "$RACE_STUBS/muse"
ln -s "$STUBS/mkdir" "$RACE_STUBS/mkdir"
cat >"$RACE_STUBS/ln" <<'EOF'
#!/bin/sh
/bin/ln -s "$HOME/.config/gh" "$HOME/.config-muse2/gh"
exec /bin/ln "$@"
EOF
chmod 755 "$RACE_STUBS/ln"
run "$RACE_STUBS" 0
check 'concurrent link creation still launches Muse' test "$RC" -eq 0
check 'concurrent link creation preserves normal config' \
    test ! -e "$CASE_HOME/.config/gh/gh"
check 'concurrently created link points at normal config' \
    is_link_to "$CASE_HOME/.config-muse2/gh" "$CASE_HOME/.config/gh"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
