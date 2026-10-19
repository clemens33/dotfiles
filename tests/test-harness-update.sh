#!/usr/bin/env bash
# Integration tests for scripts/harness-update.sh retry supervision.
set -uo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=$ROOT/scripts/harness-update.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-harness-update.XXXXXX")

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

check() {
  local description=$1
  shift
  if "$@"; then ok "$description"; else bad "$description"; fi
}

make_fake_home() {
  local name=$1
  local fake_home="$TMP_ROOT/$name/home"
  mkdir -p "$fake_home/.local/bin"

  cat >"$fake_home/.local/bin/agy" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    printf '1.2.2\n'
    ;;
  update|changelog)
    count=$(cat "$FAKE_AGY_STATE")
    count=$((count + 1))
    printf '%s\n' "$count" >"$FAKE_AGY_STATE"
    printf '%s %s\n' "$1" "$count" >>"$FAKE_AGY_CALLS"
    if [ "$count" -le "$FAKE_AGY_FAILURES" ]; then
      exit 42
    fi
    if [ "$1" = changelog ]; then
      printf '1.2.3:\n'
      # Optional bulk after the newest entry, like the real multi-release log.
      if [ "${FAKE_AGY_CHANGELOG_LINES:-0}" -gt 0 ]; then
        awk -v n="$FAKE_AGY_CHANGELOG_LINES" \
          'BEGIN { for (i = 0; i < n; i++) print "· older release note line"; print "1.2.2:" }'
      fi
    fi
    ;;
  *)
    exit 2
    ;;
esac
EOF

  cat >"$fake_home/.local/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$FAKE_SLEEP_CALLS"
if [ "${FAKE_SLEEP_REAL:-0}" -eq 1 ]; then
  /bin/sleep "$1"
fi
EOF

  chmod +x "$fake_home/.local/bin/agy" "$fake_home/.local/bin/sleep"
  printf '0\n' >"$TMP_ROOT/$name/agy.state"
  : >"$TMP_ROOT/$name/agy.calls"
  : >"$TMP_ROOT/$name/sleep.calls"
  printf '%s\n' "$fake_home"
}

run_agy() {
  local name=$1
  local failures=$2
  local mode=${3:-update}
  local timeout=${4:-10}
  local real_sleep=${5:-0}
  local updater=${6:-$SCRIPT}
  local fake_home
  local check_arg=""
  fake_home=$(make_fake_home "$name")
  if [ "$mode" = check ]; then check_arg=--check; fi

  env \
    HOME="$fake_home" \
    FAKE_AGY_STATE="$TMP_ROOT/$name/agy.state" \
    FAKE_AGY_CALLS="$TMP_ROOT/$name/agy.calls" \
    FAKE_AGY_FAILURES="$failures" \
    FAKE_SLEEP_CALLS="$TMP_ROOT/$name/sleep.calls" \
    FAKE_SLEEP_REAL="$real_sleep" \
    HARNESS_UPDATE_TIMEOUT_SECONDS="$timeout" \
    "$updater" $check_arg --only agy >"$TMP_ROOT/$name/output" 2>&1
}

transient_failure_recovers() {
  local name=transient
  local log
  run_agy "$name" 2 update || return 1
  log="$TMP_ROOT/$name/home/.local/state/harness-update/$(date +%F).log"

  [ "$(wc -l <"$TMP_ROOT/$name/agy.calls" | tr -d ' ')" -eq 3 ] &&
    grep -Fq 'agy ATTEMPT 1/3' "$log" &&
    grep -Fq 'agy RETRY after attempt 1/3; backoff=5s' "$log" &&
    grep -Fq 'agy ATTEMPT 2/3' "$log" &&
    grep -Fq 'agy RETRY after attempt 2/3; backoff=20s' "$log" &&
    grep -Fq 'agy ATTEMPT 3/3' "$log" &&
    grep -Fq 'agy OK 1.2.2 -> 1.2.2' "$TMP_ROOT/$name/output" &&
    [ "$(printf '5\n20\n')" = "$(cat "$TMP_ROOT/$name/sleep.calls")" ]
}

check 'fake agy failing twice succeeds on attempt 3 with both retries logged' \
  transient_failure_recovers

exhausted_failure_reports_once() {
  local name=exhausted
  local status log
  if run_agy "$name" 99 update; then
    return 1
  else
    status=$?
  fi
  log="$TMP_ROOT/$name/home/.local/state/harness-update/$(date +%F).log"

  [ "$status" -eq 1 ] &&
    [ "$(wc -l <"$TMP_ROOT/$name/agy.calls" | tr -d ' ')" -eq 3 ] &&
    [ "$(grep -c '^agy FAIL ' "$log")" -eq 1 ] &&
    grep -Fq 'harness update finish exit=1' "$log"
}

check 'three failed attempts report one FAIL and count once in exit status' \
  exhausted_failure_reports_once

timeout_stops_retries() {
  local name=timeout
  local status log
  if run_agy "$name" 99 update 1 1; then
    return 1
  else
    status=$?
  fi
  log="$TMP_ROOT/$name/home/.local/state/harness-update/$(date +%F).log"

  [ "$status" -eq 1 ] &&
    [ "$(wc -l <"$TMP_ROOT/$name/agy.calls" | tr -d ' ')" -eq 1 ] &&
    grep -Fq 'agy RETRY after attempt 1/3; backoff=5s' "$log" &&
    grep -Fq 'agy FAIL timed out after 1s' "$log" &&
    ! grep -Fq 'agy ATTEMPT 2/3' "$log"
}

check 'whole-step timeout expires during backoff before attempt 2' \
  timeout_stops_retries

dsh_failure_is_not_retried() {
  local name=dsh
  local fake_home variant status log
  fake_home=$(make_fake_home "$name")
  variant="$TMP_ROOT/$name/harness-update.sh"
  awk '
    /^# Export existing step functions/ {
      print "process_dsh() {"
      print "  count=$(cat \"$FAKE_DSH_STATE\")"
      print "  count=$((count + 1))"
      print "  printf \"%s\\n\" \"$count\" >\"$FAKE_DSH_STATE\""
      print "  summary \"dsh FAIL forced drift\""
      print "  return 1"
      print "}"
      print ""
    }
    { print }
  ' "$SCRIPT" >"$variant"
  printf '0\n' >"$TMP_ROOT/$name/dsh.state"

  if env \
    HOME="$fake_home" \
    FAKE_DSH_STATE="$TMP_ROOT/$name/dsh.state" \
    FAKE_SLEEP_CALLS="$TMP_ROOT/$name/sleep.calls" \
    HARNESS_UPDATE_TIMEOUT_SECONDS=10 \
    bash "$variant" --check --only dsh >"$TMP_ROOT/$name/output" 2>&1; then
    return 1
  else
    status=$?
  fi
  log="$fake_home/.local/state/harness-update/$(date +%F).log"

  [ "$status" -eq 1 ] &&
    [ "$(cat "$TMP_ROOT/$name/dsh.state")" -eq 1 ] &&
    [ "$(grep -c '^dsh FAIL forced drift$' "$log")" -eq 1 ] &&
    ! grep -Fq 'dsh RETRY' "$log"
}

check 'dsh failing drift audit runs once without retry' \
  dsh_failure_is_not_retried

contract_failure_is_not_retried() {
  local name=contract
  local fake_home variant status log
  fake_home=$(make_fake_home "$name")
  variant="$TMP_ROOT/$name/harness-update.sh"
  awk '
    /^# Export existing step functions/ {
      print "process_contract() {"
      print "  count=$(cat \"$FAKE_CONTRACT_STATE\")"
      print "  count=$((count + 1))"
      print "  printf \"%s\\n\" \"$count\" >\"$FAKE_CONTRACT_STATE\""
      print "  summary \"contract FAIL forced local check\""
      print "  return 1"
      print "}"
      print ""
    }
    { print }
  ' "$SCRIPT" >"$variant"
  printf '0\n' >"$TMP_ROOT/$name/contract.state"

  if env \
    HOME="$fake_home" \
    FAKE_CONTRACT_STATE="$TMP_ROOT/$name/contract.state" \
    FAKE_SLEEP_CALLS="$TMP_ROOT/$name/sleep.calls" \
    HARNESS_UPDATE_TIMEOUT_SECONDS=10 \
    bash "$variant" --check --only contract >"$TMP_ROOT/$name/output" 2>&1; then
    return 1
  else
    status=$?
  fi
  log="$fake_home/.local/state/harness-update/$(date +%F).log"

  [ "$status" -eq 1 ] &&
    [ "$(cat "$TMP_ROOT/$name/contract.state")" -eq 1 ] &&
    [ "$(grep -c '^contract FAIL forced local check$' "$log")" -eq 1 ] &&
    ! grep -Fq 'contract RETRY' "$log"
}

check 'contract failing deterministic check runs once without retry' \
  contract_failure_is_not_retried

check_mode_lookup_is_retried() {
  local name=check-mode
  local log
  run_agy "$name" 1 check || return 1
  log="$TMP_ROOT/$name/home/.local/state/harness-update/$(date +%F).log"

  [ "$(wc -l <"$TMP_ROOT/$name/agy.calls" | tr -d ' ')" -eq 2 ] &&
    grep -Fq 'agy RETRY after attempt 1/3; backoff=5s' "$log" &&
    grep -Fq 'agy CHECK current=1.2.2 latest=1.2.3' "$TMP_ROOT/$name/output"
}

check 'check-mode latest lookup recovers on attempt 2' \
  check_mode_lookup_is_retried

# The real `agy changelog` is >150 KB, far past the 64 KB pipe buffer. Reading
# only its first entry must not turn the early-closed pipe into a lookup failure.
check_mode_large_changelog() {
  local name=large-changelog
  FAKE_AGY_CHANGELOG_LINES=8000 run_agy "$name" 0 check || return 1

  [ "$(wc -l <"$TMP_ROOT/$name/agy.calls" | tr -d ' ')" -eq 1 ] &&
    grep -Fq 'agy CHECK current=1.2.2 latest=1.2.3' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'lookup failed' "$TMP_ROOT/$name/output"
}

check 'check-mode latest lookup survives a changelog larger than the pipe buffer' \
  check_mode_large_changelog

retry_removal_negative_control() {
  local name=no-retry
  local variant="$TMP_ROOT/$name/harness-update.sh"
  local status retry_call="run_with_retry \"\$1\""
  mkdir -p "$TMP_ROOT/$name"

  [ "$(grep -Fo "$retry_call" "$SCRIPT" | wc -l | tr -d ' ')" -eq 1 ] ||
    return 1
  # shellcheck disable=SC2016 # Mutate the literal child-shell call, not this test's $1.
  sed 's/run_with_retry "$1"/"process_$1"/' "$SCRIPT" >"$variant"
  chmod +x "$variant"
  ! grep -Fq "$retry_call" "$variant" || return 1

  if run_agy "$name" 2 update 10 0 "$variant"; then
    return 1
  else
    status=$?
  fi
  [ "$status" -eq 1 ] &&
    [ "$(wc -l <"$TMP_ROOT/$name/agy.calls" | tr -d ' ')" -eq 1 ]
}

check 'negative control rejects updater with retry loop removed' \
  retry_removal_negative_control

make_fake_muse_home() {
  local name=$1
  local fake_home
  fake_home=$(make_fake_home "$name")

  cat >"$fake_home/.local/bin/muse" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    printf 'Muse Code 1.2.1 (1.2.1-R2847.1)\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF

  cat >"$fake_home/.local/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_MUSE_CURL_CALLS"
code=200
case "${FAKE_MUSE_CURL_MODE:-ok}" in
  ok) ;;
  auth) code=401 ;;
  server) code=500 ;;
  *) exit 7 ;;
esac
cat "$FAKE_MUSE_CURL_BODY" 2>/dev/null || true
format=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--write-out" ]; then
    format=${2:-}
    shift
  fi
  shift
done
[ -z "$format" ] || printf '%b' "${format//'%{http_code}'/$code}"
EOF

  chmod +x "$fake_home/.local/bin/muse" "$fake_home/.local/bin/curl"
  printf '%s\n' "$fake_home"
}

run_muse() {
  local name=$1
  local body=$2
  local mode=${3:-ok}
  local channel_url=${4:-}
  local updater=${5:-$SCRIPT}
  local fake_home
  fake_home=$(make_fake_muse_home "$name")
  printf '%s\n' "$body" >"$TMP_ROOT/$name/channel.json"
  : >"$TMP_ROOT/$name/curl.calls"

  if [ -n "$channel_url" ]; then
    env HOME="$fake_home" \
      FAKE_MUSE_CURL_BODY="$TMP_ROOT/$name/channel.json" \
      FAKE_MUSE_CURL_MODE="$mode" \
      FAKE_MUSE_CURL_CALLS="$TMP_ROOT/$name/curl.calls" \
      MUSE_CHANNEL_URL="$channel_url" \
      HARNESS_UPDATE_TIMEOUT_SECONDS=10 \
      "$updater" --check --only muse >"$TMP_ROOT/$name/output" 2>&1
  else
    env -u MUSE_CHANNEL_URL HOME="$fake_home" \
      FAKE_MUSE_CURL_BODY="$TMP_ROOT/$name/channel.json" \
      FAKE_MUSE_CURL_MODE="$mode" \
      FAKE_MUSE_CURL_CALLS="$TMP_ROOT/$name/curl.calls" \
      HARNESS_UPDATE_TIMEOUT_SECONDS=10 \
      "$updater" --check --only muse >"$TMP_ROOT/$name/output" 2>&1
  fi
}

MUSE_CHANNEL_BODY='{"channel":"muse-stable","version":"1.2.2-R2848.1","manifest_url":"https://lookaside.facebook.com/x","urgency":"none","notification_text":""}'

muse_channel_version_reported() {
  local name=muse-latest
  run_muse "$name" "$MUSE_CHANNEL_BODY" || return 1
  grep -Fq 'muse CHECK current=1.2.1-R2847.1 latest=1.2.2-R2848.1' "$TMP_ROOT/$name/output" &&
    grep -Fq 'https://api.meta.ai/muse-code/channels/muse-stable' "$TMP_ROOT/$name/curl.calls"
}

check 'muse check reports the channel version from the vendor default URL' \
  muse_channel_version_reported

muse_invalid_manifest_rejected() {
  local name=muse-invalid
  run_muse "$name" '{"channel":"muse-stable","version":"main"}' || return 1
  grep -Fq 'muse CHECK current=1.2.1-R2847.1 latest=unknown (invalid channel manifest)' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'latest=main' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'latest=1.2' "$TMP_ROOT/$name/output"
}

check 'muse check rejects a manifest whose version is not a release version' \
  muse_invalid_manifest_rejected

muse_unreachable_is_not_fatal() {
  local name=muse-unreachable
  run_muse "$name" "$MUSE_CHANNEL_BODY" fail || return 1
  grep -Fq 'muse CHECK current=1.2.1-R2847.1 latest=unknown (channel unreachable)' "$TMP_ROOT/$name/output"
}

check 'muse check with an unreachable channel stays exit 0 and says why' \
  muse_unreachable_is_not_fatal

muse_unreachable_negative_control() {
  local name=muse-unreachable-control
  run_muse "$name" "$MUSE_CHANNEL_BODY" ok || return 1
  ! grep -Fq 'latest=unknown' "$TMP_ROOT/$name/output" &&
    grep -Fq 'latest=1.2.2-R2848.1' "$TMP_ROOT/$name/output"
}

check 'negative control: a healthy channel never reports unknown' \
  muse_unreachable_negative_control

muse_auth_denial_names_the_reason() {
  local name=muse-auth
  run_muse "$name" '{}' auth || return 1
  grep -Fq 'muse CHECK current=1.2.1-R2847.1 latest=unknown (channel requires auth)' "$TMP_ROOT/$name/output"
}

check 'muse check names an auth-denied channel instead of guessing' \
  muse_auth_denial_names_the_reason

muse_http_error_negative_control() {
  local name=muse-server
  run_muse "$name" '{}' server || return 1
  grep -Fq 'latest=unknown (channel returned HTTP 500)' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'latest=unknown (channel requires auth)' "$TMP_ROOT/$name/output"
}

check 'negative control: a 500 is reported as HTTP, not as an auth denial' \
  muse_http_error_negative_control

muse_channel_override_is_honored() {
  local name=muse-override
  run_muse "$name" "$MUSE_CHANNEL_BODY" ok 'https://channels.example.test/muse-qa' || return 1
  grep -Fq 'https://channels.example.test/muse-qa' "$TMP_ROOT/$name/curl.calls" &&
    ! grep -Fq 'api.meta.ai/muse-code/channels' "$TMP_ROOT/$name/curl.calls"
}

check 'muse check honors MUSE_CHANNEL_URL without a second hardcoded URL' \
  muse_channel_override_is_honored

muse_lookup_removal_negative_control() {
  local name=muse-no-lookup
  local variant="$TMP_ROOT/$name/harness-update.sh"
  local status
  mkdir -p "$TMP_ROOT/$name"

  [ "$(grep -c '^muse_latest() {$' "$SCRIPT" | tr -d ' ')" -eq 1 ] || return 1
  sed 's/^muse_latest() {$/muse_latest() { return 1;/' "$SCRIPT" >"$variant"
  chmod +x "$variant"
  grep -Fq 'muse_latest() { return 1;' "$variant" || return 1

  if run_muse "$name" "$MUSE_CHANNEL_BODY" ok '' "$variant"; then
    status=0
  else
    status=$?
  fi
  [ "$status" -eq 0 ] &&
    grep -Fq 'muse CHECK current=1.2.1-R2847.1 latest=unknown' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'latest=1.2.2-R2848.1' "$TMP_ROOT/$name/output"
}

check 'negative control rejects the updater with the muse lookup removed' \
  muse_lookup_removal_negative_control

# --- effective-binary lag -------------------------------------------------
# The pain: npm installs a newer opencode-ai, but the opencode first on PATH is a
# stale link into a different tree and keeps printing the old version. Real
# mise/npm must never be reachable, so stub both ahead of them on PATH.

make_fake_opencode_home() {
  local name=$1
  local bin_version=$2
  local held_version=$3
  local fake_home dir
  fake_home=$(make_fake_home "$name")
  dir="$TMP_ROOT/$name"
  mkdir -p "$dir/stale"
  printf '%s\n' "$bin_version" >"$dir/bin.version"
  printf '%s\n' "$held_version" >"$dir/npm.held"
  : >"$dir/npm.calls"

  cat >"$dir/stale/opencode-target" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) cat "$FAKE_OC_DIR/bin.version" ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$dir/stale/opencode-target"

  printf '#!/usr/bin/env bash\nexit 1\n' >"$fake_home/.local/bin/fnm"
  if [ "${OC_VIA_MISE:-0}" -eq 1 ]; then
    # opencode is NOT on PATH: only a mise-managed node puts it there.
    mkdir -p "$dir/mise-bin"
    ln -s "$dir/stale/opencode-target" "$dir/mise-bin/opencode"
    cat >"$fake_home/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  which) exit 0 ;;
  exec)
    shift 3
    PATH="$FAKE_OC_DIR/mise-bin:$PATH" exec "$@"
    ;;
  *) exit 2 ;;
esac
EOF
  else
    ln -s "$dir/stale/opencode-target" "$fake_home/.local/bin/opencode"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$fake_home/.local/bin/mise"
  fi

  cat >"$fake_home/.local/bin/npm" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  view)
    [ "${FAKE_NPM_VIEW_FAIL:-0}" -eq 0 ] || exit 1
    printf '%s\n' "$FAKE_NPM_LATEST"
    ;;
  install)
    printf '%s\n' "$*" >>"$FAKE_OC_DIR/npm.calls"
    printf '%s\n' "$FAKE_NPM_LATEST" >"$FAKE_OC_DIR/npm.held"
    if [ "${FAKE_NPM_LINKED:-0}" -eq 1 ]; then
      printf '%s\n' "$FAKE_NPM_LATEST" >"$FAKE_OC_DIR/bin.version"
    fi
    printf 'changed 2 packages\n'
    ;;
  ls)
    if [ "${FAKE_NPM_LS_FAIL:-0}" -ne 0 ]; then
      printf '{}\n'
      exit 1
    fi
    printf '{\n  "name": "lib",\n  "dependencies": {\n    "opencode-ai": {\n      "version": "%s",\n      "overridden": false\n    }\n  }\n}\n' \
      "$(cat "$FAKE_OC_DIR/npm.held")"
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "$fake_home/.local/bin/mise" "$fake_home/.local/bin/fnm" "$fake_home/.local/bin/npm"
  printf '%s\n' "$fake_home"
}

# run_opencode NAME MODE NPM_LATEST LINKED [BIN_VERSION [HELD [LS_FAIL [VIEW_FAIL [UPDATER]]]]]
run_opencode() {
  local name=$1
  local mode=$2
  local latest=$3
  local linked=$4
  local bin_version=${5:-1.18.32}
  local held=${6:-1.18.32}
  local ls_fail=${7:-0}
  local view_fail=${8:-0}
  local updater=${9:-$SCRIPT}
  local fake_home check_arg=""
  fake_home=$(make_fake_opencode_home "$name" "$bin_version" "$held")
  if [ "$mode" = check ]; then check_arg=--check; fi

  env \
    HOME="$fake_home" \
    FAKE_OC_DIR="$TMP_ROOT/$name" \
    FAKE_NPM_LATEST="$latest" \
    FAKE_NPM_LINKED="$linked" \
    FAKE_NPM_LS_FAIL="$ls_fail" \
    FAKE_NPM_VIEW_FAIL="$view_fail" \
    FAKE_SLEEP_CALLS="$TMP_ROOT/$name/sleep.calls" \
    HARNESS_UPDATE_TIMEOUT_SECONDS=10 \
    "$updater" $check_arg --only opencode >"$TMP_ROOT/$name/output" 2>&1
}

harness_log() {
  printf '%s/%s/home/.local/state/harness-update/%s.log' "$TMP_ROOT" "$1" "$(date +%F)"
}

opencode_stale_binary_fails() {
  local name=oc-stale
  local status log
  if run_opencode "$name" update 1.19.3 0; then
    return 1
  else
    status=$?
  fi
  log=$(harness_log "$name")

  [ "$status" -eq 1 ] &&
    [ "$(cat "$TMP_ROOT/$name/npm.held")" = 1.19.3 ] &&
    [ "$(grep -c '^opencode FAIL ' "$log")" -eq 1 ] &&
    grep -Fq "opencode FAIL effective=1.18.32 expected=1.19.3 (npm installed) binary=$TMP_ROOT/$name/home/.local/bin/opencode -> $TMP_ROOT/$name/stale/opencode-target" "$log" &&
    grep -Fq 'opencode FAIL effective=1.18.32 expected=1.19.3' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'opencode OK' "$log" &&
    grep -Fq 'harness update finish exit=1' "$log"
}

check 'opencode: npm installs 1.19.3 but the PATH binary stays 1.18.32 -> FAIL naming both versions and the binary' \
  opencode_stale_binary_fails

opencode_linked_update_ok() {
  local name=oc-linked
  run_opencode "$name" update 1.19.3 1 || return 1
  grep -Fq 'opencode OK 1.18.32 -> 1.19.3' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'opencode FAIL' "$TMP_ROOT/$name/output"
}

check 'opencode: update the PATH binary actually follows stays OK' \
  opencode_linked_update_ok

opencode_current_stays_ok() {
  local name=oc-current
  run_opencode "$name" update 1.19.3 0 1.19.3 1.19.3 || return 1
  grep -Fq 'opencode OK 1.19.3 -> 1.19.3' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'opencode FAIL' "$TMP_ROOT/$name/output"
}

check 'opencode: a genuinely current tool (effective == installed) stays OK' \
  opencode_current_stays_ok

opencode_unknown_installed_keeps_old_behaviour() {
  local name=oc-unknown
  run_opencode "$name" update 1.19.3 0 1.18.32 1.18.32 1 || return 1
  grep -Fq 'opencode OK 1.18.32 -> 1.18.32' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'opencode FAIL' "$TMP_ROOT/$name/output"
}

check 'opencode: npm cannot say what it holds -> no new failure, old OK line' \
  opencode_unknown_installed_keeps_old_behaviour

opencode_newer_binary_is_not_a_lag() {
  local name=oc-newer
  run_opencode "$name" update 1.19.3 0 1.20.0 1.19.0 || return 1
  grep -Fq 'opencode OK 1.20.0 -> 1.20.0' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'opencode FAIL' "$TMP_ROOT/$name/output"
}

check 'opencode: a PATH binary newer than npm holds is not reported as lagging' \
  opencode_newer_binary_is_not_a_lag

opencode_check_flags_lag() {
  local name=oc-check-lag
  run_opencode "$name" check 1.19.3 0 1.18.32 1.19.3 || return 1
  grep -Fq 'opencode CHECK current=1.18.32 latest=1.19.3 BEHIND' "$TMP_ROOT/$name/output" &&
    grep -Fq "binary=$TMP_ROOT/$name/home/.local/bin/opencode -> $TMP_ROOT/$name/stale/opencode-target" "$TMP_ROOT/$name/output" &&
    grep -Fq 'npm-installed=1.19.3' "$TMP_ROOT/$name/output" &&
    [ ! -s "$TMP_ROOT/$name/npm.calls" ]
}

check 'opencode --check flags a PATH binary behind latest and npm, changes nothing' \
  opencode_check_flags_lag

opencode_check_current_is_quiet() {
  local name=oc-check-current
  run_opencode "$name" check 1.19.3 0 1.19.3 1.19.3 || return 1
  grep -Fq 'opencode CHECK current=1.19.3 latest=1.19.3' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'BEHIND' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'npm-installed' "$TMP_ROOT/$name/output"
}

check 'opencode --check on a current tool prints no lag flag' \
  opencode_check_current_is_quiet

opencode_check_unknown_latest_unchanged() {
  local name=oc-check-unknown
  local status
  if run_opencode "$name" check 1.19.3 0 1.18.32 1.18.32 0 1; then
    return 1
  else
    status=$?
  fi
  [ "$status" -eq 1 ] &&
    grep -Fq 'opencode FAIL current=1.18.32 latest lookup failed' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'BEHIND' "$TMP_ROOT/$name/output"
}

check 'opencode --check with an unreachable registry keeps its lookup-failed behaviour' \
  opencode_check_unknown_latest_unchanged

opencode_prerelease_binary_is_a_lag() {
  local name=oc-pre-lag
  local status log
  if run_opencode "$name" update 1.19.3 0 1.19.3-beta.1 1.19.3-beta.1; then
    return 1
  else
    status=$?
  fi
  log=$(harness_log "$name")
  [ "$status" -eq 1 ] &&
    grep -Fq 'opencode FAIL effective=1.19.3-beta.1 expected=1.19.3 (npm installed)' "$log" &&
    ! grep -Fq 'opencode OK' "$log"
}

check 'opencode: a pre-release PATH binary is behind the release npm installed -> FAIL' \
  opencode_prerelease_binary_is_a_lag

opencode_release_over_prerelease_is_not_a_lag() {
  local name=oc-pre-ahead
  run_opencode "$name" update 1.19.3-beta.1 0 1.19.3 1.19.2 || return 1
  grep -Fq 'opencode OK 1.19.3 -> 1.19.3' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'opencode FAIL' "$TMP_ROOT/$name/output"
}

check 'opencode: a release PATH binary ahead of the installed pre-release is not a lag' \
  opencode_release_over_prerelease_is_not_a_lag

opencode_check_prerelease_directions() {
  run_opencode oc-check-pre-behind check 1.19.3 0 1.19.3-beta.1 1.19.3-beta.1 || return 1
  run_opencode oc-check-pre-ahead check 1.19.3-beta.1 0 1.19.3 1.19.3 || return 1
  grep -Fq 'opencode CHECK current=1.19.3-beta.1 latest=1.19.3 BEHIND' "$TMP_ROOT/oc-check-pre-behind/output" &&
    grep -Fq 'opencode CHECK current=1.19.3 latest=1.19.3-beta.1' "$TMP_ROOT/oc-check-pre-ahead/output" &&
    ! grep -Fq 'BEHIND' "$TMP_ROOT/oc-check-pre-ahead/output"
}

check 'opencode --check ranks a pre-release below its release, never above' \
  opencode_check_prerelease_directions

opencode_manager_fallback_names_binary() {
  local name=oc-mise-lag
  local status log expected_binary
  if OC_VIA_MISE=1 run_opencode "$name" update 1.19.3 0; then
    return 1
  else
    status=$?
  fi
  log=$(harness_log "$name")
  expected_binary="$TMP_ROOT/$name/mise-bin/opencode -> $TMP_ROOT/$name/stale/opencode-target"
  [ "$status" -eq 1 ] &&
    [ ! -e "$TMP_ROOT/$name/home/.local/bin/opencode" ] &&
    grep -Fq "opencode FAIL effective=1.18.32 expected=1.19.3 (npm installed) binary=$expected_binary" "$log" &&
    ! grep -Fq 'not-on-PATH' "$log"
}

check 'opencode: lag found through the mise fallback names the binary mise resolves' \
  opencode_manager_fallback_names_binary

opencode_manager_fallback_check_names_binary() {
  local name=oc-mise-check
  OC_VIA_MISE=1 run_opencode "$name" check 1.19.3 0 1.18.32 1.19.3 || return 1
  grep -Fq "BEHIND binary=$TMP_ROOT/$name/mise-bin/opencode -> $TMP_ROOT/$name/stale/opencode-target" "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'not-on-PATH' "$TMP_ROOT/$name/output"
}

check 'opencode --check through the mise fallback names the binary mise resolves' \
  opencode_manager_fallback_check_names_binary

muse_check_flags_behind_channel() {
  local name=muse-behind
  run_muse "$name" "$MUSE_CHANNEL_BODY" || return 1
  grep -Fq 'muse CHECK current=1.2.1-R2847.1 latest=1.2.2-R2848.1 BEHIND binary=' "$TMP_ROOT/$name/output"
}

check 'muse --check flags a build behind the channel' \
  muse_check_flags_behind_channel

opencode_lag_gate_negative_control() {
  local name=oc-no-gate
  local variant="$TMP_ROOT/$name/harness-update.sh"
  mkdir -p "$TMP_ROOT/$name"

  [ "$(grep -c '^effective_lag() {$' "$SCRIPT" | tr -d ' ')" -eq 1 ] || return 1
  sed 's/^effective_lag() {$/effective_lag() { return 0;/' "$SCRIPT" >"$variant"
  chmod +x "$variant"
  grep -Fq 'effective_lag() { return 0;' "$variant" || return 1

  # With the gate removed the stale binary sails through as OK: exactly the bug.
  run_opencode "$name" update 1.19.3 0 1.18.32 1.18.32 0 0 "$variant" || return 1
  grep -Fq 'opencode OK 1.18.32 -> 1.18.32' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'opencode FAIL' "$TMP_ROOT/$name/output"
}

check 'negative control: updater without the lag gate reports the stale binary as OK' \
  opencode_lag_gate_negative_control

make_fake_ae_home() {
  local name=$1
  local fake_home dir
  fake_home=$(make_fake_home "$name")
  dir="$TMP_ROOT/$name"
  printf '2026.10.93\n' >"$dir/ae.version"
  cat >"$fake_home/.local/bin/ae" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version) printf 'ae %s\n' "$(cat "$FAKE_OC_DIR/ae.version")" ;;
  upgrade)
    if [ "${FAKE_AE_LINKED:-0}" -eq 1 ]; then
      printf '%s\n' "$AE_VERSION" >"$FAKE_OC_DIR/ae.version"
    fi
    ;;
  *) exit 2 ;;
esac
EOF
  chmod +x "$fake_home/.local/bin/ae"
  printf '%s\n' "$fake_home"
}

# run_ae NAME LINKED [--check]
run_ae() {
  local name=$1
  local linked=$2
  local fake_home check_arg=""
  fake_home=$(make_fake_ae_home "$name")
  if [ "${3:-}" = --check ]; then check_arg=--check; fi
  env \
    HOME="$fake_home" \
    FAKE_OC_DIR="$TMP_ROOT/$name" \
    FAKE_AE_LINKED="$linked" \
    FAKE_SLEEP_CALLS="$TMP_ROOT/$name/sleep.calls" \
    AE_VERSION=2026.10.94 \
    HARNESS_UPDATE_TIMEOUT_SECONDS=10 \
    "$SCRIPT" $check_arg --include-ae --only ae >"$TMP_ROOT/$name/output" 2>&1
}

ae_pinned_version_not_reached_fails() {
  local name=ae-stale
  local status
  if run_ae "$name" 0; then
    return 1
  else
    status=$?
  fi
  [ "$status" -eq 1 ] &&
    grep -Fq "ae FAIL effective=2026.10.93 expected=2026.10.94 (pinned AE_VERSION) binary=$TMP_ROOT/$name/home/.local/bin/ae" "$(harness_log "$name")" &&
    ! grep -Fq 'ae OK' "$(harness_log "$name")"
}

check 'ae: pinned upgrade that leaves the PATH binary on the old version -> FAIL' \
  ae_pinned_version_not_reached_fails

ae_pinned_version_reached_ok() {
  local name=ae-ok
  run_ae "$name" 1 || return 1
  grep -Fq 'ae OK 2026.10.93 -> 2026.10.94' "$TMP_ROOT/$name/output" &&
    ! grep -Fq 'ae FAIL' "$TMP_ROOT/$name/output"
}

check 'ae: pinned upgrade the PATH binary follows stays OK' \
  ae_pinned_version_reached_ok

ae_check_flags_behind_pin() {
  local name=ae-check
  run_ae "$name" 0 --check || return 1
  grep -Fq 'ae CHECK current=2026.10.93 target=2026.10.94 BEHIND binary=' "$TMP_ROOT/$name/output"
}

check 'ae --check flags a PATH binary behind the pin' \
  ae_check_flags_behind_pin

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
