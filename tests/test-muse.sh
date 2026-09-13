#!/bin/sh
# Tests for scripts/muse-settings-merge.sh.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=$ROOT/scripts/muse-settings-merge.sh
SETTINGS=$ROOT/muse/settings.json
SERVERS=$ROOT/claude/mcpServers.json
INSTALL=$ROOT/install.conf.yaml
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-muse.XXXXXX")
TEST_HOME=$TMP_ROOT/home
TARGET=$TEST_HOME/.config/muse/settings.json

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

fresh_install_has_managed_settings() {
    HOME=$TEST_HOME sh "$SCRIPT" "$TARGET" "$SETTINGS" "$SERVERS" >/dev/null 2>&1 &&
        jq -e --slurpfile servers "$SERVERS" '
            .model == "muse-spark-1.3" and
            .reasoning_effort == "max" and
            .schema_version == 1 and
            .mcpServers == $servers[0] and
            (has("mcp_servers") | not)
        ' "$TARGET" >/dev/null
}

check 'fresh install creates the complete managed Muse settings' \
    fresh_install_has_managed_settings

has_runtime_state() {
    jq -e '
        .runtime_nonce == "keep-me" and
        .tui.foreign_context_notice_shown == true
    ' "$1" >/dev/null
}

existing_runtime_key_survives() {
    runtime_home=$TMP_ROOT/runtime-home
    runtime_target=$runtime_home/.config/muse/settings.json
    mkdir -p "$(dirname "$runtime_target")"
    printf '%s\n' \
        '{"model":"old","runtime_nonce":"keep-me","tui":{"foreign_context_notice_shown":true}}' \
        >"$runtime_target"

    HOME=$runtime_home sh "$SCRIPT" "$runtime_target" "$SETTINGS" "$SERVERS" \
        >/dev/null 2>&1 &&
        has_runtime_state "$runtime_target" &&
        jq -e '
            .schema_version == 1 and
            .model == "muse-spark-1.3" and
            .reasoning_effort == "max"
        ' "$runtime_target" >/dev/null
}

check "existing Muse-owned runtime keys survive" existing_runtime_key_survives

runtime_preservation_negative_control() {
    jq 'del(.runtime_nonce)' "$runtime_target" >"$TMP_ROOT/runtime-negative.json"
    ! has_runtime_state "$TMP_ROOT/runtime-negative.json"
}

check 'negative control detects a clobbered runtime key' \
    runtime_preservation_negative_control

second_merge_is_byte_identical() {
    idem_home=$TMP_ROOT/idempotent-home
    idem_target=$idem_home/.config/muse/settings.json
    HOME=$idem_home sh "$SCRIPT" "$idem_target" "$SETTINGS" "$SERVERS" \
        >/dev/null 2>&1 || return 1
    cp "$idem_target" "$TMP_ROOT/first-merge"
    HOME=$idem_home sh "$SCRIPT" "$idem_target" "$SETTINGS" "$SERVERS" \
        >/dev/null 2>&1 || return 1
    cmp -s "$TMP_ROOT/first-merge" "$idem_target"
}

check 'second merge is byte-identical' second_merge_is_byte_identical

byte_comparison_negative_control() {
    cp "$TMP_ROOT/first-merge" "$TMP_ROOT/changed-merge"
    printf '\n' >>"$TMP_ROOT/changed-merge"
    ! cmp -s "$TMP_ROOT/first-merge" "$TMP_ROOT/changed-merge"
}

check 'negative control detects changed merge bytes' \
    byte_comparison_negative_control

has_canonical_mcp_state() {
    candidate=$1
    jq -e --slurpfile servers "$SERVERS" '
        ($servers[0] | keys) as $managed_keys |
        .mcpServers as $actual |
        (has("mcp_servers") | not) and
        all($managed_keys[]; . as $key | $actual[$key] == $servers[0][$key])
    ' "$candidate" >/dev/null
}

snake_case_collision_is_removed() {
    collision_home=$TMP_ROOT/collision-home
    collision_target=$collision_home/.config/muse/settings.json
    mkdir -p "$(dirname "$collision_target")"
    printf '%s\n' \
        '{"mcp_servers":{"legacy-local":{"type":"stdio","command":"legacy"}},"mcpServers":{"machine-local":{"type":"stdio","command":"local"},"serena":{"type":"stdio","command":"wrong"}},"runtime_nonce":"keep-me"}' \
        >"$collision_target"

    HOME=$collision_home sh "$SCRIPT" "$collision_target" "$SETTINGS" "$SERVERS" \
        >/dev/null 2>&1 &&
        has_canonical_mcp_state "$collision_target" &&
        jq -e '
            .runtime_nonce == "keep-me" and
            .mcpServers["legacy-local"].command == "legacy" and
            .mcpServers["machine-local"].command == "local"
        ' "$collision_target" >/dev/null
}

check 'MCP merge preserves local servers, removes snake_case, and lets the tracked source win' \
    snake_case_collision_is_removed

mcp_collision_negative_control() {
    jq '.mcp_servers = {"wrong": {}}' "$collision_target" \
        >"$TMP_ROOT/collision-negative.json"
    ! has_canonical_mcp_state "$TMP_ROOT/collision-negative.json"
}

check 'negative control detects both MCP key spellings' \
    mcp_collision_negative_control

merge_assertion_rejects_managed_snake_case_key() {
    assertion_home=$TMP_ROOT/assertion-home
    assertion_target=$assertion_home/.config/muse/settings.json
    mkdir -p "$(dirname "$assertion_target")"
    printf '%s\n' '{"runtime_nonce":"keep-me"}' >"$assertion_target"
    cp "$assertion_target" "$TMP_ROOT/assertion-before.json"
    printf '%s\n' \
        '{"model":"muse-spark-1.3","reasoning_effort":"max","mcp_servers":{}}' \
        >"$TMP_ROOT/settings-with-snake.json"

    if HOME=$assertion_home sh "$SCRIPT" "$assertion_target" \
        "$TMP_ROOT/settings-with-snake.json" "$SERVERS" \
        >"$TMP_ROOT/assertion.out" 2>&1; then
        return 1
    fi
    grep -Fq 'ERROR: refusing Muse settings with both MCP key spellings' \
        "$TMP_ROOT/assertion.out" &&
        cmp -s "$TMP_ROOT/assertion-before.json" "$assertion_target"
}

check 'negative control makes the script assertion reject snake_case input' \
    merge_assertion_rejects_managed_snake_case_key

is_noncontributor_model() {
    jq -e '.model == "muse-spark-1.3"' "$1" >/dev/null
}

check 'managed model is literally muse-spark-1.3' \
    is_noncontributor_model "$TARGET"

contributor_model_negative_control() {
    jq '.model = "muse-spark-1.3-contributor"' "$TARGET" \
        >"$TMP_ROOT/contributor-negative.json"
    ! is_noncontributor_model "$TMP_ROOT/contributor-negative.json"
}

check 'negative control rejects contributor-tier model' \
    contributor_model_negative_control

has_schema_version_one() {
    jq -e '.schema_version == 1' "$1" >/dev/null
}

check 'fresh settings carry schema_version 1' has_schema_version_one "$TARGET"

schema_version_negative_control() {
    jq '.schema_version = 0' "$TARGET" >"$TMP_ROOT/schema-negative.json"
    ! has_schema_version_one "$TMP_ROOT/schema-negative.json"
}

check 'negative control rejects wrong schema_version' \
    schema_version_negative_control

mode_is_600() {
    [ -n "$(find "$1" -perm 600 -print)" ]
}

check 'merged settings file has mode 0600' mode_is_600 "$TARGET"

mode_negative_control() {
    cp "$TARGET" "$TMP_ROOT/world-readable.json"
    chmod 644 "$TMP_ROOT/world-readable.json"
    ! mode_is_600 "$TMP_ROOT/world-readable.json"
}

check 'negative control rejects mode 0644' mode_negative_control

no_jq_is_a_visible_noop() {
    no_jq_home=$TMP_ROOT/no-jq-home
    no_jq_target=$no_jq_home/.config/muse/settings.json
    mkdir -p "$TMP_ROOT/empty-path"
    PATH=$TMP_ROOT/empty-path HOME=$no_jq_home /bin/sh "$SCRIPT" \
        "$no_jq_target" "$SETTINGS" "$SERVERS" \
        >"$TMP_ROOT/no-jq.out" 2>&1 &&
        grep -Fq 'WARNING: jq not found, skipping Muse settings merge' \
            "$TMP_ROOT/no-jq.out" &&
        [ ! -e "$no_jq_target" ]
}

check 'missing jq warns, exits zero, and writes nothing' no_jq_is_a_visible_noop

no_jq_warning_negative_control() {
    printf '%s\n' 'Muse settings unchanged' >"$TMP_ROOT/no-jq-negative.out"
    ! grep -Fq 'WARNING: jq not found, skipping Muse settings merge' \
        "$TMP_ROOT/no-jq-negative.out"
}

check 'negative control rejects a silent jq skip' \
    no_jq_warning_negative_control

installer_wires_muse_merge() {
    # $HOME must remain literal in the tracked Dotbot command.
    # shellcheck disable=SC2016
    grep -Fqx \
        '    - command: scripts/muse-settings-merge.sh "$HOME/.config/muse/settings.json" muse/settings.json claude/mcpServers.json' \
        "$1"
}

check 'Dotbot install invokes the Muse merge with tracked sources' \
    installer_wires_muse_merge "$INSTALL"

installer_wiring_negative_control() {
    sed '/scripts\/muse-settings-merge\.sh/d' "$INSTALL" \
        >"$TMP_ROOT/install-without-muse.yaml"
    ! installer_wires_muse_merge "$TMP_ROOT/install-without-muse.yaml"
}

check 'negative control detects missing Dotbot Muse wiring' \
    installer_wiring_negative_control

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
