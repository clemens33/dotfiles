#!/bin/sh
# Generic install shell-block guards.
#
# Lifted from tests/test-deepseek-harness.sh at f6483d5, sections
# "Dotbot runs shell: blocks under $SHELL" and "the precondition for pinning
# /bin/sh". Those checks are not specific to the retired pilot. The helpers,
# the Dotbot pin assertions, the seam, the install wiring, and the block scan
# below are that source, not a rewrite.
#
# Every `~/...` and `$HOME/...` string here is a literal pattern matched against
# the CONTENT of a config file, never a path this script resolves, so tilde and
# parameter expansion must NOT happen. File-wide because every occurrence is the
# same deliberate pattern.
# shellcheck disable=SC2088,SC2016
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-install-blocks.XXXXXX")

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

equals() { # equals <description> <actual> <expected>
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1 (got '$2', want '$3')"
    fi
}

CONF=$ROOT/install.conf.yaml

# ---------------------------------------------------------------------------
# 6b. Dotbot runs `shell:` blocks under $SHELL, so ./install pins a POSIX one
# ---------------------------------------------------------------------------
# THE REGRESSION THIS EXISTS FOR. Dotbot passes os.environ['SHELL'] to
# subprocess as `executable`, so a `shell:` block runs under the user's LOGIN
# shell. On a fish login every block here died at its first POSIX assignment
# (`fish: Unsupported use of =`) with the step half-executed, and the whole DSH
# install silently never happened.
#
# Extracting a block and running it under `sh` - which is what the rest of this
# file does - cannot see that, because it skips the very call chain that breaks.
# So these assert the chain: what ./install hands Dotbot, and what Dotbot then
# hands a command.
INSTALL_SH=$ROOT/install
MIC_CONF=$ROOT/dotfiles-mic/install.conf.yaml

check 'the root install script exists' test -f "$INSTALL_SH"
# The upstream behaviour this depends on. A Dotbot bump that stops honouring
# $SHELL would make the pin pointless, and silently so.
check 'Dotbot still selects the interpreter from $SHELL' \
    grep -q "executable = os.environ.get('SHELL')" "$ROOT/dotbot/dotbot/util/common.py"
# Both passes, or the overlay installs under fish while the public layer does
# not - which is worse than failing outright, because it half-works.
equals 'both Dotbot invocations pin the interpreter' \
    "$(grep -c '^[[:space:]]*SHELL="\${DOTBOT_SHELL}" \\$' "$INSTALL_SH" || true)" "2"
check 'the pinned interpreter is POSIX sh' \
    grep -q '^DOTBOT_SHELL="/bin/sh"$' "$INSTALL_SH"
# Command-scoped, not exported: the caller's login shell must survive ./install.
check 'the pin is never exported' \
    test "$(grep -c '^[[:space:]]*export SHELL' "$INSTALL_SH" || true)" = 0

# --- the real seam: Dotbot, a real config, a non-POSIX login shell ----------
# Reproduces the failure and proves the fix, using the REAL Dotbot binary and a
# throwaway config. No live home is touched: the block only writes into a temp
# directory.
login_shell=$(command -v fish || true)
if [ -x "$ROOT/dotbot/bin/dotbot" ] && [ -n "$login_shell" ]; then
    seam=$TMP_ROOT/seam
    mkdir -p "$seam"
    # A block that is POSIX and nothing more: an assignment and a redirect.
    # fish rejects the assignment; every POSIX shell accepts it.
    cat >"$seam/seam.conf.yaml" <<'SEAMCONF'
- shell:
  - command: |
      set -eu
      marker=ran
      printf '%s\n' "$marker" >"$SEAM_OUT"
    description: POSIX assignment canary
    stderr: true
SEAMCONF

    run_seam() { # run_seam <shell>
        rm -f "$seam/out"
        SHELL=$1 SEAM_OUT=$seam/out \
            "$ROOT/dotbot/bin/dotbot" -d "$seam" -c "$seam/seam.conf.yaml" \
            >"$seam/log" 2>&1
    }

    rc=0
    run_seam "$login_shell" || rc=$?
    check 'a fish login shell fails a POSIX block (the reported regression)' \
        test "$rc" != "0"
    check 'the fish failure is the unsupported-assignment one' \
        grep -q "Unsupported use of '='" "$seam/log"
    check 'the fish run produced no output file' test ! -e "$seam/out"

    rc=0
    run_seam /bin/sh || rc=$?
    equals 'the same block under /bin/sh succeeds' "$rc" "0"
    check 'the block under /bin/sh actually ran' test -s "$seam/out"
else
    ok 'Dotbot seam cases skipped (no dotbot checkout or no fish to reproduce with)'
fi

# --- the wiring: what the REAL ./install hands each Dotbot pass -------------
# Runs the real script with a stub Dotbot that records the SHELL it received,
# a stub git so the submodule lines are inert, and a temp HOME so the preflight
# cannot touch the real ~/.claude.
if command -v bash >/dev/null 2>&1; then
    wire=$TMP_ROOT/wire
    mkdir -p "$wire/home" "$wire/base/dotbot/bin" "$wire/base/dotfiles-mic" "$wire/bin"
    cp "$INSTALL_SH" "$wire/base/install"
    : >"$wire/base/install.conf.yaml"
    : >"$wire/base/dotfiles-mic/install.conf.yaml"
    : >"$wire/base/dotfiles-mic/.git"

    cat >"$wire/base/dotbot/bin/dotbot" <<'STUBBOT'
#!/bin/sh
# Records the interpreter Dotbot would hand subprocess, plus which pass this is.
printf '%s\t%s\n' "${SHELL:-UNSET}" "$*" >>"$WIRE_LOG"
exit 0
STUBBOT
    chmod +x "$wire/base/dotbot/bin/dotbot"

    cat >"$wire/bin/git" <<'STUBGIT'
#!/bin/sh
exit 0
STUBGIT
    chmod +x "$wire/bin/git"

    wire_log=$wire/log
    : >"$wire_log"
    rc=0
    (
        PATH=$wire/bin:$PATH HOME=$wire/home WIRE_LOG=$wire_log \
            SHELL=${login_shell:-/usr/bin/false} \
            bash "$wire/base/install"
    ) >"$wire/out" 2>&1 || rc=$?
    equals 'the real install script completes under a fish login shell' "$rc" "0"
    equals 'both Dotbot passes ran' "$(grep -c . "$wire_log" || true)" "2"
    equals 'every Dotbot pass received /bin/sh' \
        "$(awk -F'\t' '$1 == "/bin/sh" { n++ } END { print n + 0 }' "$wire_log")" "2"
    check 'the public pass is the one with the public config' \
        test -n "$(awk -F'\t' 'NR == 1 && index($2, "install.conf.yaml")' "$wire_log")"
    check 'the overlay pass is the one with the overlay config' \
        test -n "$(awk -F'\t' 'NR == 2 && index($2, "dotfiles-mic")' "$wire_log")"
    # The pin must not leak back into the caller.
    check 'the caller login shell is left alone' \
        test -z "$(awk -F'\t' '$1 != "/bin/sh"' "$wire_log")"
else
    ok 'install wiring cases skipped (bash not installed)'
fi

# --- the precondition for pinning /bin/sh at all ---------------------------
# Pinning a POSIX interpreter is only safe while every block IS POSIX. This is
# the standing check: a bashism added later fails here instead of failing an
# install on Ubuntu, where /bin/sh is dash rather than bash in POSIX mode.
scan_node=$(command -v node || true)
scan_prefix=${DSH_PREFIX:-$HOME/.local/share/dsh}
if [ -n "$scan_node" ] && "$scan_node" -e \
    'require("node:module").createRequire(process.argv[1] + "/package.json")("js-yaml")' \
    "$scan_prefix" >/dev/null 2>&1; then
    blocks=$TMP_ROOT/blocks
    mkdir -p "$blocks"
    n_blocks=$("$scan_node" -e '
        const { createRequire } = require("node:module")
        const yaml = createRequire(process.argv[1] + "/package.json")("js-yaml")
        const fs = require("node:fs")
        let n = 0
        for (const [tag, f] of [["pub", process.argv[3]], ["mic", process.argv[4]]]) {
          if (!fs.existsSync(f)) continue
          for (const b of yaml.load(fs.readFileSync(f, "utf8"))) {
            for (const st of (Array.isArray(b.shell) ? b.shell : [])) {
              if (typeof st?.command !== "string") continue
              n++
              fs.writeFileSync(`${process.argv[2]}/${tag}-${n}.sh`, st.command + "\n")
            }
          }
        }
        process.stdout.write(String(n))
    ' "$scan_prefix" "$blocks" "$CONF" "$MIC_CONF")
    check 'the shell blocks were extracted' test "${n_blocks:-0}" -gt 0

    bad_syntax=0
    for b in "$blocks"/*.sh; do
        sh -n "$b" 2>/dev/null || bad_syntax=$((bad_syntax + 1))
    done
    equals 'every shell block parses as POSIX sh' "$bad_syntax" "0"

    # dash is the stricter reading, and it is what /bin/sh IS on Ubuntu/WSL.
    if command -v dash >/dev/null 2>&1; then
        bad_dash=0
        for b in "$blocks"/*.sh; do
            dash -n "$b" 2>/dev/null || bad_dash=$((bad_dash + 1))
        done
        equals 'every shell block parses under dash, which is Ubuntu /bin/sh' \
            "$bad_dash" "0"
    else
        ok 'dash block parse skipped (dash not installed)'
    fi

    if command -v shellcheck >/dev/null 2>&1; then
        check 'no shell block uses a bashism shellcheck can name' \
            sh -c 'shellcheck -s sh -f gcc "$1"/*.sh 2>&1 | grep -qE "SC3[0-9]{3}|SC2039" && exit 1 || exit 0' \
            _ "$blocks"
    else
        ok 'block bashism scan skipped (shellcheck not installed)'
    fi

    # The pin is inert only while nothing downstream reads $SHELL.
    check 'no shell block reads $SHELL, so pinning it changes nothing else' \
        sh -c 'grep -l "SHELL" "$1"/*.sh >/dev/null 2>&1 && exit 1 || exit 0' _ "$blocks"
else
    ok 'shell-block POSIX scan skipped (no installed runtime to borrow js-yaml from)'
fi
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
