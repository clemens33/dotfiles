#!/bin/sh
# Drift guards for two things config.fish and fish/completions replace with static text:
#   1. the Homebrew block in config.fish stands in for `brew shellenv fish | source`;
#   2. fish/completions/uv.fish stands in for `uv generate-shell-completion fish | source`.
# Each guard SKIPs where its tool is missing. The uv guard also SKIPs under CI, where the
# installed uv version is not the one the file was generated with.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-fish-env-drift.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; }

# ---- 1. static Homebrew environment equals `brew shellenv fish` ---------------------
BREW=/opt/homebrew/bin/brew
FISH=$(command -v fish || true)
if [ ! -x "$BREW" ]; then
    skip "brew env: $BREW is not installed"
elif [ -z "$FISH" ]; then
    skip "brew env: fish is not installed"
else
    # The static block is every line between the `test -x` guard and the libpq comment.
    awk '
        /^if test -x \/opt\/homebrew\/bin\/brew$/ { inb = 1; next }
        inb && /^    # keg-only libpq/ { exit }
        inb { sub(/^    /, ""); print }
    ' "$ROOT/config.fish" >"$TMP/static.fish"
    if [ ! -s "$TMP/static.fish" ]; then
        fail "brew env: no static block found in config.fish"
    else
        "$BREW" shellenv fish >"$TMP/live.fish"
        # Print the resulting variables, one element per line, as the shell sees them.
        probe='for v in HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY MANPATH INFOPATH PATH
    echo "== $v"; set -q $v; and printf "%s\n" $$v
end'
        for case in "clean" "preset"; do
            if [ "$case" = preset ]; then
                extra="MANPATH=/foo/man::/bar/ INFOPATH=/x/info"
            else
                extra=""
            fi
            for src in static live; do
                # shellcheck disable=SC2086
                env -i HOME="$HOME" TERM=xterm PATH=/usr/bin:/bin $extra \
                    "$FISH" --no-config -c "source $TMP/$src.fish; $probe" >"$TMP/$src.$case.out" 2>&1 || true
            done
            if cmp -s "$TMP/static.$case.out" "$TMP/live.$case.out"; then
                pass "brew env ($case start): static block equals brew shellenv fish"
            else
                fail "brew env ($case start): static block differs from brew shellenv fish"
                diff "$TMP/static.$case.out" "$TMP/live.$case.out" | sed 's/^/    /' || true
            fi
        done
    fi
fi

# ---- 2. fish/completions/uv.fish matches the installed uv ---------------------------
if [ -n "${CI:-}" ]; then
    skip "uv completion: CI does not pin the uv version"
elif ! command -v uv >/dev/null 2>&1; then
    skip "uv completion: uv is not installed"
elif uv generate-shell-completion fish >"$TMP/uv.fish" 2>/dev/null && cmp -s "$TMP/uv.fish" "$ROOT/fish/completions/uv.fish"; then
    pass "uv completion: fish/completions/uv.fish matches uv $(uv --version | awk '{print $2}')"
else
    fail "uv completion: fish/completions/uv.fish differs from the installed uv; run: just uv-completion"
fi

[ "$FAIL" -eq 0 ]
