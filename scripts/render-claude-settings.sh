#!/bin/sh
# Render claude/settings.json into the settings of the extra Claude Code profiles.
#
# Why: claude-p and claude-mic (CLAUDE_CONFIG_DIR=~/.claude-p, ~/.claude-mic) load
# their own rendered contract as user memory AND, walking up from any cwd under
# $HOME, ~/.claude/CLAUDE.md as the ancestor project file of $HOME. That is the
# same contract twice per session. A profile therefore excludes that one path
# with claudeMdExcludes. The exclude cannot live in claude/settings.json: plain
# `claude` shares that file, and for it ~/.claude/CLAUDE.md is the user memory.
# The setting is read from $CLAUDE_CONFIG_DIR/settings.json, so it covers every
# launcher: the fish functions, bash, and ae (which sets the variable itself).
#
# Sources: claude/settings.json (the one canonical file). Output per profile:
# the source plus claudeMdExcludes: ["$HOME/.claude/CLAUDE.md"], written as a
# REGULAR file. A source that already lists excludes keeps them.
#
# SAFETY: before this script, every target was a symlink to claude/settings.json.
# A target is never written through (that would overwrite the canonical file):
# content goes to a temp file next to the target, the target is unlinked, then
# the temp file is moved into place.
#
# OVERWRITE: runtime changes Claude Code makes to a profile's settings.json (a
# plugin toggled, a model chosen) are replaced at install, by decision. Before
# replacing a file that differs, the script prints WARN and every differing key
# path (top level and first nested level) so the change can be promoted into
# claude/settings.json first. --check prints the same diff and writes nothing.
#
# Exit codes: 0 ok | 1 stale or legacy targets (--check) or a failed write
# | 2 usage error, missing jq or source, invalid source, unresolvable target.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SOURCE="$ROOT/claude/settings.json"
EXCLUDE="$HOME/.claude/CLAUDE.md"

usage() {
    cat <<'EOF'
Usage: scripts/render-claude-settings.sh [--check]

Renders claude/settings.json plus claudeMdExcludes for ~/.claude/CLAUDE.md into
~/.claude-p/settings.json and ~/.claude-mic/settings.json, so a profile session
loads the contract once.

  --check   Report targets that are out of date, exit 1. Writes nothing.
            "legacy <path>": a symlink to this repo's claude/settings.json
            (state before the first install of this script).
            "stale <path>": anything else that is not the rendered content,
            followed by the differing key paths.

A target is skipped when its identity directory does not exist: this script
never creates one.
EOF
}

check_only=0
if [ "$#" -gt 1 ]; then
    printf 'render-claude-settings: too many arguments\n' >&2
    usage >&2
    exit 2
fi
case "${1:-}" in
    '') ;;
    --check) check_only=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
        printf 'render-claude-settings: unknown argument: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

# jq is required, and its absence is loud: a silent skip would leave the old
# symlink in place and the contract loading twice.
if ! command -v jq >/dev/null 2>&1; then
    printf 'render-claude-settings: jq not found; install it (brew install jq | apt install jq)\n' >&2
    exit 2
fi
if [ ! -f "$SOURCE" ]; then
    printf 'render-claude-settings: missing source: %s\n' "$SOURCE" >&2
    exit 2
fi
if ! jq -e 'type == "object"' "$SOURCE" >/dev/null 2>&1; then
    printf 'render-claude-settings: source is not a JSON object: %s\n' "$SOURCE" >&2
    exit 2
fi

# identity directory | target file. The identity gate matches render-contract.sh:
# ./install creates ~/.claude-p (public pass) and the overlay creates ~/.claude-mic,
# so a machine without the overlay simply has no second profile to render.
targets() {
    cat <<EOF
$HOME/.claude-p|$HOME/.claude-p/settings.json
$HOME/.claude-mic|$HOME/.claude-mic/settings.json
EOF
}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/render-claude-settings.XXXXXX")
staged=""
# Reached through the trap below, which shellcheck does not follow.
# shellcheck disable=SC2329
cleanup() {
    rm -rf "$work_dir"
    [ -z "$staged" ] || rm -f "$staged"
}
trap cleanup EXIT HUP INT TERM

rendered=$work_dir/settings.json
jq --arg p "$EXCLUDE" '
    (.claudeMdExcludes // []) as $e
    | .claudeMdExcludes = (if ($e | index($p)) != null then $e else $e + [$p] end)
' "$SOURCE" >"$rendered"

# differing_keys <target>: one "differs: <path>" line per top-level key and per
# first-nested key whose presence or value differs between the target and the
# rendered text. Values are wrapped in a one-element array so an absent key and
# an explicit null are different (a bare lookup returns null for both).
differing_keys() {
    jq -n -r --slurpfile a "$1" --slurpfile b "$rendered" '
        def flat:
            . as $d
            | reduce (keys_unsorted[]) as $k ({};
                . + {($k): [$d[$k]]}
                + (if ($d[$k] | type) == "object"
                   then ($d[$k] | with_entries({key: ($k + "." + .key), value: [.value]}))
                   else {} end));
        ($a[0] | flat) as $x | ($b[0] | flat) as $y
        | (($x | keys) + ($y | keys) | unique)[] as $k
        | select($x[$k] != $y[$k])
        | "differs: " + $k
    '
}

# common_dir <dir>: absolute git common dir of the repository containing <dir>
# (the same for a checkout and every worktree of it), or empty.
common_dir() {
    (cd "$1" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || true
}

# is_repo_source <resolved path>: this checkout's claude/settings.json, or the
# same file in another worktree of the same repository (a worktree running the
# checks sees the symlinks the live checkout installed). A claude/settings.json
# of any other repository is foreign.
is_repo_source() {
    [ "$1" = "$SOURCE" ] && return 0
    case "$1" in
        */claude/settings.json) ;;
        *) return 1 ;;
    esac
    mine=$(common_dir "$ROOT")
    theirs=$(common_dir "${1%/claude/settings.json}")
    [ -n "$mine" ] && [ "$mine" = "$theirs" ]
}

n_written=0
n_unchanged=0
n_skipped=0
n_legacy=0
n_stale=0
n_failed=0

while IFS='|' read -r identity target; do
    [ -n "$target" ] || continue
    if [ ! -d "$identity" ]; then
        n_skipped=$((n_skipped + 1))
        continue
    fi
    if [ -d "$target" ] && [ ! -L "$target" ]; then
        printf 'render-claude-settings: %s is a directory - resolve manually\n' "$target" >&2
        n_failed=$((n_failed + 1))
        continue
    fi

    # Classify the target: current | legacy | stale (+ detail lines in $detail).
    detail=""
    if [ -L "$target" ]; then
        resolved=$(readlink -f "$target" 2>/dev/null || true)
        if [ -n "$resolved" ] && [ -f "$resolved" ] && is_repo_source "$resolved"; then
            state=legacy
        else
            state=stale
            detail="  foreign symlink -> ${resolved:-unresolvable}"
        fi
    elif [ ! -e "$target" ]; then
        state=stale
        detail="  missing"
    elif ! jq -e 'type == "object"' "$target" >/dev/null 2>&1; then
        state=stale
        detail="  not a JSON object"
    elif jq -n -e --slurpfile a "$target" --slurpfile b "$rendered" '$a[0] == $b[0]' >/dev/null 2>&1; then
        state=current
    else
        state=stale
        detail=$(differing_keys "$target" | sed 's/^/  /')
    fi

    if [ "$state" = current ]; then
        n_unchanged=$((n_unchanged + 1))
        continue
    fi

    if [ "$check_only" -eq 1 ]; then
        if [ "$state" = legacy ]; then
            printf 'legacy %s\n' "$target"
            n_legacy=$((n_legacy + 1))
        else
            printf 'stale %s\n' "$target"
            [ -z "$detail" ] || printf '%s\n' "$detail"
            n_stale=$((n_stale + 1))
        fi
        continue
    fi

    # Install: replace anything that is not the rendered content. A legacy
    # symlink is the expected migration and needs no warning.
    if [ "$state" = stale ] && [ "$detail" != "  missing" ]; then
        {
            printf 'WARN: %s differs from claude/settings.json plus the contract exclude; it is replaced.\n' "$target"
            printf '%s\n' "$detail"
            printf '      Promote a wanted runtime change into %s first.\n' "$SOURCE"
        } >&2
    fi
    dir=${target%/*}
    if ! mkdir -p "$dir"; then
        n_failed=$((n_failed + 1))
        continue
    fi
    # Staged inside the destination directory so the final move is a rename on
    # one filesystem, and so no partial file is ever visible.
    staged=$(mktemp "$dir/.render-claude-settings.XXXXXX")
    cp "$rendered" "$staged"
    chmod 644 "$staged"
    rm -f "$target"
    mv "$staged" "$target"
    staged=""
    printf 'rendered %s\n' "$target"
    n_written=$((n_written + 1))
done <<EOF
$(targets)
EOF

if [ "$check_only" -eq 1 ]; then
    if [ "$n_failed" -gt 0 ]; then
        exit 2
    fi
    printf 'settings: %d up to date, %d legacy, %d stale, %d skipped\n' \
        "$n_unchanged" "$n_legacy" "$n_stale" "$n_skipped"
    [ "$n_stale" -eq 0 ] && [ "$n_legacy" -eq 0 ] || exit 1
    exit 0
fi

printf 'settings: %d rendered, %d unchanged, %d skipped\n' \
    "$n_written" "$n_unchanged" "$n_skipped"
[ "$n_failed" -eq 0 ] || exit 1
