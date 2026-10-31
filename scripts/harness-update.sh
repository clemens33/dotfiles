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
RETRY_ATTEMPTS=3
# process_<tool> status for a --check verdict of "outdated": it fails the run, but
# it is a definitive answer rather than a transient error, so it is never retried.
CHECK_OUTDATED=3

usage() {
  cat <<'EOF'
Usage: scripts/harness-update.sh [--check] [--only TOOL] [--include-ae]

Tools: claude, codex, agy, grok, opencode, muse, copilot, ae, contract

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
    claude|codex|agy|grok|opencode|muse|copilot|ae|contract) return 0 ;;
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
        printf 'error: --only requires one of: claude, codex, agy, grok, opencode, muse, copilot, ae, contract\n' >&2
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
  local message=$1
  local failed_prefix
  if [ -n "${RETRY_TOOL:-}" ] &&
    [ "${RETRY_ATTEMPT:-0}" -lt "${RETRY_ATTEMPTS:-0}" ]; then
    failed_prefix="$RETRY_TOOL FAIL"
    case "$message" in
      "$failed_prefix"*)
        message="$RETRY_TOOL ATTEMPT $RETRY_ATTEMPT/$RETRY_ATTEMPTS failed${message#"$failed_prefix"}"
        ;;
    esac
  fi
  printf '%s\n' "$message"
  printf '%s\n' "$message" >>"$LOG_FILE"
}

# True only when copilot on PATH resolves to a VS Code/Insiders copilot-shim
# file. A bare name, a broken link, or a symlink loop is not a shim, so callers
# keep the old command -v behaviour. Never execute the candidate.
# readlink(1) without -f; the final pwd -P canonicalizes relative link targets.
copilot_is_shim() {
  local cmd target link seen dir base
  cmd=$(command -v copilot 2>/dev/null) || return 1
  case "$cmd" in
    */*) target=$cmd ;;
    *) return 1 ;;
  esac
  seen=0
  while [ -L "$target" ]; do
    seen=$((seen + 1))
    [ "$seen" -le 32 ] || return 1
    link=$(readlink "$target") || return 1
    case "$link" in
      /*) target=$link ;;
      *) target=$(dirname "$target")/$link ;;
    esac
  done
  dir=$(dirname "$target")
  base=$(basename "$target")
  dir=$(CDPATH= cd -- "$dir" 2>/dev/null && pwd -P) || return 1
  case "$dir/$base" in
    *copilot-shim*) return 0 ;;
  esac
  return 1
}

copilot_installed() {
  command -v copilot >/dev/null 2>&1 && ! copilot_is_shim
}

# Observe presence before another tool update changes the Node/mise runtime.
# The marker survives that transition; check mode never creates it.
# A copilot-shim stub does not count as a previously installed binary.
COPILOT_EXPECTED=0
if [ -f "$LOG_DIR/copilot-installed" ] || copilot_installed; then
  COPILOT_EXPECTED=1
fi

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

run_with_retry() {
  local tool=$1
  local attempt=1
  local result backoff
  while [ "$attempt" -le "$RETRY_ATTEMPTS" ]; do
    RETRY_TOOL=$tool
    RETRY_ATTEMPT=$attempt
    export RETRY_TOOL RETRY_ATTEMPT
    if [ "$attempt" -gt 1 ]; then
      summary "$tool ATTEMPT $attempt/$RETRY_ATTEMPTS"
    fi
    "process_$tool"
    result=$?
    if [ "$result" -eq 0 ]; then
      return 0
    fi
    if [ "$result" -eq "$CHECK_OUTDATED" ]; then
      return 1
    fi
    if [ "$attempt" -eq "$RETRY_ATTEMPTS" ]; then
      return "$result"
    fi
    case "$attempt" in
      1) backoff=5 ;;
      *) backoff=20 ;;
    esac
    summary "$tool RETRY after attempt $attempt/$RETRY_ATTEMPTS; backoff=${backoff}s"
    sleep "$backoff"
    attempt=$((attempt + 1))
  done
}

run_step() {
  local result
  # A lost managed install is a local setup failure, not a transient network
  # error. Fail immediately rather than spending retry backoffs on it.
  if [ "$1" = copilot ] && [ "$COPILOT_EXPECTED" -eq 1 ] && ! copilot_installed; then
    process_copilot
    return $?
  fi
  # Expand the positional argument in the child, not the supervising shell.
  # shellcheck disable=SC2016
  case "$1" in
    contract)
      with_timeout bash -c 'set -uo pipefail; "process_$1"' bash "$1"
      ;;
    *)
      with_timeout bash -c 'set -uo pipefail; run_with_retry "$1"' bash "$1"
      ;;
  esac
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

# Version npm itself holds for a global package, read from its own tree (no
# registry call). The PATH binary can be a different copy that npm never touched.
npm_global_version() {
  local package="$1"
  local mode listing
  mode=$(npm_mode) || return 1
  case "$mode" in
    mise) listing=$(mise exec node@lts -- npm ls --global --depth=0 --json "$package" 2>>"$LOG_FILE") ;;
    fnm) listing=$(fnm exec --using=default -- npm ls --global --depth=0 --json "$package" 2>>"$LOG_FILE") ;;
    nvm) listing=$(nvm_exec npm ls --global --depth=0 --json "$package" 2>>"$LOG_FILE") ;;
    npm) listing=$(npm ls --global --depth=0 --json "$package" 2>>"$LOG_FILE") ;;
  esac
  # `|` delimiter: scoped package names (@opencode/cli) contain `/`.
  printf '%s\n' "$listing" | tr -d '\n' |
    sed -n "s|.*\"$package\"[[:space:]]*:[[:space:]]*{[^}]*\"version\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*|\1|p"
}

# Succeeds when $1 sorts before $2 under sort -V. If sort lacks -V, any
# difference counts as earlier: loud beats silent.
version_sorts_first() {
  local first
  first=$(printf '%s\n%s\n' "$1" "$2" | sort -V 2>/dev/null | sed -n 1p) || first=""
  [ -z "$first" ] || [ "$first" = "$1" ]
}

# Succeeds when version $1 is strictly older than $2. Equality and an unknown
# version on either side are never "older", so a failed lookup cannot fail a
# step. sort -V alone ranks 1.2.3-beta.1 above 1.2.3, so split off the
# pre-release first: on equal cores the release outranks its pre-releases.
version_older() {
  local core_a core_b pre_a pre_b
  [ -n "$1" ] && [ -n "$2" ] && [ "$1" != "$2" ] || return 1
  core_a=${1%%-*}
  core_b=${2%%-*}
  pre_a=${1#"$core_a"}
  pre_b=${2#"$core_b"}
  if [ "$core_a" != "$core_b" ]; then
    version_sorts_first "$core_a" "$core_b"
  elif [ -z "$pre_a" ]; then
    return 1
  elif [ -z "$pre_b" ]; then
    return 0
  else
    version_sorts_first "$pre_a" "$pre_b"
  fi
}

# `command -v` as run_opencode would see it when the tool is only reachable
# through the node manager, so diagnostics name the binary that actually runs.
manager_command_v() {
  local mode
  mode=$(npm_mode) || return 1
  # Expand the positional argument in the child, not here.
  # shellcheck disable=SC2016
  case "$mode" in
    mise) mise exec node@lts -- bash -c 'command -v "$1"' bash "$1" ;;
    fnm) fnm exec --using=default -- bash -c 'command -v "$1"' bash "$1" ;;
    nvm) nvm_exec bash -c 'command -v "$1"' bash "$1" ;;
    npm) return 1 ;;
  esac
}

# Where `tool` actually runs from. A symlink is shown with its target: a stale
# link is how the PATH binary outlives the install that should have replaced it.
resolved_binary() {
  local path target
  # Same order run_opencode executes: PATH, the opencode curl install, managers.
  path=$(command -v "$1" 2>/dev/null) || path=""
  if [ -z "$path" ] && [ "$1" = opencode ] && [ -x "$OPENCODE_NATIVE_BIN" ]; then
    path=$OPENCODE_NATIVE_BIN
  fi
  if [ -z "$path" ]; then
    path=$(manager_command_v "$1" 2>/dev/null) || path=""
  fi
  if [ -z "$path" ]; then
    printf 'not-on-PATH'
    return 0
  fi
  if [ -L "$path" ] && target=$(readlink "$path"); then
    printf '%s -> %s' "$path" "$target"
  else
    printf '%s' "$path"
  fi
}

# Check-mode suffix: current is behind latest, with the binary that answered.
behind_note() {
  version_older "$2" "$3" || return 0
  printf ' BEHIND binary=%s' "$(resolved_binary "$1")"
}

# Update-mode gate: fail when the PATH binary is older than the version the
# update step installed. An unknown expected version never fails.
effective_lag() {
  local tool=$1 effective=$2 expected=$3 source=$4
  version_older "$effective" "$expected" || return 0
  summary "$tool FAIL effective=$effective expected=$expected ($source) binary=$(resolved_binary "$tool"); the binary on PATH lags the update, repoint or remove it"
  return 1
}

# PATH first, so a copy shadowing the curl install is the one measured; then
# the curl install itself, which the vendor installer does not link onto this
# script's fixed PATH; then the node managers.
opencode_available() {
  local mode
  if command -v opencode >/dev/null 2>&1 || [ -x "$OPENCODE_NATIVE_BIN" ]; then
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
  if [ -x "$OPENCODE_NATIVE_BIN" ]; then
    "$OPENCODE_NATIVE_BIN" "$@"
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
    # OpenCode 2 prints "opencode v2.1.4"; OpenCode 1 printed a bare "1.19.4".
    opencode) run_opencode --version 2>>"$LOG_FILE" | awk 'NR == 1 { v = $NF; sub(/^v/, "", v); print v }' ;;
    muse) muse --version 2>>"$LOG_FILE" | awk 'NR == 1 { gsub(/[()]/, "", $NF); print $NF }' ;;
    copilot) copilot --version 2>>"$LOG_FILE" | awk 'NR == 1 { sub(/\.$/, "", $NF); print $NF }' ;;
    ae) ae --version 2>>"$LOG_FILE" | awk 'NR == 1 { print $NF }' ;;
    *) return 1 ;;
  esac
}

agy_latest() {
  local changelog
  changelog=$(agy changelog 2>>"$LOG_FILE") || return 1
  # No early `exit`: the changelog is far larger than the pipe buffer, and awk
  # quitting first would SIGPIPE printf, which pipefail reports as a failed lookup.
  printf '%s\n' "$changelog" | awk '!found && /^[0-9]+\.[0-9]+\.[0-9]+:/ { sub(/:$/, "", $1); print $1; found = 1 }'
}

# OpenCode 2 ships two ways: the vendor curl installer (binary in
# ~/.opencode/bin, updated by `opencode upgrade`) or npm (@opencode/cli). The
# curl copy wins when present; npm is the fallback.
OPENCODE_NPM_PACKAGE=@opencode/cli
OPENCODE_NATIVE_BIN="$HOME/.opencode/bin/opencode"

native_opencode_version() {
  "$OPENCODE_NATIVE_BIN" --version 2>>"$LOG_FILE" | awk 'NR == 1 { v = $NF; sub(/^v/, "", v); print v }'
}

# Same release endpoint the vendor installer resolves "latest" from.
opencode_latest() {
  curl --silent --show-error --location --proto '=https' --connect-timeout 5 --max-time 15 \
    https://opencode.ai/update/api/latest/cli/npm 2>>"$LOG_FILE" |
    sed -n 's/.*"version":"\([^"]*\)".*/\1/p'
}

grok_latest() {
  local check
  check=$(grok update --check --json 2>>"$LOG_FILE") || return 1
  printf '%s\n' "$check" | sed -n 's/.*"latestVersion":"\([^"]*\)".*/\1/p'
}

# Latest version published on the Muse release channel. Mirrors the vendor
# launcher's resolution: same channel URL, same MUSE_CHANNEL_URL override, same
# version pattern. Prints "<version>\t<reason>" so the caller can report why a
# lookup failed without a second call. Never authenticates: the channel
# manifest is public, so no credential file is read and no token is sent.
muse_latest() {
  local channel_url result status document version
  channel_url="${MUSE_CHANNEL_URL:-https://api.meta.ai/muse-code/channels/muse-stable}"
  if ! command -v curl >/dev/null 2>&1; then
    printf '\tno curl available\n'
    return 0
  fi
  result=$(curl \
    --silent \
    --show-error \
    --location \
    --max-redirs 3 \
    --proto '=https' \
    --proto-redir '=https' \
    --tlsv1.2 \
    --connect-timeout 5 \
    --max-time 15 \
    --header 'Accept: application/json' \
    --write-out '\n%{http_code}' \
    "$channel_url" 2>>"$LOG_FILE") || result=""
  status=${result##*$'\n'}
  if [ "$status" = "$result" ]; then
    document=$result
    status=""
  else
    document=${result%$'\n'*}
  fi
  case "$status" in
    401|403)
      printf '\tchannel requires auth\n'
      return 0
      ;;
    2??) ;;
    '')
      printf '\tchannel unreachable\n'
      return 0
      ;;
    *)
      printf '\tchannel returned HTTP %s\n' "$status"
      return 0
      ;;
  esac
  version=$(printf '%s\n' "$document" |
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-R[0-9]+(\.[0-9]+)?$ ]]; then
    printf '\tinvalid channel manifest\n'
    return 0
  fi
  printf '%s\tok\n' "$version"
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
  summary "$tool CHECK current=$before latest=$latest$(behind_note "$tool" "$before" "$latest")"
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

# Use the stable release channel and the ACTIVE CLI, not the npm loader's
# manifest: cached native packages can be newer than that manifest.
copilot_latest() {
  curl --fail --silent --show-error --location --max-redirs 3 \
    --proto '=https' --proto-redir '=https' --connect-timeout 5 --max-time 15 \
    https://api.github.com/repos/github/copilot-cli/releases/latest 2>>"$LOG_FILE" |
    jq -er '.tag_name | select(type == "string") | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) | ltrimstr("v")'
}

process_copilot() {
  hash -r
  if ! copilot_installed; then
    if [ "$COPILOT_EXPECTED" -eq 1 ]; then
      summary 'copilot FAIL previously installed binary missing; restore Copilot in the active Node/mise runtime'
      return 1
    fi
    summary 'copilot SKIP not installed'
    return 0
  fi
  local before latest after marker
  before=$(installed_version copilot) || before=""
  if ! [[ "$before" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    summary 'copilot FAIL unable to read active version'
    return 1
  fi
  latest=$(copilot_latest) || latest=""
  if [ -z "$latest" ]; then
    summary "copilot FAIL current=$before stable release lookup failed"
    return 1
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    summary "copilot CHECK current=$before latest=$latest$(behind_note copilot "$before" "$latest")"
    if version_older "$before" "$latest"; then
      return "$CHECK_OUTDATED"
    fi
    return 0
  fi
  if ! log_run copilot update stable; then
    summary "copilot FAIL current=$before update command failed"
    return 1
  fi
  hash -r
  after=$(installed_version copilot) || after=""
  if ! [[ "$after" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    summary 'copilot FAIL unable to read updated active version'
    return 1
  fi
  effective_lag copilot "$after" "$latest" 'stable GitHub release' || return 1
  marker=$(mktemp "$LOG_DIR/.copilot-installed.XXXXXX") || return 1
  if ! printf '%s\n' "$after" >"$marker" || ! chmod 600 "$marker" || ! mv "$marker" "$LOG_DIR/copilot-installed"; then
    rm -f "$marker"
    summary 'copilot FAIL cannot record installed state'
    return 1
  fi
  summary "copilot OK $before -> $after latest=$latest"
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
    summary "agy CHECK current=$before latest=$latest$(behind_note agy "$before" "$latest")"
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
    summary "grok CHECK current=$before latest=$latest$(behind_note grok "$before" "$latest")"
  else
    update_native grok grok update
  fi
}

process_opencode() {
  if ! opencode_available; then
    summary 'opencode SKIP not installed'
    return 0
  fi
  local before latest after installed note native=0
  before=$(installed_version opencode) || before=""
  if [ -z "$before" ]; then
    summary 'opencode FAIL unable to read installed version'
    return 1
  fi
  # OpenCode 1 cannot upgrade itself to 2 here (npm package renamed, v1
  # installer refuses 2.x) and opencode/opencode.jsonc is native V2 config.
  case "$before" in
    1.*)
      summary "opencode FAIL current=$before is OpenCode 1 binary=$(resolved_binary opencode); remove it (npm uninstall -g opencode-ai) and install V2: curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path"
      return 1
      ;;
  esac
  if [ -x "$OPENCODE_NATIVE_BIN" ]; then
    native=1
    # A leftover V1 in ~/.opencode/bin would run V1's own upgrader.
    installed=$(native_opencode_version) || installed=""
    case "$installed" in
      1.*)
        summary "opencode FAIL ~/.opencode/bin holds OpenCode 1 ($installed); install V2 over it: curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path"
        return 1
        ;;
    esac
  fi
  if [ "$CHECK_ONLY" -eq 1 ]; then
    if [ "$native" -eq 1 ]; then
      latest=$(opencode_latest) || latest=""
    else
      latest=$(npm_latest "$OPENCODE_NPM_PACKAGE") || latest=""
    fi
    if [ -z "$latest" ]; then
      summary "opencode FAIL current=$before latest lookup failed"
      return 1
    fi
    note=$(behind_note opencode "$before" "$latest")
    if [ "$native" -eq 1 ]; then
      installed=$(native_opencode_version) || installed=""
      if [ -n "$installed" ] && [ "$installed" != "$before" ]; then
        note="$note native-installed=$installed"
      fi
    else
      installed=$(npm_global_version "$OPENCODE_NPM_PACKAGE") || installed=""
      if [ -n "$installed" ] && [ "$installed" != "$before" ]; then
        note="$note npm-installed=$installed"
      fi
    fi
    summary "opencode CHECK current=$before latest=$latest$note"
    return 0
  fi
  if [ "$native" -eq 1 ]; then
    if ! log_run "$OPENCODE_NATIVE_BIN" upgrade; then
      summary "opencode FAIL current=$before native upgrade failed"
      return 1
    fi
  elif ! npm_install_latest "$OPENCODE_NPM_PACKAGE"; then
    summary "opencode FAIL current=$before npm update failed"
    return 1
  fi
  hash -r
  after=$(installed_version opencode) || after=""
  if [ -z "$after" ]; then
    summary "opencode FAIL before=$before unable to read updated version"
    return 1
  fi
  # What the update just installed, not the registry: the PATH binary can be
  # another copy (a stale link into a hoisted tree, a leftover npm install
  # shadowing ~/.opencode/bin) that the update never replaced.
  if [ "$native" -eq 1 ]; then
    installed=$(native_opencode_version) || installed=""
    effective_lag opencode "$after" "$installed" "native installed" || return 1
  else
    installed=$(npm_global_version "$OPENCODE_NPM_PACKAGE") || installed=""
    effective_lag opencode "$after" "$installed" "npm installed" || return 1
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
    summary "ae CHECK current=$before target=${target:-pin-required}$(behind_note ae "$before" "$target")"
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
  effective_lag ae "$after" "$target" "pinned AE_VERSION" || return 1
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
    local lookup latest reason
    lookup=$(muse_latest)
    latest=${lookup%%$'\t'*}
    reason=${lookup#*$'\t'}
    if [ -n "$latest" ]; then
      summary "muse CHECK current=$before latest=$latest$(behind_note muse "$before" "$latest")"
    else
      summary "muse CHECK current=$before latest=unknown ($reason)"
    fi
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
export CHECK_ONLY INCLUDE_AE LOG_FILE LOG_DIR REPO_ROOT RETRY_ATTEMPTS CHECK_OUTDATED COPILOT_EXPECTED OPENCODE_NPM_PACKAGE OPENCODE_NATIVE_BIN
export -f summary run_with_retry log_run npm_mode nvm_exec npm_latest npm_install_latest \
  npm_global_version version_sorts_first version_older manager_command_v resolved_binary \
  behind_note effective_lag \
  opencode_available run_opencode native_opencode_version opencode_latest installed_version agy_latest grok_latest muse_latest \
  check_with_npm update_native install_muse process_claude process_codex \
  copilot_is_shim copilot_installed copilot_latest process_copilot process_agy process_grok process_opencode process_muse process_ae \
  process_contract

failures=0
for tool in claude codex agy grok opencode muse copilot ae contract; do
  if selected "$tool" && ! run_step "$tool"; then failures=1; fi
done

printf '[%s] harness update finish exit=%s\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$failures" >>"$LOG_FILE"

if [ "$failures" -ne 0 ] && [ "$(uname -s)" = Darwin ] && command -v osascript >/dev/null 2>&1; then
  osascript -e 'display notification "One or more CLI updates failed. Check ~/.local/state/harness-update/." with title "Harness update failed"' \
    >>"$LOG_FILE" 2>&1 || true
fi

exit "$failures"
