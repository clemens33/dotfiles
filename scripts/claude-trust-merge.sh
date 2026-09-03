#!/usr/bin/env bash
# Pre-accept Claude Code's "Do you trust the files in this folder?" dialog.
#
# Usage: claude-trust-merge.sh <path/to/.claude.json> <path/to/trusted-paths.txt>
#
# WHY A MERGE AND NOT A SYMLINK: .claude.json holds runtime state and is
# rewritten by Claude Code via write-then-rename, so it cannot be a symlink —
# same constraint as scripts/mcp-merge.sh, and this mirrors that shape.
#
# WHY PER PATH: Claude Code has NO global "trust everything" setting. Trust
# lives only at .projects["<repo root>"].hasTrustDialogAccepted, and it is a
# SEPARATE system from permissions — permissions.defaultMode=bypassPermissions
# does NOT suppress the trust dialog. The flag does cover subdirectories and
# worktrees of a listed root, so listing repo roots is enough.
#
# KNOWN LIMIT: trust for $HOME itself is held for the session only and is never
# persisted by Claude Code, so a session started directly in ~ re-prompts every
# time no matter what this script writes. Start in a project subdirectory.
#
# The merge is ADDITIVE and only ever sets the flag to true; every other key in
# each project entry is preserved, so re-running is safe and order-independent.
set -euo pipefail

target="$1"
paths_file="$2"

if ! command -v jq >/dev/null 2>&1; then
    echo "WARNING: jq not found, skipping trust merge for $target"
    exit 0
fi

if [ ! -f "$paths_file" ]; then
    echo "ERROR: trusted paths list not found: $paths_file" >&2
    exit 1
fi

# Strip comments and blanks; expand a leading ~ so the list stays portable
# between the WSL box and the Mac.
paths_json="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        -e '/^$/d' "$paths_file" \
    | sed -e "s|^~|$HOME|" \
    | jq -R . | jq -s .)"

# Refuse symlinks outright: Claude Code rewrites this file via rename, so a
# link never survives it anyway, and mv below would either replace the link
# or (link to a directory) drop the temp file inside it and leave the real
# target untouched.
if [ -L "$target" ]; then
    echo "ERROR: $target is a symlink; Claude Code state files must be regular files" >&2
    exit 1
fi
if [ -e "$target" ] && [ ! -f "$target" ]; then
    echo "ERROR: $target exists but is not a regular file" >&2
    exit 1
fi

dir="$(dirname "$target")"
mkdir -p "$dir"

tmp="$(mktemp "$dir/.claude.json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

if [ -f "$target" ]; then
    src="$target"
else
    echo '{}' > "$tmp.seed"
    src="$tmp.seed"
fi

# Two things happen here:
#   1. every path in the list is added (or flagged, if already present);
#   2. every project ALREADY in .claude.json that lies UNDER a listed root is
#      flagged too.
# (2) matters because Claude keys trust to the GIT REPO ROOT, so a listed
# parent like ~/projects/mic/ai does NOT cover the separate repos inside it.
# The prefix test is what keeps this from trusting everything ever opened:
# a /private/tmp clone or a one-off folder outside the listed roots keeps
# whatever answer was given at the time. Nothing is ever set to false and no
# other key is touched.
jq --argjson paths "$paths_json" '
    .projects = (
        ($paths | map({ (.): {} }) | add // {})
        * (.projects // {})
        | with_entries(
            if (.key as $k | $paths | any(. as $p | $k == $p or ($k | startswith($p + "/"))))
            then .value.hasTrustDialogAccepted = true
            else . end
          )
    )
' "$src" > "$tmp"

rm -f "$tmp.seed"

# Best-effort mode: Claude Code recreates this file under its own umask.
chmod 600 "$tmp"
mv "$tmp" "$target"
trap - EXIT

echo "Pre-accepted trust for $(printf '%s' "$paths_json" | jq 'length') path(s) in $target"
