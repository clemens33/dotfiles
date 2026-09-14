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

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
