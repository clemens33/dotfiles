#!/usr/bin/env bash

# Update installed AI coding harnesses without letting one failure skip the rest.
# Step functions are exported and invoked in supervised child shells.
# shellcheck disable=SC2329
set -uo pipefail

export PATH="$HOME/.local/bin:$HOME/.grok/bin:$HOME/.local/share/mise/shims:$HOME/.local/share/fnm:$HOME/.fnm:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export CI=1
export NO_COLOR=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ONLY=0
INCLUDE_AE=0
ONLY_TOOL=""
LOG_DIR="$HOME/.local/state/harness-update"
LOG_FILE="$LOG_DIR/$(date +%F).log"
STEP_TIMEOUT=${HARNESS_UPDATE_TIMEOUT_SECONDS:-300}

usage() {
  cat <<'EOF'
Usage: scripts/harness-update.sh [--check] [--only TOOL] [--include-ae]

Tools: claude, codex, agy, grok, opencode, muse, ae, contract

  --check       Report installed and latest versions without changing anything
  --only TOOL   Process one tool only
  --include-ae  Include ae; updates require an explicit AE_VERSION pin

contract is not a CLI: it reports harness instruction files that no longer match
the rendered contract. It never renders — run ./install for that.

Each tool has a 300-second deadline (HARNESS_UPDATE_TIMEOUT_SECONDS overrides it).
EOF
}

valid_tool() {
  case "$1" in
    claude|codex|agy|grok|opencode|muse|ae|contract) return 0 ;;
    *) return 1 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      ;;
    --include-ae)
      INCLUDE_AE=1
      ;;
    --only)
      if [ "$#" -lt 2 ] || ! valid_tool "$2"; then
        printf 'error: --only requires one of: claude, codex, agy, grok, opencode, muse, ae, contract\n' >&2
        usage >&2
        exit 2
      fi
      ONLY_TOOL="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$STEP_TIMEOUT" in
  ''|*[!0-9]*|0*)
    printf 'error: HARNESS_UPDATE_TIMEOUT_SECONDS must be a positive integer\n' >&2
    exit 2
    ;;
esac

if ! mkdir -p "$LOG_DIR"; then
  printf 'error: cannot create log directory: %s\n' "$LOG_DIR" >&2
  exit 1
fi

if ! touch "$LOG_FILE"; then
  printf 'error: cannot write log: %s\n' "$LOG_FILE" >&2
  exit 1
fi

# Date names sort oldest-first. Bash arrays keep this portable to macOS Bash 3.2.
shopt -s nullglob
log_files=("$LOG_DIR"/????-??-??.log)
if [ "${#log_files[@]}" -gt 14 ]; then
  remove_count=$((${#log_files[@]} - 14))
  index=0
  while [ "$index" -lt "$remove_count" ]; do
    rm "${log_files[$index]}"
    index=$((index + 1))
  done
fi
shopt -u nullglob

printf '\n[%s] harness update start check=%s only=%s include_ae=%s\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$CHECK_ONLY" "${ONLY_TOOL:-all}" "$INCLUDE_AE" >>"$LOG_FILE"

summary() {
  printf '%s\n' "$1"
  printf '%s\n' "$1" >>"$LOG_FILE"
}

selected() {
  [ -z "$ONLY_TOOL" ] || [ "$ONLY_TOOL" = "$1" ]
}

# Bound the entire step, including version probes. Kill descendants too: an npm
# or installer child must not keep updating after its parent reports a timeout.
with_timeout() {
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout --kill-after=5 "$STEP_TIMEOUT" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout --kill-after=5 "$STEP_TIMEOUT" "$@"
  else
    # macOS ships Perl, but not GNU timeout. A new session owns the child group.
    perl -MPOSIX=setsid -e '
      my $seconds = shift @ARGV;
      my $pid = fork();
      defined $pid or die "fork: $!\n";
      if (!$pid) {
        setsid() >= 0 or die "setsid: $!\n";
        exec @ARGV or die "exec: $!\n";
      }
      my $stop = sub {
        my ($code) = @_;
        kill "TERM", -$pid;
        select undef, undef, undef, 0.5;
        kill "KILL", -$pid;
        waitpid $pid, 0;
        exit $code;
      };
      $SIG{ALRM} = sub { $stop->(124) };
      $SIG{INT} = sub { $stop->(130) };
      $SIG{TERM} = sub { $stop->(143) };
      alarm $seconds;
      waitpid $pid, 0;
      my $status = $?;
      alarm 0;
      exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);
    ' "$STEP_TIMEOUT" "$@"
  fi
}

run_step() {
  local result
  # Expand the positional argument in the child, not the supervising shell.
  # shellcheck disable=SC2016
  with_timeout bash -c 'set -uo pipefail; "process_$1"' bash "$1"
  result=$?
  if [ "$result" -eq 124 ] || [ "$result" -eq 137 ]; then
    summary "$1 FAIL timed out after ${STEP_TIMEOUT}s"
  fi
  return "$result"
}

log_run() {
  local result
  {
    printf '[%s] run:' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf ' %q' "$@"
    printf '\n'
    "$@" </dev/null
    result=$?
    printf '[%s] exit=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$result"
  } >>"$LOG_FILE" 2>&1
  return "$result"
}

npm_mode() {
  if command -v mise >/dev/null 2>&1 && mise which node >/dev/null 2>&1; then
    printf 'mise\n'
  elif command -v fnm >/dev/null 2>&1 && fnm exec --using=default -- npm --version >/dev/null 2>&1; then
    printf 'fnm\n'
  elif [ -s "$HOME/.nvm/nvm.sh" ] && nvm_exec npm --version >/dev/null 2>&1; then
    printf 'nvm\n'
  elif command -v npm >/dev/null 2>&1; then
    printf 'npm\n'
  else
    return 1
  fi
}

nvm_exec() (
  set +u
  # shellcheck source=/dev/null
  . "$HOME/.nvm/nvm.sh"
  nvm use default >/dev/null
  "$@"
)

npm_latest() {
  local package="$1"
  local mode
  mode=$(npm_mode) || return 1
  case "$mode" in
    mise) mise exec node@lts -- npm view "$package" version --no-fund --no-audit 2>>"$LOG_FILE" ;;
    fnm) fnm exec --using=default -- npm view "$package" version --no-fund --no-audit 2>>"$LOG_FILE" ;;
    nvm) nvm_exec npm view "$package" version --no-fund --no-audit 2>>"$LOG_FILE" ;;
    npm) npm view "$package" version --no-fund --no-audit 2>>"$LOG_FILE" ;;
  esac
}

npm_install_latest() {
  local package="$1"
  local mode
  mode=$(npm_mode) || return 1
  # Keep npm's global strict-allow-scripts policy; approve only this package.
  case "$mode" in
    mise) log_run mise exec node@lts -- npm install --global --no-fund --no-audit --allow-scripts="$package" "$package@latest" ;;
    fnm) log_run fnm exec --using=default -- npm install --global --no-fund --no-audit --allow-scripts="$package" "$package@latest" ;;
    nvm) log_run nvm_exec npm install --global --no-fund --no-audit --allow-scripts="$package" "$package@latest" ;;
    npm) log_run npm install --global --no-fund --no-audit --allow-scripts="$package" "$package@latest" ;;
  esac
}

opencode_available() {
  local mode
  if command -v opencode >/dev/null 2>&1; then
    return 0
  fi
  mode=$(npm_mode) || return 1
  case "$mode" in
    mise) mise exec node@lts -- opencode --version >/dev/null 2>&1 ;;
    fnm) fnm exec --using=default -- opencode --version >/dev/null 2>&1 ;;
    nvm) nvm_exec opencode --version >/dev/null 2>&1 ;;
    npm) return 1 ;;
  esac
}

run_opencode() {
  local mode
  if command -v opencode >/dev/null 2>&1; then
    opencode "$@"
    return
  fi
  mode=$(npm_mode) || return 1
  case "$mode" in
    mise) mise exec node@lts -- opencode "$@" ;;
    fnm) fnm exec --using=default -- opencode "$@" ;;
    nvm) nvm_exec opencode "$@" ;;
    npm) return 1 ;;
  esac
}

installed_version() {
  case "$1" in
    claude) claude --version 2>>"$LOG_FILE" | awk 'NR == 1 { print $1 }' ;;
    codex) codex --version 2>>"$LOG_FILE" | awk 'NR == 1 { print $NF }' ;;
    agy) agy --version 2>>"$LOG_FILE" | awk 'NR == 1 { print $1 }' ;;
    grok) grok --version 2>>"$LOG_FILE" | awk 'NR == 1 { print $2 }' ;;
    opencode) run_opencode --version 2>>"$LOG_FILE" | awk 'NR == 1 { print $1 }' ;;
    muse) muse --version 2>>"$LOG_FILE" | awk 'NR == 1 { gsub(/[()]/, "", $NF); print $NF }' ;;
    ae) ae --version 2>>"$LOG_FILE" | awk 'NR == 1 { print $NF }' ;;
    *) return 1 ;;
  esac
}

agy_latest() {
  local changelog
  changelog=$(agy changelog 2>>"$LOG_FILE") || return 1
  printf '%s\n' "$changelog" | awk '/^[0-9]+\.[0-9]+\.[0-9]+:/ { sub(/:$/, "", $1); print $1; exit }'
}

grok_latest() {
  local check
  check=$(grok update --check --json 2>>"$LOG_FILE") || return 1
  printf '%s\n' "$check" | sed -n 's/.*"latestVersion":"\([^"]*\)".*/\1/p'
}

check_with_npm() {
  local tool="$1"
  local package="$2"
  local before latest
  before=$(installed_version "$tool") || before=""
  if [ -z "$before" ]; then
    summary "$tool FAIL unable to read installed version"
    return 1
  fi
  latest=$(npm_latest "$package") || latest=""
  if [ -z "$latest" ]; then
    summary "$tool FAIL current=$before latest lookup failed"
    return 1
  fi
  summary "$tool CHECK current=$before latest=$latest"
}

update_native() {
  local tool="$1"
  local before after
  shift
  before=$(installed_version "$tool") || before=""
  if [ -z "$before" ]; then
    summary "$tool FAIL unable to read installed version"
    return 1
  fi
  if ! log_run "$@"; then
    summary "$tool FAIL current=$before update command failed"
    return 1
  fi
  hash -r
  after=$(installed_version "$tool") || after=""
  if [ -z "$after" ]; then
    summary "$tool FAIL before=$before unable to read updated version"
    return 1
  fi
  summary "$tool OK $before -> $after"
}

process_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    summary 'claude SKIP not installed'
    return 0
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    check_with_npm claude @anthropic-ai/claude-code
  else
    update_native claude claude update
  fi
}

process_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    summary 'codex SKIP not installed'
    return 0
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    check_with_npm codex @openai/codex
  else
    update_native codex codex update
  fi
}

process_agy() {
  if ! command -v agy >/dev/null 2>&1; then
    summary 'agy SKIP not installed'
    return 0
  fi
  local before latest
  before=$(installed_version agy) || before=""
  if [ -z "$before" ]; then
    summary 'agy FAIL unable to read installed version'
    return 1
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    latest=$(agy_latest) || latest=""
    if [ -z "$latest" ]; then
      summary "agy FAIL current=$before latest lookup failed"
      return 1
    fi
    summary "agy CHECK current=$before latest=$latest"
  else
    update_native agy agy update
  fi
}

process_grok() {
  if ! command -v grok >/dev/null 2>&1; then
    summary 'grok SKIP not installed'
    return 0
  fi
  local before latest
  before=$(installed_version grok) || before=""
  if [ -z "$before" ]; then
    summary 'grok FAIL unable to read installed version'
    return 1
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    latest=$(grok_latest) || latest=""
    if [ -z "$latest" ]; then
      summary "grok FAIL current=$before latest lookup failed"
      return 1
    fi
    summary "grok CHECK current=$before latest=$latest"
  else
    update_native grok grok update
  fi
}

process_opencode() {
  if ! opencode_available; then
    summary 'opencode SKIP not installed'
    return 0
  fi
  local before latest after
  before=$(installed_version opencode) || before=""
  if [ -z "$before" ]; then
    summary 'opencode FAIL unable to read installed version'
    return 1
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    latest=$(npm_latest opencode-ai) || latest=""
    if [ -z "$latest" ]; then
      summary "opencode FAIL current=$before latest lookup failed"
      return 1
    fi
    summary "opencode CHECK current=$before latest=$latest"
    return 0
  fi
  if ! npm_install_latest opencode-ai; then
    summary "opencode FAIL current=$before npm update failed"
    return 1
  fi
  hash -r
  after=$(installed_version opencode) || after=""
  if [ -z "$after" ]; then
    summary "opencode FAIL before=$before unable to read updated version"
    return 1
  fi
  summary "opencode OK $before -> $after"
}

process_ae() {
  if [ "$INCLUDE_AE" -ne 1 ]; then
    summary 'ae SKIP excluded; upgrades stay explicitly pinned'
    return 0
  fi
  if ! command -v ae >/dev/null 2>&1; then
    summary 'ae SKIP not installed'
    return 0
  fi
  local before target after
  before=$(installed_version ae) || before=""
  if [ -z "$before" ]; then
    summary 'ae FAIL unable to read installed version'
    return 1
  fi
  target=${AE_VERSION:-}
  if [ "$CHECK_ONLY" -eq 1 ]; then
    summary "ae CHECK current=$before target=${target:-pin-required}"
    return 0
  fi
  if [ -z "$target" ]; then
    summary "ae FAIL current=$before --include-ae requires AE_VERSION=<calver>"
    return 1
  fi
  if ! log_run env AE_VERSION="$target" ae upgrade; then
    summary "ae FAIL current=$before pinned update failed"
    return 1
  fi
  hash -r
  after=$(installed_version ae) || after=""
  if [ -z "$after" ]; then
    summary "ae FAIL before=$before unable to read updated version"
    return 1
  fi
  summary "ae OK $before -> $after"
}

install_muse() {
  curl -fsSL https://dev.meta.ai/install.sh | bash
}

process_muse() {
  if ! command -v muse >/dev/null 2>&1; then
    summary 'muse SKIP not installed'
    return 0
  fi
  local before after
  before=$(installed_version muse) || before=""
  if [ -z "$before" ]; then
    summary 'muse FAIL unable to read installed version'
    return 1
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    summary "muse CHECK current=$before latest=unknown (installer has no version lookup)"
    return 0
  fi
  if ! log_run install_muse; then
    summary "muse FAIL current=$before installer failed"
    return 1
  fi
  hash -r
  after=$(installed_version muse) || after=""
  if [ -z "$after" ]; then
    summary "muse FAIL before=$before unable to read updated version"
    return 1
  fi
  if [ "$before" = "$after" ]; then
    summary "muse OK $before -> $after (muse: up to date)"
  else
    summary "muse OK $before -> $after"
  fi
}

# Drift only — the contract is rendered by ./install, never from here. An
# unattended job must not rewrite the rules every harness reads next session.
process_contract() {
  local renderer="$REPO_ROOT/scripts/render-contract.sh"
  if [ ! -x "$renderer" ]; then
    summary 'contract SKIP renderer not found'
    return 0
  fi
  local output result stale count
  output=$("$renderer" --check 2>&1)
  result=$?
  printf '[%s] contract --check exit=%s\n%s\n' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$result" "$output" >>"$LOG_FILE"
  case "$result" in
    0)
      summary 'contract OK all targets match the rendered contract'
      ;;
    1)
      # Home-relative and counted: this line lands in a daily log, unread
      # until something is wrong.
      stale=$(printf '%s\n' "$output" | awk -v home="$HOME" '
        $1 == "stale" {
          path = $2
          if (index(path, home) == 1) { path = "~" substr(path, length(home) + 1) }
          printf "%s ", path
        }')
      count=$(printf '%s\n' "$output" | grep -c '^stale ')
      summary "contract STALE $count target(s), run ./install: ${stale% }"
      ;;
    *)
      summary "contract FAIL --check exited $result"
      return 1
      ;;
  esac
}

# Export existing step functions so timeout can supervise a separate Bash process.
export CHECK_ONLY INCLUDE_AE LOG_FILE REPO_ROOT
export -f summary log_run npm_mode nvm_exec npm_latest npm_install_latest \
  opencode_available run_opencode installed_version agy_latest grok_latest \
  check_with_npm update_native install_muse process_claude process_codex \
  process_agy process_grok process_opencode process_muse process_ae \
  process_contract

failures=0
for tool in claude codex agy grok opencode muse ae contract; do
  if selected "$tool" && ! run_step "$tool"; then failures=1; fi
done

printf '[%s] harness update finish exit=%s\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$failures" >>"$LOG_FILE"

if [ "$failures" -ne 0 ] && [ "$(uname -s)" = Darwin ] && command -v osascript >/dev/null 2>&1; then
  osascript -e 'display notification "One or more CLI updates failed. Check ~/.local/state/harness-update/." with title "Harness update failed"' \
    >>"$LOG_FILE" 2>&1 || true
fi

exit "$failures"
