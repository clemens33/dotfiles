#!/bin/sh

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
WRAPPER=$ROOT/bin/open-design
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-open-design.XXXXXX")
STUB_BIN=$TMP_ROOT/stub-bin
DOCKER_LOG=$TMP_ROOT/docker.log
TOOL_LOG=$TMP_ROOT/tool.log

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    file=$1
    expected=$(printf '%b' "$2")
    grep -F -- "$expected" "$file" >/dev/null ||
        fail "$file does not contain: $expected"
}

assert_not_contains() {
    file=$1
    unexpected=$2
    if grep -F -- "$unexpected" "$file" >/dev/null; then
        fail "$file unexpectedly contains: $unexpected"
    fi
}

assert_empty() {
    [ ! -s "$1" ] || fail "$1 is not empty"
}

reset_logs() {
    : > "$DOCKER_LOG"
    : > "$TOOL_LOG"
}

mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/docker" <<'STUB'
#!/bin/sh
{
    printf 'CALL'
    for arg do
        printf '\t<%s>' "$arg"
    done
    printf '\n'
} >> "$DOCKER_LOG"

case ${1:-} in
    info)
        exit "${STUB_INFO_RC:-0}"
        ;;
    inspect)
        printf '%s\n' "${STUB_RUNNING:-true}"
        exit 0
        ;;
    compose)
        case " $* " in
            *' config --images '*)
                printf '%s\n' "${STUB_IMAGE:-open-design-vela:0.21.1-vela0.0.33}"
                exit "${STUB_CONFIG_RC:-0}"
                ;;
        esac
        exit "${STUB_COMPOSE_RC:-0}"
        ;;
    build)
        dd of=/dev/null 2>/dev/null
        exit "${STUB_BUILD_RC:-0}"
        ;;
    exec)
        case " $* " in
            *' mktemp -d /tmp/open-design-import.XXXXXX '*)
                printf '%s\n' /tmp/open-design-import.stub123
                exit 0
                ;;
            *' tar -xf - -C /tmp/open-design-import.stub123 '*)
                dd of=/dev/null 2>/dev/null
                exit "${STUB_TRANSFER_RC:-0}"
                ;;
            *' design-systems import-local /tmp/open-design-import.stub123 '*)
                exit "${STUB_IMPORT_RC:-0}"
                ;;
            *' mkdir /tmp/open-design-sync-lock.'*)
                exit "${STUB_LOCK_RC:-0}"
                ;;
            *' rm -rf /tmp/open-design-sync-lock.'*)
                exit 0
                ;;
            *' mktemp -d /tmp/open-design-sync.XXXXXX '*)
                printf '%s\n' /tmp/open-design-sync.stub456
                exit 0
                ;;
            *' tar -xf - -C /tmp/open-design-sync.stub456 '*)
                dd of=/dev/null 2>/dev/null
                exit "${STUB_SYNC_TRANSFER_RC:-0}"
                ;;
            *'manifest.json schemaVersion '*)
                printf '%s' "${STUB_SYNC_SCHEMA-od-design-system-project/v1}"
                exit "${STUB_SYNC_MANIFEST_RC:-0}"
                ;;
            *'manifest.json id '*)
                printf '%s' "${STUB_SYNC_ID-assistant}"
                exit "${STUB_SYNC_MANIFEST_RC:-0}"
                ;;
            *foreign-source*)
                printf '%s\n' "${STUB_SYNC_STATE:-install}"
                exit 0
                ;;
            *managedBy*)
                exit "${STUB_SYNC_PLACE_RC:-0}"
                ;;
            *' design-systems show '*)
                exit "${STUB_SYNC_SHOW_RC:-0}"
                ;;
            *' mcp --daemon-url http://127.0.0.1:7456 '*)
                if [ -n "${STUB_EXEC_SIGNAL:-}" ]; then
                    kill -"$STUB_EXEC_SIGNAL" "$$"
                fi
                exit "${STUB_EXEC_RC:-0}"
                ;;
        esac
        exit "${STUB_EXEC_RC:-0}"
        ;;
esac
exit 0
STUB

cat > "$STUB_BIN/curl" <<'STUB'
#!/bin/sh
{
    printf 'CALL'
    for arg do
        printf '\t<%s>' "$arg"
    done
    printf '\n'
} >> "$TOOL_LOG"
case " $* " in
    *'/api/health '*) printf '{"status":"ok"}\n' ;;
    *'/api/version '*) printf '{"version":"0.21.1"}\n' ;;
    *'/api/design-systems/install '*)
        printf '{"designSystem":{"id":"user:assistant"}}\n'
        exit "${STUB_INSTALL_RC:-0}"
        ;;
    *' -X DELETE '*)
        exit "${STUB_DELETE_RC:-0}"
        ;;
esac
STUB

cat > "$STUB_BIN/open" <<'STUB'
#!/bin/sh
printf 'CALL\t<%s>\n' "$1" >> "$TOOL_LOG"
STUB

chmod +x "$STUB_BIN/docker" "$STUB_BIN/curl" "$STUB_BIN/open"

TEST_HOME=$TMP_ROOT/home
CONFIG_DIR=$TEST_HOME/.config/open-design
mkdir -p "$CONFIG_DIR" "$TMP_ROOT/commands"
ln -s "$WRAPPER" "$TMP_ROOT/commands/open-design"
ln -s "$WRAPPER" "$TMP_ROOT/commands/open-design-mcp"
OD=$TMP_ROOT/commands/open-design
MCP=$TMP_ROOT/commands/open-design-mcp

export HOME="$TEST_HOME"
export PATH="$STUB_BIN:/usr/bin:/bin"
export DOCKER_LOG TOOL_LOG

: > "$CONFIG_DIR/compose.yaml"
: > "$CONFIG_DIR/Dockerfile"

# The service image is a local derivative, so a missing Dockerfile must fail
# before any Compose call rather than build an unpinned image.
reset_logs
mv "$CONFIG_DIR/Dockerfile" "$CONFIG_DIR/Dockerfile.away"
if "$OD" build > "$TMP_ROOT/nodockerfile.out" 2> "$TMP_ROOT/nodockerfile.err"; then
    fail 'build succeeded without a Dockerfile'
fi
assert_empty "$TMP_ROOT/nodockerfile.out"
assert_contains "$TMP_ROOT/nodockerfile.err" 'Dockerfile not found'
assert_empty "$DOCKER_LOG"
mv "$CONFIG_DIR/Dockerfile.away" "$CONFIG_DIR/Dockerfile"

prefix="CALL\t<compose>\t<--project-directory>\t<$CONFIG_DIR>\t<-f>\t<$CONFIG_DIR/compose.yaml>"

# The image name comes from Compose, and the Dockerfile is fed on stdin with no
# build context, because a context cannot follow the Dotbot symlink and must not
# be widened to the dotfiles checkout.
build_call='CALL\t<build>\t<--tag>\t<open-design-vela:0.21.1-vela0.0.33>\t<->'

# install builds the local derivative first, so a clean machine never starts
# against a missing image, then brings the service up without rebuilding.
reset_logs
"$OD" install
assert_contains "$DOCKER_LOG" "$build_call"
assert_contains "$DOCKER_LOG" "$prefix\t<up>\t<-d>\t<--no-build>\t<--pull>\t<never>\t<--wait>"

reset_logs
"$OD" build
assert_contains "$DOCKER_LOG" "$build_call"
assert_not_contains "$DOCKER_LOG" "$ROOT"

# A Compose file naming an unexpected image must not become a docker build
# argument, and a failing build must propagate.
reset_logs
if STUB_IMAGE='evil; rm -rf /' "$OD" build > "$TMP_ROOT/badimage.out" 2> "$TMP_ROOT/badimage.err"; then
    fail 'build accepted an unexpected image name'
fi
assert_empty "$TMP_ROOT/badimage.out"
assert_not_contains "$DOCKER_LOG" '<build>'

reset_logs
set +e
STUB_BUILD_RC=41 "$OD" build > "$TMP_ROOT/buildfail.out" 2> "$TMP_ROOT/buildfail.err"
build_rc=$?
set -e
[ "$build_rc" -eq 41 ] || fail "build exit status was $build_rc, expected 41"

# Lifecycle commands never rebuild and never reach a registry; image changes go
# through `build`.
reset_logs
"$OD" start
assert_contains "$DOCKER_LOG" "$prefix\t<up>\t<-d>\t<--no-build>\t<--pull>\t<never>\t<--wait>"
assert_not_contains "$DOCKER_LOG" '<build>'

reset_logs
"$OD" stop
assert_contains "$DOCKER_LOG" "$prefix\t<stop>"

reset_logs
"$OD" down
assert_contains "$DOCKER_LOG" "$prefix\t<down>\t<--remove-orphans>"
assert_not_contains "$DOCKER_LOG" '<-v>'
assert_not_contains "$DOCKER_LOG" '<--volumes>'
assert_not_contains "$DOCKER_LOG" '<build>'

reset_logs
"$OD" restart
assert_contains "$DOCKER_LOG" "$prefix\t<up>\t<-d>\t<--no-build>\t<--pull>\t<never>\t<--force-recreate>\t<--wait>"
assert_not_contains "$DOCKER_LOG" '<build>'

reset_logs
"$OD" status
assert_contains "$DOCKER_LOG" "$prefix\t<ps>"

reset_logs
"$OD" logs --tail 7 --since 'two hours ago'
assert_contains "$DOCKER_LOG" "$prefix\t<logs>\t<--tail>\t<7>\t<--since>\t<two hours ago>"

reset_logs
"$OD" open
assert_contains "$TOOL_LOG" 'CALL\t<http://127.0.0.1:7456>'

reset_logs
"$OD" health > "$TMP_ROOT/health.out"
assert_contains "$TOOL_LOG" '<http://127.0.0.1:7456/api/health>'
assert_contains "$TMP_ROOT/health.out" '"status":"ok"'

reset_logs
"$OD" version > "$TMP_ROOT/version.out"
assert_contains "$TOOL_LOG" '<http://127.0.0.1:7456/api/version>'
assert_contains "$TMP_ROOT/version.out" '"version":"0.21.1"'

reset_logs
"$OD" cli project create --name 'Name with spaces' --metadata-json '' --json
assert_contains "$DOCKER_LOG" '<project>\t<create>\t<--name>\t<Name with spaces>\t<--metadata-json>\t<>\t<--json>\t<--daemon-url>\t<http://127.0.0.1:7456>'

"$OD" help > "$TMP_ROOT/help.out"
assert_contains "$TMP_ROOT/help.out" 'import-design-system'
assert_contains "$TMP_ROOT/help.out" 'build'
assert_not_contains "$TMP_ROOT/help.out" 'pull'
if "$OD" pull > "$TMP_ROOT/pull.out" 2> "$TMP_ROOT/pull.err"; then
    fail 'retired pull command still succeeds'
fi
assert_empty "$TMP_ROOT/pull.out"
if "$OD" does-not-exist > "$TMP_ROOT/unknown.out" 2> "$TMP_ROOT/unknown.err"; then
    fail 'unknown command succeeded'
fi
assert_empty "$TMP_ROOT/unknown.out"

# MCP bridge is stdout-clean and propagates docker exit and signal status.
reset_logs
"$MCP" > "$TMP_ROOT/mcp.out" 2> "$TMP_ROOT/mcp.err"
assert_empty "$TMP_ROOT/mcp.out"
assert_empty "$TMP_ROOT/mcp.err"
assert_contains "$DOCKER_LOG" '<exec>\t<-i>\t<open-design>\t<node>\t<apps/daemon/dist/cli.js>\t<mcp>\t<--daemon-url>\t<http://127.0.0.1:7456>'

set +e
STUB_EXEC_RC=37 "$MCP" > "$TMP_ROOT/mcp-exit.out" 2> "$TMP_ROOT/mcp-exit.err"
mcp_rc=$?
set -e
[ "$mcp_rc" -eq 37 ] || fail "MCP exit status was $mcp_rc, expected 37"
assert_empty "$TMP_ROOT/mcp-exit.out"

set +e
STUB_EXEC_SIGNAL=TERM "$MCP" > "$TMP_ROOT/mcp-signal.out" 2> "$TMP_ROOT/mcp-signal.err"
mcp_signal_rc=$?
set -e
[ "$mcp_signal_rc" -eq 143 ] || fail "MCP signal status was $mcp_signal_rc, expected 143"
assert_empty "$TMP_ROOT/mcp-signal.out"

if "$MCP" unexpected > "$TMP_ROOT/mcp-arg.out" 2> "$TMP_ROOT/mcp-arg.err"; then
    fail 'MCP bridge accepted an argument'
fi
assert_empty "$TMP_ROOT/mcp-arg.out"

# Import streams only the selected directory, preserves args (including an
# empty string), and exact-path-cleans container temp data on success/failure.
fixture=$TMP_ROOT/'fixture with spaces'
mkdir -p "$fixture"
printf '# Fixture\n' > "$fixture/DESIGN.md"

reset_logs
"$OD" import-design-system "$fixture" --name 'Fixture with spaces' --craft '' --json
assert_contains "$DOCKER_LOG" '<design-systems>\t<import-local>\t</tmp/open-design-import.stub123>\t<--name>\t<Fixture with spaces>\t<--craft>\t<>\t<--json>\t<--import-mode>\t<hybrid>\t<--daemon-url>\t<http://127.0.0.1:7456>'
assert_contains "$DOCKER_LOG" '<rm>\t<-rf>\t</tmp/open-design-import.stub123>'
assert_not_contains "$DOCKER_LOG" "$fixture"
assert_not_contains "$DOCKER_LOG" "$HOME"
assert_not_contains "$DOCKER_LOG" '<--volume>'
assert_not_contains "$DOCKER_LOG" '<-v>'

reset_logs
set +e
STUB_IMPORT_RC=23 "$OD" import-design-system "$fixture" --json
import_rc=$?
set -e
[ "$import_rc" -eq 23 ] || fail "import exit status was $import_rc, expected 23"
assert_contains "$DOCKER_LOG" '<rm>\t<-rf>\t</tmp/open-design-import.stub123>'

reset_logs
set +e
STUB_TRANSFER_RC=24 "$OD" import-design-system "$fixture" > "$TMP_ROOT/transfer.out" 2> "$TMP_ROOT/transfer.err"
transfer_rc=$?
set -e
[ "$transfer_rc" -ne 0 ] || fail 'failed transfer returned success'
assert_contains "$DOCKER_LOG" '<rm>\t<-rf>\t</tmp/open-design-import.stub123>'

if "$OD" import-design-system / > "$TMP_ROOT/root.out" 2> "$TMP_ROOT/root.err"; then
    fail 'filesystem-root import succeeded'
fi
assert_empty "$TMP_ROOT/root.out"

if "$OD" import-design-system "$TMP_ROOT/missing" > "$TMP_ROOT/missing.out" 2> "$TMP_ROOT/missing.err"; then
    fail 'missing-directory import succeeded'
fi
assert_empty "$TMP_ROOT/missing.out"

# ── sync-package ────────────────────────────────────────────────────────────
# The generic package bridge: stream a finished package into persistent
# container storage, install it once through OpenDesign's own local-install
# API, and update in place afterwards. It must never touch a design system it
# did not install, and must leave the previous one in place when anything fails.

pkg=$TMP_ROOT/'package with spaces'
mkdir -p "$pkg"
printf '{"schemaVersion":"od-design-system-project/v1","id":"assistant"}\n' > "$pkg/manifest.json"
printf '# Fixture\n' > "$pkg/DESIGN.md"
printf ':root { --bg: #fff; }\n' > "$pkg/tokens.css"

# A directory that is not a package is rejected before the container is touched.
for missing in manifest.json DESIGN.md tokens.css; do
    reset_logs
    mv "$pkg/$missing" "$pkg/$missing.away"
    if "$OD" sync-package "$pkg" > "$TMP_ROOT/nopkg.out" 2> "$TMP_ROOT/nopkg.err"; then
        fail "sync-package accepted a directory without $missing"
    fi
    assert_contains "$TMP_ROOT/nopkg.err" 'not a design-system package'
    assert_empty "$DOCKER_LOG"
    mv "$pkg/$missing.away" "$pkg/$missing"
done

# First install: stage, place, call the install API once, then verify.
reset_logs
STUB_SYNC_STATE=install "$OD" sync-package "$pkg" > "$TMP_ROOT/install.out" 2> "$TMP_ROOT/install.err"
assert_contains "$TMP_ROOT/install.out" 'install user:assistant'
assert_contains "$DOCKER_LOG" '<mktemp>\t<-d>\t</tmp/open-design-sync.XXXXXX>'
assert_contains "$DOCKER_LOG" '<tar>\t<-xf>\t<->\t<-C>\t</tmp/open-design-sync.stub456>'
assert_contains "$DOCKER_LOG" '<design-systems>\t<show>\t<user:assistant>'
assert_contains "$TOOL_LOG" '<http://127.0.0.1:7456/api/design-systems/install>'
assert_contains "$TOOL_LOG" '<{"source":"local","path":"/app/.od/design-system-sources/assistant"}>'
# The host path never reaches the container, and nothing is mounted.
assert_not_contains "$DOCKER_LOG" "$pkg"
assert_not_contains "$DOCKER_LOG" '<--volume>'
assert_not_contains "$DOCKER_LOG" '<-v>'

# Update: the catalog symlink already points at our source, so the install API
# is not called again.
reset_logs
STUB_SYNC_STATE=update "$OD" sync-package "$pkg" > "$TMP_ROOT/update.out" 2> "$TMP_ROOT/update.err"
assert_contains "$TMP_ROOT/update.out" 'update user:assistant'
assert_not_contains "$TOOL_LOG" '/api/design-systems/install'

# Collisions with anything this command did not install are refused, and
# nothing is placed.
reset_logs
if STUB_SYNC_STATE=foreign-source "$OD" sync-package "$pkg" > "$TMP_ROOT/fsrc.out" 2> "$TMP_ROOT/fsrc.err"; then
    fail 'sync-package overwrote an unmanaged source directory'
fi
assert_contains "$TMP_ROOT/fsrc.err" 'not installed by this command'
assert_not_contains "$DOCKER_LOG" 'managedBy'

reset_logs
if STUB_SYNC_STATE=foreign-link "$OD" sync-package "$pkg" > "$TMP_ROOT/flink.out" 2> "$TMP_ROOT/flink.err"; then
    fail 'sync-package replaced an unrelated design system'
fi
assert_contains "$TMP_ROOT/flink.err" 'already installed'
assert_not_contains "$DOCKER_LOG" 'managedBy'

# A manifest the bridge does not understand stops before anything is placed.
reset_logs
if STUB_SYNC_SCHEMA=od-design-system-project/v2 "$OD" sync-package "$pkg" > "$TMP_ROOT/schema.out" 2> "$TMP_ROOT/schema.err"; then
    fail 'sync-package accepted an unknown schemaVersion'
fi
assert_contains "$TMP_ROOT/schema.err" 'unsupported manifest schemaVersion'
assert_contains "$DOCKER_LOG" '<rm>\t<-rf>\t</tmp/open-design-sync.stub456>'

reset_logs
if STUB_SYNC_ID='../escape' "$OD" sync-package "$pkg" > "$TMP_ROOT/badid.out" 2> "$TMP_ROOT/badid.err"; then
    fail 'sync-package accepted an unsafe id'
fi
assert_contains "$TMP_ROOT/badid.err" 'unsafe design-system id'

# A failed transfer, a failed placement, a refused install and a package that
# does not validate all roll back and report failure.
reset_logs
set +e
STUB_SYNC_TRANSFER_RC=24 "$OD" sync-package "$pkg" > "$TMP_ROOT/xfer.out" 2> "$TMP_ROOT/xfer.err"
xfer_rc=$?
set -e
[ "$xfer_rc" -ne 0 ] || fail 'failed transfer returned success'
assert_contains "$TMP_ROOT/xfer.err" 'failed to stream the package'
assert_contains "$DOCKER_LOG" '<rm>\t<-rf>\t</tmp/open-design-sync.stub456>'

reset_logs
set +e
STUB_SYNC_PLACE_RC=9 "$OD" sync-package "$pkg" > "$TMP_ROOT/place.out" 2> "$TMP_ROOT/place.err"
place_rc=$?
set -e
[ "$place_rc" -ne 0 ] || fail 'failed placement returned success'
assert_contains "$TMP_ROOT/place.err" 'failed to install the package'

reset_logs
set +e
STUB_INSTALL_RC=22 STUB_SYNC_STATE=install "$OD" sync-package "$pkg" > "$TMP_ROOT/api.out" 2> "$TMP_ROOT/api.err"
api_rc=$?
set -e
[ "$api_rc" -ne 0 ] || fail 'refused install returned success'
assert_contains "$TMP_ROOT/api.err" 'refused to install'
# Rollback restores the previous source directory.
assert_contains "$DOCKER_LOG" '/app/.od/design-system-sources/.backup-assistant'

reset_logs
set +e
STUB_SYNC_SHOW_RC=1 STUB_SYNC_STATE=update "$OD" sync-package "$pkg" > "$TMP_ROOT/show.out" 2> "$TMP_ROOT/show.err"
show_rc=$?
set -e
[ "$show_rc" -ne 0 ] || fail 'unvalidated package returned success'
assert_contains "$TMP_ROOT/show.err" 'previous state restored'
assert_contains "$DOCKER_LOG" '/app/.od/design-system-sources/.backup-assistant'

# Argument handling.
if "$OD" sync-package > "$TMP_ROOT/noarg.out" 2> "$TMP_ROOT/noarg.err"; then
    fail 'sync-package accepted no arguments'
fi
assert_contains "$TMP_ROOT/noarg.err" 'usage: open-design sync-package'

if "$OD" sync-package "$pkg" extra > "$TMP_ROOT/extra.out" 2> "$TMP_ROOT/extra.err"; then
    fail 'sync-package accepted extra arguments'
fi
assert_contains "$TMP_ROOT/extra.err" 'usage: open-design sync-package'

if "$OD" sync-package / > "$TMP_ROOT/syncroot.out" 2> "$TMP_ROOT/syncroot.err"; then
    fail 'sync-package accepted the filesystem root'
fi

if "$OD" sync-package "$TMP_ROOT/missing-package" > "$TMP_ROOT/syncmissing.out" 2> "$TMP_ROOT/syncmissing.err"; then
    fail 'sync-package accepted a missing directory'
fi

# One writer per design system: the lock is taken before any state changes and
# released on the way out, and a second run refuses instead of racing over the
# same source directory, backup and catalog entry.
reset_logs
STUB_SYNC_STATE=update "$OD" sync-package "$pkg" > "$TMP_ROOT/lock.out" 2> "$TMP_ROOT/lock.err"
assert_contains "$DOCKER_LOG" '<mkdir>\t</tmp/open-design-sync-lock.assistant>'
assert_contains "$DOCKER_LOG" '<rm>\t<-rf>\t</tmp/open-design-sync-lock.assistant>'
# The lock is taken before the package is placed.
lock_line=$(grep -n 'open-design-sync-lock.assistant>' "$DOCKER_LOG" | head -1 | cut -d: -f1)
place_line=$(grep -n 'managedBy' "$DOCKER_LOG" | head -1 | cut -d: -f1)
[ "$lock_line" -lt "$place_line" ] || fail 'the lock is taken after the package is placed'

reset_logs
if STUB_LOCK_RC=1 "$OD" sync-package "$pkg" > "$TMP_ROOT/busy.out" 2> "$TMP_ROOT/busy.err"; then
    fail 'a second concurrent sync-package run was allowed'
fi
assert_contains "$TMP_ROOT/busy.err" 'holds the lock'
assert_not_contains "$DOCKER_LOG" 'managedBy'
assert_not_contains "$DOCKER_LOG" 'foreign-source'
# Losing the race must not delete the lock the winner holds.
assert_not_contains "$DOCKER_LOG" '<rm>\t<-rf>\t</tmp/open-design-sync-lock.assistant>'

# Rolling back a fresh install goes through the API, so the daemon also drops
# the workspace binding; unlinking the catalog symlink directly would not.
reset_logs
set +e
STUB_SYNC_SHOW_RC=1 STUB_SYNC_STATE=install "$OD" sync-package "$pkg" > "$TMP_ROOT/undo.out" 2> "$TMP_ROOT/undo.err"
undo_rc=$?
set -e
[ "$undo_rc" -ne 0 ] || fail 'unvalidated fresh install returned success'
assert_contains "$TOOL_LOG" '<-X>\t<DELETE>\t<http://127.0.0.1:7456/api/design-systems/user:assistant>'
assert_not_contains "$DOCKER_LOG" '<rm>\t<-f>\t</app/.od/design-systems/assistant>'
assert_contains "$DOCKER_LOG" '.backup-assistant-'

# If the daemon will not drop the entry, the package stays installed and the
# source is left alone rather than pulled out from under a live catalog entry.
reset_logs
set +e
STUB_SYNC_SHOW_RC=1 STUB_DELETE_RC=7 STUB_SYNC_STATE=install "$OD" sync-package "$pkg" > "$TMP_ROOT/undo2.out" 2> "$TMP_ROOT/undo2.err"
undo2_rc=$?
set -e
[ "$undo2_rc" -ne 0 ] || fail 'failed rollback returned success'
assert_contains "$TMP_ROOT/undo2.err" 'leaving the installed package in place'
# The restore step (its script is the only one that moves a backup back) must
# not run: the catalog entry is still live and needs its source.
# shellcheck disable=SC2016  # matching the container-side script text verbatim
assert_not_contains "$DOCKER_LOG" 'if [ -d "$2" ]; then mv "$2" "$1"; fi'

# Backups are named per run, so a crashed earlier run cannot leave one that a
# later run would delete.
reset_logs
STUB_SYNC_STATE=update "$OD" sync-package "$pkg" > "$TMP_ROOT/backup.out" 2> "$TMP_ROOT/backup.err"
backup_name=$(grep -o '\.backup-assistant-[A-Za-z0-9]*' "$DOCKER_LOG" | head -1)
[ -n "$backup_name" ] || fail 'no per-run backup name was used'
[ "$backup_name" != '.backup-assistant-' ] || fail 'the backup name carries no run suffix'

printf 'PASS: OpenDesign dispatcher stub suite\n'
