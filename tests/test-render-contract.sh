#!/bin/sh
# Tests for scripts/render-contract.sh.
#
# The script under test is exercised through a symlink inside a throwaway root
# whose sources are COPIES: the symlink-safety case deliberately points a target
# at the root's own shared/AGENTS.md, and a regression there must not be able to
# destroy the real one in this repo.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=$ROOT/scripts/render-contract.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-render-contract.XXXXXX")

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

sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    else
        sha256sum "$1" | awk '{ print $1 }'
    fi
}

contains() {
    grep -Fq -- "$2" "$1"
}

not_contains() {
    ! grep -Fq -- "$2" "$1"
}

no_trailing_separator() {
    ! tail -n 3 "$1" | grep -q '^---$'
}

# find -perm keeps this off `ls` parsing; 644 is an exact-mode match on both
# BSD and GNU find.
mode_is_644() {
    [ -n "$(find "$1" -perm 644 -print)" ]
}

# make_root <name> <with-overlay: yes|no>
make_root() {
    root=$TMP_ROOT/$1
    mkdir -p "$root/scripts" "$root/shared" "$root/dotfiles-mic"
    ln -s "$SCRIPT" "$root/scripts/render-contract.sh"
    cp "$ROOT/shared/AGENTS.md" "$root/shared/AGENTS.md"
    if [ "$2" = yes ]; then
        cp "$ROOT/dotfiles-mic/AGENTS-MIC.md" "$root/dotfiles-mic/AGENTS-MIC.md"
    fi
}

# make_home <name> <identity dirs...>
make_home() {
    home=$TMP_ROOT/$1
    shift
    mkdir -p "$home"
    for dir do
        mkdir -p "$home/$dir"
    done
}

# render <root> <home> [args...] — never inherits the caller's HOME.
render() {
    r=$TMP_ROOT/$1
    h=$TMP_ROOT/$2
    shift 2
    HOME=$h sh "$r/scripts/render-contract.sh" "$@"
}

PUBLIC_MARK='# SOUL.md'
MIC_MARK='# MIC addendum'

# ---------------------------------------------------------------------------
# 1. Full render: every identity present, overlay present
# ---------------------------------------------------------------------------
make_root full yes
make_home h1 .claude .claude2 .claude-mic .codex .config/opencode .gemini/config
render full h1 >"$TMP_ROOT/out1" 2>"$TMP_ROOT/err1" || bad "render exited non-zero"

for t in .claude/CLAUDE.md .claude2/CLAUDE.md .claude-mic/CLAUDE.md \
    .codex/AGENTS.md .config/opencode/AGENTS.md \
    .gemini/config/plugins/dotfiles/rules/AGENTS.md; do
    target=$TMP_ROOT/h1/$t
    check "$t is a regular file" test -f "$target"
    check "$t is not a symlink" test ! -L "$target"
    check "$t carries the public contract" contains "$target" "$PUBLIC_MARK"
    check "$t carries the MIC addendum" contains "$target" "$MIC_MARK"
    check "$t carries the generated-file header" contains "$target" 'GENERATED FILE'
done

check 'summary reports six renders' grep -q 'contract: 6 rendered' "$TMP_ROOT/out1"
check 'rendered file is mode 0644' mode_is_644 "$TMP_ROOT/h1/.claude/CLAUDE.md"

# ---------------------------------------------------------------------------
# 2. BLOCKER-class: a symlinked target must never be written through
# ---------------------------------------------------------------------------
make_root symlink yes
make_home h2 .claude
src=$TMP_ROOT/symlink/shared/AGENTS.md
before=$(sha256 "$src")
ln -s "$src" "$TMP_ROOT/h2/.claude/CLAUDE.md"
render symlink h2 >/dev/null
after=$(sha256 "$src")
check 'source survives a symlinked target byte-identical' test "$before" = "$after"
check 'symlinked target is replaced by a regular file' test ! -L "$TMP_ROOT/h2/.claude/CLAUDE.md"
check 'replaced target holds the rendered contract' \
    contains "$TMP_ROOT/h2/.claude/CLAUDE.md" 'GENERATED FILE'

# ---------------------------------------------------------------------------
# 3. Idempotence: a second run writes nothing at all
# ---------------------------------------------------------------------------
cp "$TMP_ROOT/h1/.claude/CLAUDE.md" "$TMP_ROOT/first-render"
touch "$TMP_ROOT/marker"
render full h1 >"$TMP_ROOT/out3"
check 'second run renders nothing' grep -q 'contract: 0 rendered, 6 unchanged' "$TMP_ROOT/out3"
check 'second run leaves bytes identical' cmp -s "$TMP_ROOT/first-render" "$TMP_ROOT/h1/.claude/CLAUDE.md"
newer=$(find "$TMP_ROOT/h1/.claude/CLAUDE.md" -newer "$TMP_ROOT/marker")
check 'second run does not even rewrite the file' test -z "$newer"

# ---------------------------------------------------------------------------
# 4. Private overlay absent: public-only output, no dangling separator
# ---------------------------------------------------------------------------
make_root public-only no
make_home h4 .claude
render public-only h4 >/dev/null
solo=$TMP_ROOT/h4/.claude/CLAUDE.md
check 'public-only target has the contract' contains "$solo" "$PUBLIC_MARK"
check 'public-only target has no MIC section' not_contains "$solo" "$MIC_MARK"
check 'public-only header records the missing overlay' \
    contains "$solo" 'Source 2: none (private overlay not checked out)'
check 'public-only target ends without a separator' no_trailing_separator "$solo"

# ---------------------------------------------------------------------------
# 5. Absent identity directory is skipped, never conjured
# ---------------------------------------------------------------------------
check 'no ~/.claude2 directory is created' test ! -e "$TMP_ROOT/h4/.claude2"
check 'no ~/.claude-mic directory is created' test ! -e "$TMP_ROOT/h4/.claude-mic"

# ---------------------------------------------------------------------------
# 6. --check reports drift and writes nothing
# ---------------------------------------------------------------------------
render full h1 --check >"$TMP_ROOT/out6" 2>&1
check '--check is quiet when up to date' grep -q '6 up to date, 0 stale' "$TMP_ROOT/out6"

printf 'tampered\n' >>"$TMP_ROOT/h1/.codex/AGENTS.md"
tampered=$(sha256 "$TMP_ROOT/h1/.codex/AGENTS.md")
rc=0
render full h1 --check >"$TMP_ROOT/out6b" 2>&1 || rc=$?
check '--check exits 1 on drift' test "$rc" = 1
check '--check names the stale target' grep -q "stale .*\.codex/AGENTS.md" "$TMP_ROOT/out6b"
check '--check writes nothing' test "$tampered" = "$(sha256 "$TMP_ROOT/h1/.codex/AGENTS.md")"

rc=0
render full h1 >/dev/null || rc=$?
check 'a normal run repairs the drifted target' test "$rc" = 0
check 'repaired target matches the rest' \
    cmp -s "$TMP_ROOT/h1/.codex/AGENTS.md" "$TMP_ROOT/h1/.claude/CLAUDE.md"

# ---------------------------------------------------------------------------
# 7. Usage errors
# ---------------------------------------------------------------------------
rc=0
render full h1 --nonsense >/dev/null 2>&1 || rc=$?
check 'unknown argument exits 2' test "$rc" = 2
rc=0
render full h1 --check extra >/dev/null 2>&1 || rc=$?
check 'too many arguments exits 2' test "$rc" = 2

# ---------------------------------------------------------------------------
# 8. A `Rendered:` line in the CONTRACT BODY is content, not the header date.
#    A blanket /^Rendered: /d would strip it from both sides of the comparison
#    and hide the change in either the source or the target.
# ---------------------------------------------------------------------------
make_root payload yes
printf '\nRendered: only by ./install, never by hand.\n' \
    >>"$TMP_ROOT/payload/dotfiles-mic/AGENTS-MIC.md"
make_home h8 .claude
render payload h8 >/dev/null
body_target=$TMP_ROOT/h8/.claude/CLAUDE.md
check 'a body Rendered: line reaches the target' \
    contains "$body_target" 'Rendered: only by ./install, never by hand.'

# Rewrite only the header date in the target: still ignored, still clean.
awk 'NR == 1 { h = ($0 == "<!--") }
     h && $0 == "-->" { h = 0 }
     h && /^Rendered: / { print "Rendered: 1999-01-01"; next }
     { print }' "$body_target" >"$TMP_ROOT/h8-redated"
cp "$TMP_ROOT/h8-redated" "$body_target"
chmod 644 "$body_target"
rc=0
render payload h8 --check >/dev/null 2>&1 || rc=$?
check 'a changed header date alone stays clean' test "$rc" = 0

# Tamper with the body line in the target only.
sed 's/^Rendered: only by .*/Rendered: whenever you like./' "$body_target" \
    >"$TMP_ROOT/h8-tampered"
cp "$TMP_ROOT/h8-tampered" "$body_target"
chmod 644 "$body_target"
rc=0
render payload h8 --check >"$TMP_ROOT/out8" 2>&1 || rc=$?
check '--check catches a tampered body Rendered: line' test "$rc" = 1
check '--check names that target' grep -q 'stale .*\.claude/CLAUDE\.md' "$TMP_ROOT/out8"

# Change the same kind of line in the SOURCE: targets must go stale.
render payload h8 >/dev/null
printf 'Rendered: a second body rule.\n' \
    >>"$TMP_ROOT/payload/dotfiles-mic/AGENTS-MIC.md"
rc=0
render payload h8 --check >/dev/null 2>&1 || rc=$?
check '--check catches a changed source Rendered: line' test "$rc" = 1

# ---------------------------------------------------------------------------
# 9. Mode is part of freshness: matching content at the wrong mode is stale
# ---------------------------------------------------------------------------
chmod 600 "$TMP_ROOT/h1/.claude2/CLAUDE.md"
rc=0
render full h1 --check >"$TMP_ROOT/out9" 2>&1 || rc=$?
check '--check catches a 0600 target' test "$rc" = 1
check '--check names the wrong-mode target' \
    grep -q 'stale .*\.claude2/CLAUDE\.md' "$TMP_ROOT/out9"
check '--check does not repair the mode itself' \
    test -z "$(find "$TMP_ROOT/h1/.claude2/CLAUDE.md" -perm 644 -print)"
render full h1 >/dev/null
check 'a normal run repairs the mode' mode_is_644 "$TMP_ROOT/h1/.claude2/CLAUDE.md"

chmod 666 "$TMP_ROOT/h1/.codex/AGENTS.md"
rc=0
render full h1 --check >/dev/null 2>&1 || rc=$?
check '--check catches a 0666 target' test "$rc" = 1
render full h1 >/dev/null
check 'a normal run repairs a world-writable target' mode_is_644 "$TMP_ROOT/h1/.codex/AGENTS.md"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
