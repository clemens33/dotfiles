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

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
