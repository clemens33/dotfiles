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

Tools: claude, codex, agy, grok, opencode, muse, ae, dsh, contract

  --check       Report installed and latest versions without changing anything
  --only TOOL   Process one tool only
  --include-ae  Include ae; updates require an explicit AE_VERSION pin

contract is not a CLI: it reports harness instruction files that no longer match
the rendered contract. It never renders — run ./install for that.

dsh is CHECK-ONLY in both modes. The DeepSeek Harness pilot is a developer
preview pinned by deepseek-harness/package-lock.json, so this never upgrades it:
it reports the pinned RC, whether the runtime matches the lock, whether the
managed preset still matches the installed `standard` it was copied from, and
each configured MCP server.

Each tool has a 300-second deadline (HARNESS_UPDATE_TIMEOUT_SECONDS overrides it).
EOF
}

valid_tool() {
  case "$1" in
    claude|codex|agy|grok|opencode|muse|ae|dsh|contract) return 0 ;;
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
        printf 'error: --only requires one of: claude, codex, agy, grok, opencode, muse, ae, dsh, contract\n' >&2
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
process_dsh() {
  local prefix="${DSH_PREFIX:-$HOME/.local/share/dsh}"
  local dsh_home="${DSH_HOME:-$HOME/.dsh}"
  local tracked="$REPO_ROOT/deepseek-harness"
  local pinned installed shipped issues=0 degraded=0

  if [ ! -f "$tracked/package-lock.json" ]; then
    summary 'dsh SKIP not managed by this checkout'
    return 0
  fi
  if [ ! -x "$prefix/node_modules/.bin/dsh" ]; then
    summary 'dsh SKIP not installed - run ./install'
    return 0
  fi

  # The umbrella version is what we pin; the lock is what actually fixes the
  # plugin graph, where several agent-plane packages resolve one RC ahead.
  pinned=$(node -e 'const l=require(process.argv[1]);process.stdout.write(l.packages["node_modules/@deepseek-ai/dsh"].version)' \
    "$tracked/package-lock.json" 2>/dev/null) || pinned=""
  installed=$(DSH_HOME="$dsh_home" "$prefix/node_modules/.bin/dsh" --version 2>/dev/null | tr -d '[:space:]') || installed=""
  if [ -z "$pinned" ] || [ -z "$installed" ]; then
    summary 'dsh FAIL unable to read pinned or installed version'
    return 1
  fi
  if [ "$pinned" != "$installed" ]; then
    summary "dsh FAIL runtime $installed does not match pinned $pinned - run ./install"
    issues=1
  fi

  # Does the provisioned runtime still agree with the tracked inputs? A drifted
  # copy is why `npm ci` would reinstall, so report it rather than silently
  # trusting the prefix.
  local f
  for f in .npmrc package.json package-lock.json; do
    if ! cmp -s "$tracked/$f" "$prefix/$f"; then
      summary "dsh FAIL runtime $f differs from the tracked copy - run ./install"
      issues=1
    fi
  done

  # The pinned pnpm helper. It exists only because `dsh plugin` shells out to
  # pnpm and pnpm is the only installer that keeps ONE @deepseek-ai plane. It
  # lives in its own prefix so the official runtime graph stays byte-identical,
  # and it must never acquire a plane package of its own.
  local pnpm_prefix pnpm_entry pnpm_pinned pnpm_installed
  pnpm_prefix="${DSH_PNPM_PREFIX:-$HOME/.local/share/dsh-pnpm}"
  pnpm_entry="$pnpm_prefix/node_modules/pnpm/bin/pnpm.mjs"
  if [ ! -f "$pnpm_entry" ]; then
    summary 'dsh FAIL pinned pnpm helper is missing - run ./install'
    issues=1
  else
    for f in .npmrc package.json package-lock.json; do
      if ! cmp -s "$tracked/pnpm/$f" "$pnpm_prefix/$f"; then
        summary "dsh FAIL pnpm helper $f differs from the tracked copy - run ./install"
        issues=1
      fi
    done
    pnpm_pinned=$(node -e 'const l=require(process.argv[1]);process.stdout.write(l.packages["node_modules/pnpm"].version)' \
      "$tracked/pnpm/package-lock.json" 2>/dev/null) || pnpm_pinned=""
    pnpm_installed=$(node "$pnpm_entry" --version 2>/dev/null | tr -d '[:space:]') || pnpm_installed=""
    if [ -z "$pnpm_pinned" ] || [ -z "$pnpm_installed" ]; then
      summary 'dsh FAIL unable to read pinned or installed pnpm version'
      issues=1
    elif [ "$pnpm_pinned" != "$pnpm_installed" ]; then
      summary "dsh FAIL pnpm $pnpm_installed does not match pinned $pnpm_pinned - run ./install"
      issues=1
    fi
    if [ -n "$(find "$pnpm_prefix/node_modules" -type d -name '@deepseek-ai' -print 2>/dev/null | head -n 1)" ]; then
      summary 'dsh FAIL pnpm helper prefix contains @deepseek-ai packages - second plane'
      issues=1
    fi
  fi

  # The managed dsh-tui profile. Its three install inputs are tracked and its
  # node_modules must stay free of the plane: a single @deepseek-ai package
  # there is a split singleton, which is the condition this whole profile-local
  # shape exists to prevent.
  local tui_profile tui_pinned tui_locked tui_installed
  tui_profile="$dsh_home/profiles/dsh-tui"
  if [ ! -d "$tui_profile" ]; then
    summary 'dsh FAIL dsh-tui profile is missing - run ./install'
    issues=1
  else
    for f in package.json pnpm-workspace.yaml pnpm-lock.yaml; do
      if [ -L "$tui_profile/$f" ]; then
        summary "dsh FAIL dsh-tui profile $f is a symlink - run ./install"
        issues=1
      elif ! cmp -s "$tracked/profiles/dsh-tui/$f" "$tui_profile/$f"; then
        summary "dsh FAIL dsh-tui profile $f differs from the tracked copy - run ./install"
        issues=1
      fi
    done
    # Exact version AND integrity, from the tracked manifest and lock. The TUI
    # is community code with agent-host authority; a silently moved tarball is
    # exactly what the pin is for. No auto-upgrade here, by design.
    tui_pinned=$(node -e 'const m=require(process.argv[1]);process.stdout.write(m.dependencies["@deepseek-harness-tui/dsh-tui"]??"")' \
      "$tracked/profiles/dsh-tui/package.json" 2>/dev/null) || tui_pinned=""
    tui_locked=$(awk '/^  .@deepseek-harness-tui\/dsh-tui@/ { getline; if ($0 ~ /integrity:/) { sub(/.*integrity: /, ""); sub(/}.*/, ""); print; exit } }' \
      "$tracked/profiles/dsh-tui/pnpm-lock.yaml" 2>/dev/null) || tui_locked=""
    if [ -z "$tui_pinned" ] || [ -z "$tui_locked" ]; then
      summary 'dsh FAIL unable to read the pinned TUI version or its locked integrity'
      issues=1
    elif ! grep -q "@deepseek-harness-tui/dsh-tui@$tui_pinned'" "$tracked/profiles/dsh-tui/pnpm-lock.yaml"; then
      summary "dsh FAIL tracked pnpm-lock.yaml does not lock TUI $tui_pinned"
      issues=1
    fi
    # Everything above reads the TRACKED inputs, which proves only that this
    # checkout is self-consistent. What actually boots is the package in the
    # profile's node_modules, so read its version too: a profile installed
    # before a pin changed, or one whose install never completed, passes every
    # static gate while running something else entirely.
    tui_installed=$(node -e 'process.stdout.write(require(process.argv[1]).version ?? "")' \
      "$tui_profile/node_modules/@deepseek-harness-tui/dsh-tui/package.json" 2>/dev/null) || tui_installed=""
    if [ -z "$tui_installed" ]; then
      summary 'dsh FAIL the dsh-tui profile has no installed TUI package - run ./install'
      issues=1
    elif [ "$tui_installed" != "$tui_pinned" ]; then
      summary "dsh FAIL installed TUI $tui_installed does not match pinned $tui_pinned - run ./install"
      issues=1
    fi
    if [ -n "$(find "$tui_profile/node_modules" -type d -name '@deepseek-ai' -print 2>/dev/null | head -n 1)" ]; then
      summary 'dsh FAIL dsh-tui profile contains @deepseek-ai packages - second plane'
      issues=1
    fi
  fi

  # rc.1 offers no preset inheritance, so the managed preset is a COPY of the
  # shipped `standard` composition, and a DSH bump can move that source
  # underneath us. The snapshot region is delimited by one exact marker line:
  # everything before it must BE the installed standard, byte for byte, with no
  # difference in either direction. Comparing the shipped file's LINE COUNT
  # instead was wrong twice over - a standard that grew would read our own MCP
  # rows back as if they were upstream's, and one that shrank would silently
  # compare less than it should.
  local managed marker markers offset
  managed="$tracked/presets/dotfiles/agent.cordis.yml"
  marker='# ── MCP servers (dotfiles addition'
  shipped="$prefix/node_modules/@deepseek-ai/dsh-agent-presets/presets/standard/agent.cordis.yml"
  markers=$(grep -c -F -- "$marker" "$managed" 2>/dev/null) || markers=0
  if [ ! -f "$shipped" ]; then
    summary 'dsh FAIL installed standard preset not found for the drift check'
    issues=1
  elif [ "$markers" -ne 1 ]; then
    summary "dsh FAIL managed preset carries $markers MCP marker lines, expected exactly 1"
    issues=1
  else
    # Byte offset, not line number: the prefix is compared as bytes so a
    # changed line ending or a missing final newline counts as drift too.
    offset=$(grep -b -F -m1 -- "$marker" "$managed" | cut -d: -f1)
    if ! head -c "$offset" "$managed" | cmp -s - "$shipped"; then
      summary 'dsh FAIL managed preset drifted from the installed standard - refresh deepseek-harness/presets/dotfiles'
      issues=1
    fi
  fi

  # The runtime patch and preset are managed COPIES, never symlinks: a link
  # would aim the harness at the working tree and let anything that writes
  # through it land in the repo. Compare the copies to the tracked originals
  # exactly, and mirror the preset directory in both directions so a leftover
  # file from an older revision is reported rather than quietly composed.
  #
  # Three patch layers now, not one: the shared model route at the home level,
  # and one roster row per profile. They are NOT interchangeable - the roster id
  # differs between the surfaces - so each is compared against its own source.
  local runtime_patch runtime_preset src dst base pair label
  runtime_preset="$dsh_home/.agent-presets/dotfiles"
  for pair in \
    "cordis.patch.yml:$dsh_home/cordis.patch.yml:home" \
    "profiles/web/cordis.patch.yml:$dsh_home/profiles/web/cordis.patch.yml:web profile" \
    "profiles/dsh-tui/cordis.patch.yml:$dsh_home/profiles/dsh-tui/cordis.patch.yml:dsh-tui profile"; do
    src=${pair%%:*}
    runtime_patch=${pair#*:}
    label=${runtime_patch##*:}
    runtime_patch=${runtime_patch%:*}
    if [ -L "$runtime_patch" ]; then
      summary "dsh FAIL $label cordis.patch.yml is a symlink - run ./install to replace it with a managed copy"
      issues=1
    elif [ ! -f "$runtime_patch" ]; then
      summary "dsh FAIL $label cordis.patch.yml is missing - run ./install"
      issues=1
    elif ! cmp -s "$tracked/$src" "$runtime_patch"; then
      summary "dsh FAIL $label cordis.patch.yml differs from the tracked copy - run ./install"
      issues=1
    fi
  done
  if [ -L "$runtime_preset" ]; then
    summary 'dsh FAIL runtime preset is a symlink - run ./install to replace it with a managed copy'
    issues=1
  elif [ ! -d "$runtime_preset" ]; then
    summary 'dsh FAIL runtime preset directory is missing - run ./install'
    issues=1
  else
    # Redirected from a FILE, not from a pipe: a `while read` on the right of a
    # pipe runs in a subshell and every issues=1 set inside it is discarded.
    # A temp file keeps that correct without needing a bash-only construct.
    local listing
    listing=$(mktemp "${TMPDIR:-/tmp}/dsh-preset.XXXXXX")
    find "$tracked/presets/dotfiles" -type f | sort >"$listing"
    while IFS= read -r src; do
      base=${src##*/}
      if [ -L "$runtime_preset/$base" ]; then
        summary "dsh FAIL runtime preset file $base is a symlink - run ./install"
        issues=1
      elif ! cmp -s "$src" "$runtime_preset/$base"; then
        summary "dsh FAIL runtime preset file $base differs from the tracked copy - run ./install"
        issues=1
      fi
    done <"$listing"
    find "$runtime_preset" -type f | sort >"$listing"
    while IFS= read -r dst; do
      base=${dst##*/}
      if [ ! -f "$tracked/presets/dotfiles/$base" ]; then
        summary "dsh FAIL runtime preset carries $base, which this checkout does not track - run ./install"
        issues=1
      fi
    done <"$listing"
    rm -f "$listing"
  fi

  # Composition gate. The home layer applies to EVERY profile, so a row it
  # targets must exist in every profile's tree or that profile logs an
  # unmatched-row warning on every boot. `sdk-minimal` is the one shipped
  # template without `dsh-base`, and `llm-pi-ai` is a dsh-base row, so its
  # warning is expected and pinned here EXACTLY: a second warning line, or a
  # different one, is a real regression. --dump-config composes without serving.
  local composed dump_rc dump_err dump_out warn_n route_n prof expect_route
  local sdk_minimal_warning='patch: entry "llm-pi-ai" not found'
  dump_out=$(mktemp "${TMPDIR:-/tmp}/dsh-dump.XXXXXX")
  for prof in dsh-tui web headless acp sdk sdk-minimal; do
    expect_route=1
    [ "$prof" = sdk-minimal ] && expect_route=0
    dump_rc=0
    dump_err=$(DSH_HOME="$dsh_home" "$prefix/node_modules/.bin/dsh" --profile "$prof" \
      --dump-config 2>&1 >"$dump_out") || dump_rc=$?
    composed=$(cat "$dump_out" 2>/dev/null || true)
    warn_n=$(printf '%s' "$dump_err" | grep -c . || true)
    if [ "$dump_rc" -ne 0 ]; then
      summary "dsh FAIL profile $prof failed to compose: $(printf '%s' "$dump_err" | tr '\n' ';')"
      issues=1
      continue
    fi
    route_n=$(printf '%s\n' "$composed" | grep -c '^        baseURL: https://openrouter.ai/api/v1$' || true)
    if [ "$route_n" -ne "$expect_route" ]; then
      summary "dsh FAIL profile $prof carries $route_n OpenRouter route(s), expected $expect_route"
      issues=1
    fi
    if [ "$prof" = sdk-minimal ]; then
      # Exactly one warning line, and it must be the known one. A CHANGED single
      # line is reported as DEGRADED with the text quoted, because that is a
      # signal to read rather than a broken managed surface; anything more is a
      # failure.
      case $warn_n in
      0)
        summary 'dsh FAIL sdk-minimal no longer emits its known unmatched-row warning - the pinned exception is stale'
        issues=1
        ;;
      1)
        case $dump_err in
        *"$sdk_minimal_warning"*) : ;;
        *)
          summary "dsh DEGRADED sdk-minimal warning changed: $(printf '%s' "$dump_err" | tr '\n' ';')"
          degraded=1
          ;;
        esac
        ;;
      *)
        summary "dsh FAIL sdk-minimal emits more than the one pinned warning: $(printf '%s' "$dump_err" | tr '\n' ';')"
        issues=1
        ;;
      esac
    elif [ "$warn_n" -ne 0 ]; then
      summary "dsh FAIL profile $prof emits composition warnings: $(printf '%s' "$dump_err" | tr '\n' ';')"
      issues=1
    fi
  done
  rm -f "$dump_out"

  # Per-server MCP status, bounded and model-free. Severity is per SERVER, not
  # per run: Serena, Context7 and Chrome DevTools are the shared core set, and
  # losing one is a real failure worth the daily notification. OpenDesign only
  # answers while its loopback container runs, so its loss is explicit and
  # nonfatal. Exit 2 means the probe could not describe the live harness at all
  # - a missing or drifted managed preset - which is never "degraded".
  local mcp mcp_rc flat core_down reported=0
  mcp=$(node "$tracked/mcp-status.mjs" --timeout-ms 60000 2>&1)
  mcp_rc=$?
  flat=$(printf '%s' "$mcp" | tr '\n' ';' | sed 's/;$//')
  if [ "$mcp_rc" -ge 2 ]; then
    summary "dsh FAIL cannot probe the live MCP configuration: $flat"
    issues=1
    reported=1
  else
    core_down=$(printf '%s\n' "$mcp" |
      awk '/^mcp (serena|context7|chrome-devtools) DEGRADED/ { n++ } END { print n + 0 }')
    if [ "$core_down" -gt 0 ]; then
      summary "dsh FAIL $core_down core MCP server(s) unavailable: $flat"
      issues=1
      reported=1
    elif [ "$mcp_rc" -ne 0 ]; then
      summary "dsh DEGRADED optional MCP unavailable (nonfatal): $flat"
      reported=1
    fi
  fi

  # An earlier static failure must never be overwritten by an OK line.
  if [ "$reported" -eq 0 ]; then
    if [ "$issues" -ne 0 ]; then
      summary "dsh FAIL see the dsh lines above; pinned=$pinned $flat"
    elif [ "$degraded" -eq 0 ]; then
      summary "dsh OK pinned=$pinned $flat"
    else
      summary "dsh DEGRADED see the dsh lines above; pinned=$pinned $flat"
    fi
  fi

  [ "$issues" -eq 0 ]
}

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
  process_dsh process_contract

failures=0
for tool in claude codex agy grok opencode muse ae dsh contract; do
  if selected "$tool" && ! run_step "$tool"; then failures=1; fi
done

printf '[%s] harness update finish exit=%s\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$failures" >>"$LOG_FILE"

if [ "$failures" -ne 0 ] && [ "$(uname -s)" = Darwin ] && command -v osascript >/dev/null 2>&1; then
  osascript -e 'display notification "One or more CLI updates failed. Check ~/.local/state/harness-update/." with title "Harness update failed"' \
    >>"$LOG_FILE" 2>&1 || true
fi

exit "$failures"
