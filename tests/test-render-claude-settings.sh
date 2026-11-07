#!/bin/sh
# Tests for scripts/render-claude-settings.sh.
#
# Requirement under test: in claude-p and claude-mic sessions the contract must
# load once. Claude Code also loads ~/.claude/CLAUDE.md as the ancestor project
# file of $HOME, next to the profile's own copy, so the profile homes exclude
# that one path through claudeMdExcludes. ~/.claude/settings.json is shared with
# plain `claude` (where the file is the user memory) and must stay untouched.
# The profile homes get a RENDERED settings.json: the one canonical source
# (claude/settings.json) plus the exclude, never a second hand-kept file.
#
# Expected outcomes come from those requirements and from fixtures written in
# this file, not from the script's own output. The fixture source lives in a
# throwaway root: a regression that wrote through a symlink would corrupt the
# fixture, never this repo's claude/settings.json.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
SCRIPT=$ROOT/scripts/render-claude-settings.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-render-claude-settings.XXXXXX")

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

check() { # check <description> <command...>
    desc=$1
    shift
    if "$@"; then ok "$desc"; else bad "$desc"; fi
}

contains() {
    grep -Fq -- "$2" "$1"
}

not_contains() {
    ! grep -Fq -- "$2" "$1"
}

sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{ print $1 }'
    else
        sha256sum "$1" | awk '{ print $1 }'
    fi
}

inode() {
    ls -i "$1" | awk '{ print $1 }'
}

FIXTURE='{
  "model": "opus",
  "permissions": { "deny": ["Bash(rm -rf /)"], "defaultMode": "bypassPermissions" },
  "enabledPlugins": { "alpha@market": true, "beta@market": false },
  "autoMemoryEnabled": true
}'

# make_root <name>: a root with the script symlinked in and a fixture source.
make_root() {
    root=$TMP_ROOT/$1
    mkdir -p "$root/scripts" "$root/claude"
    ln -s "$SCRIPT" "$root/scripts/render-claude-settings.sh"
    printf '%s\n' "$FIXTURE" >"$root/claude/settings.json"
}

# make_home <name> <identity dirs...>
make_home() {
    home=$TMP_ROOT/$1
    shift
    mkdir -p "$home"
    for dir do
        mkdir -p "$home/$dir"
    done
}

# legacy_links <root> <home> <dirs...>: the pre-fix install state, every
# identity's settings.json a symlink to the canonical source.
legacy_links() {
    lr=$TMP_ROOT/$1
    lh=$TMP_ROOT/$2
    shift 2
    for dir do
        ln -s "$lr/claude/settings.json" "$lh/$dir/settings.json"
    done
}

# render <root> <home> [args...] — never inherits the caller's HOME.
render() {
    r=$TMP_ROOT/$1
    h=$TMP_ROOT/$2
    shift 2
    HOME=$h sh "$r/scripts/render-claude-settings.sh" "$@"
}

# render_quiet <root> <home> [args...]: same, output discarded (for check).
render_quiet() {
    render "$@" >/dev/null 2>&1
}

# json_is <file> <jq-boolean-program>: true when the program is true for the file.
json_is() {
    jq -e "$2" "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 1. Install on the legacy state: symlinks become rendered regular files
# ---------------------------------------------------------------------------
make_root a
make_home h1 .claude .claude-p .claude-mic
legacy_links a h1 .claude .claude-p .claude-mic
src_before=$(sha256 "$TMP_ROOT/a/claude/settings.json")
render a h1 >"$TMP_ROOT/out1" 2>"$TMP_ROOT/err1" || bad "render exited non-zero"

for id in .claude-p .claude-mic; do
    t=$TMP_ROOT/h1/$id/settings.json
    check "$id/settings.json is a regular file, not a symlink" test -f "$t" -a ! -L "$t"
    check "$id/settings.json excludes exactly the HOME contract path" \
        json_is "$t" ".claudeMdExcludes == [\"$TMP_ROOT/h1/.claude/CLAUDE.md\"]"
    check "$id/settings.json keeps every source key and value" \
        json_is "$t" "del(.claudeMdExcludes) == $FIXTURE"
done
check 'canonical source is byte-identical (no write-through)' \
    test "$(sha256 "$TMP_ROOT/a/claude/settings.json")" = "$src_before"
check 'plain ~/.claude/settings.json is still a symlink to the source' \
    test "$(readlink "$TMP_ROOT/h1/.claude/settings.json")" = "$TMP_ROOT/a/claude/settings.json"
check 'plain ~/.claude has no exclude (the contract is its user memory)' \
    not_contains "$TMP_ROOT/a/claude/settings.json" claudeMdExcludes
check 'summary reports two renders' contains "$TMP_ROOT/out1" 'settings: 2 rendered'

# ---------------------------------------------------------------------------
# 2. The excluded path is the one render-contract.sh writes for plain claude
# ---------------------------------------------------------------------------
check 'render-contract.sh still writes the excluded path' \
    contains "$ROOT/scripts/render-contract.sh" '$HOME/.claude|$HOME/.claude/CLAUDE.md'

# ---------------------------------------------------------------------------
# 3. Idempotence and --check
# ---------------------------------------------------------------------------
ino=$(inode "$TMP_ROOT/h1/.claude-p/settings.json")
render a h1 >"$TMP_ROOT/out3" 2>&1 || bad "second render exited non-zero"
check 'second render writes nothing' contains "$TMP_ROOT/out3" 'settings: 0 rendered'
check 'second render leaves the file in place' \
    test "$(inode "$TMP_ROOT/h1/.claude-p/settings.json")" = "$ino"
check '--check is clean after render' render_quiet a h1 --check

make_home h2 .claude .claude-p .claude-mic
legacy_links a h2 .claude-p
if render a h2 --check >"$TMP_ROOT/out3b" 2>&1; then
    bad '--check accepted a legacy symlink'
else
    ok '--check fails on a legacy symlink'
fi
check '--check labels the legacy symlink' contains "$TMP_ROOT/out3b" "legacy $TMP_ROOT/h2/.claude-p/settings.json"
check '--check does not mutate' test -L "$TMP_ROOT/h2/.claude-p/settings.json"

# A formatting-only rewrite is not drift: Claude Code may reserialise the file.
jq -c . "$TMP_ROOT/h1/.claude-p/settings.json" >"$TMP_ROOT/compact.json"
cp "$TMP_ROOT/compact.json" "$TMP_ROOT/h1/.claude-p/settings.json"
check '--check ignores formatting-only changes' render_quiet a h1 --check

# ---------------------------------------------------------------------------
# 4. Drift: nested runtime change, source edit, foreign symlink
# ---------------------------------------------------------------------------
jq '.enabledPlugins."gamma@market" = true | .model = "sonnet"' "$TMP_ROOT/h1/.claude-p/settings.json" \
    >"$TMP_ROOT/drift.json"
cp "$TMP_ROOT/drift.json" "$TMP_ROOT/h1/.claude-p/settings.json"
if render a h1 --check >"$TMP_ROOT/out4" 2>&1; then
    bad '--check accepted a runtime change'
else
    ok '--check fails on a runtime change'
fi
check '--check marks the target stale' contains "$TMP_ROOT/out4" "stale $TMP_ROOT/h1/.claude-p/settings.json"
check '--check names the top-level key' contains "$TMP_ROOT/out4" 'differs: model'
check '--check names the top-level object key' contains "$TMP_ROOT/out4" 'differs: enabledPlugins'
check '--check names the first nested key' contains "$TMP_ROOT/out4" 'differs: enabledPlugins.gamma@market'
check '--check does not list unchanged keys' not_contains "$TMP_ROOT/out4" 'differs: permissions'
check '--check does not mutate a stale target' \
    json_is "$TMP_ROOT/h1/.claude-p/settings.json" '.model == "sonnet"'

render a h1 >"$TMP_ROOT/out4b" 2>"$TMP_ROOT/err4b" || bad "overwrite render exited non-zero"
check 'install warns before it overwrites a runtime change' contains "$TMP_ROOT/err4b" 'WARN'
check 'install warning names the differing nested key' contains "$TMP_ROOT/err4b" 'differs: enabledPlugins.gamma@market'
check 'install restores the source value' json_is "$TMP_ROOT/h1/.claude-p/settings.json" '.model == "opus"'

printf '%s\n' "$FIXTURE" | jq '.model = "haiku"' >"$TMP_ROOT/a/claude/settings.json"
if render a h1 --check >"$TMP_ROOT/out4c" 2>&1; then
    bad '--check missed a source edit'
else
    ok '--check fails after the canonical source changes'
fi
check '--check reports the source edit as stale' contains "$TMP_ROOT/out4c" "stale $TMP_ROOT/h1/.claude-p/settings.json"
printf '%s\n' "$FIXTURE" >"$TMP_ROOT/a/claude/settings.json"

make_home h3 .claude .claude-p
mkdir -p "$TMP_ROOT/elsewhere"
printf '{"model":"x"}\n' >"$TMP_ROOT/elsewhere/settings.json"
ln -s "$TMP_ROOT/elsewhere/settings.json" "$TMP_ROOT/h3/.claude-p/settings.json"
if render a h3 --check >"$TMP_ROOT/out4d" 2>&1; then
    bad '--check accepted a foreign symlink'
else
    ok '--check fails on a foreign symlink'
fi
check '--check labels a foreign symlink stale, not legacy' contains "$TMP_ROOT/out4d" "stale $TMP_ROOT/h3/.claude-p/settings.json"
check '--check does not call a foreign symlink legacy' not_contains "$TMP_ROOT/out4d" 'legacy '
check 'foreign symlink target file is untouched' contains "$TMP_ROOT/elsewhere/settings.json" '{"model":"x"}'
render a h3 >"$TMP_ROOT/out4e" 2>"$TMP_ROOT/err4e" || bad "foreign symlink render exited non-zero"
check 'install replaces a foreign symlink with a regular file' test -f "$TMP_ROOT/h3/.claude-p/settings.json" -a ! -L "$TMP_ROOT/h3/.claude-p/settings.json"
check 'install never wrote through a foreign symlink' contains "$TMP_ROOT/elsewhere/settings.json" '{"model":"x"}'

# Presence counts, not only value: an absent key and an explicit null differ.
make_root n
printf '{"enabledPlugins":{}}\n' >"$TMP_ROOT/n/claude/settings.json"
make_home h11 .claude-p
render n h11 >/dev/null 2>&1 || bad "null-case render exited non-zero"
jq '.runtime = null | .enabledPlugins.x = null' "$TMP_ROOT/h11/.claude-p/settings.json" >"$TMP_ROOT/null-add.json"
cp "$TMP_ROOT/null-add.json" "$TMP_ROOT/h11/.claude-p/settings.json"
render n h11 --check >"$TMP_ROOT/out4h" 2>&1 || true
check 'added null top-level key is reported' contains "$TMP_ROOT/out4h" 'differs: runtime'
check 'added null nested key is reported' contains "$TMP_ROOT/out4h" 'differs: enabledPlugins.x'
check 'the object holding the added null key is reported' contains "$TMP_ROOT/out4h" 'differs: enabledPlugins'

printf '{"a":null,"enabledPlugins":{"x":null}}\n' >"$TMP_ROOT/n/claude/settings.json"
jq -n --arg p "$TMP_ROOT/h11/.claude/CLAUDE.md" '{enabledPlugins:{}, claudeMdExcludes:[$p]}' >"$TMP_ROOT/h11/.claude-p/settings.json"
render n h11 --check >"$TMP_ROOT/out4i" 2>&1 || true
check 'removed null top-level key is reported' contains "$TMP_ROOT/out4i" 'differs: a'
check 'removed null nested key is reported' contains "$TMP_ROOT/out4i" 'differs: enabledPlugins.x'
render n h11 >/dev/null 2>"$TMP_ROOT/err4i" || bad "null-removal render exited non-zero"
check 'install warning names the removed null key' contains "$TMP_ROOT/err4i" 'differs: a'
check 'install restores the null keys from the source' \
    json_is "$TMP_ROOT/h11/.claude-p/settings.json" 'has("a") and .a == null and (.enabledPlugins | has("x"))'

# The legacy label is for this repository only: a sibling worktree of the same
# repo counts (a worktree running the checks sees the live checkout's links),
# the claude/settings.json of any other repository does not.
git_commit() { # git_commit <repo>: commit everything, no identity or signing config needed
    git -C "$1" add -A >/dev/null 2>&1
    git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false \
        commit -q -m init >/dev/null 2>&1
}
make_root g
git -C "$TMP_ROOT/g" init -q >/dev/null 2>&1
printf 'scripts\n' >"$TMP_ROOT/g/.gitignore"
git_commit "$TMP_ROOT/g"
git -C "$TMP_ROOT/g" worktree add -q "$TMP_ROOT/g-sibling" >/dev/null 2>&1
mkdir -p "$TMP_ROOT/other-repo/claude"
printf '{"model":"other"}\n' >"$TMP_ROOT/other-repo/claude/settings.json"
git -C "$TMP_ROOT/other-repo" init -q >/dev/null 2>&1
git_commit "$TMP_ROOT/other-repo"
check 'fixture: sibling worktree has its own claude/settings.json' test -f "$TMP_ROOT/g-sibling/claude/settings.json"

make_home h9 .claude-p
ln -s "$TMP_ROOT/g-sibling/claude/settings.json" "$TMP_ROOT/h9/.claude-p/settings.json"
if render g h9 --check >"$TMP_ROOT/out4f" 2>&1; then
    bad '--check accepted a symlink into a sibling worktree'
else
    ok '--check fails on a sibling-worktree symlink (not yet migrated)'
fi
check 'sibling-worktree symlink is legacy' contains "$TMP_ROOT/out4f" "legacy $TMP_ROOT/h9/.claude-p/settings.json"
check 'sibling-worktree symlink is not stale' not_contains "$TMP_ROOT/out4f" 'stale '

make_home h10 .claude-p
ln -s "$TMP_ROOT/other-repo/claude/settings.json" "$TMP_ROOT/h10/.claude-p/settings.json"
if render g h10 --check >"$TMP_ROOT/out4g" 2>&1; then
    bad '--check accepted a symlink into another repository'
else
    ok '--check fails on a symlink into another repository'
fi
check 'other-repo symlink is stale' contains "$TMP_ROOT/out4g" "stale $TMP_ROOT/h10/.claude-p/settings.json"
check 'other-repo symlink is not legacy' not_contains "$TMP_ROOT/out4g" 'legacy '
render g h10 >/dev/null 2>&1 || bad "other-repo symlink render exited non-zero"
check 'install replaces an other-repo symlink with a regular file' \
    test -f "$TMP_ROOT/h10/.claude-p/settings.json" -a ! -L "$TMP_ROOT/h10/.claude-p/settings.json"
check 'install never wrote through into the other repository' \
    contains "$TMP_ROOT/other-repo/claude/settings.json" '{"model":"other"}'

# ---------------------------------------------------------------------------
# 5. Identity gating: an absent identity is skipped, never created
# ---------------------------------------------------------------------------
make_home h4 .claude .claude-p
render a h4 >"$TMP_ROOT/out5" 2>&1 || bad "render without .claude-mic exited non-zero"
check 'absent ~/.claude-mic is not created' test ! -e "$TMP_ROOT/h4/.claude-mic"
check 'present ~/.claude-p is rendered' test -f "$TMP_ROOT/h4/.claude-p/settings.json"
check 'summary counts the skipped identity' contains "$TMP_ROOT/out5" '1 skipped'
check '--check passes with the identity absent' render_quiet a h4 --check

# ---------------------------------------------------------------------------
# 6. Source already carries an exclude: kept, not duplicated, not replaced
# ---------------------------------------------------------------------------
make_root b
printf '%s\n' "$FIXTURE" | jq '.claudeMdExcludes = ["/keep/me.md"]' >"$TMP_ROOT/b/claude/settings.json"
make_home h5 .claude-p
render b h5 >/dev/null 2>&1 || bad "render with source exclude exited non-zero"
check 'source exclude kept and HOME contract path added' \
    json_is "$TMP_ROOT/h5/.claude-p/settings.json" \
    ".claudeMdExcludes == [\"/keep/me.md\", \"$TMP_ROOT/h5/.claude/CLAUDE.md\"]"
render b h5 >/dev/null 2>&1 || bad "re-render with source exclude exited non-zero"
check 'rerun does not duplicate the exclude' \
    json_is "$TMP_ROOT/h5/.claude-p/settings.json" '.claudeMdExcludes | length == 2'

# ---------------------------------------------------------------------------
# 7. Failure modes are loud: no jq, no source, bad source
# ---------------------------------------------------------------------------
make_home h6 .claude-p
legacy_links a h6 .claude-p
mkdir -p "$TMP_ROOT/empty-path"
no_jq_rc=0
PATH=$TMP_ROOT/empty-path HOME=$TMP_ROOT/h6 /bin/sh "$TMP_ROOT/a/scripts/render-claude-settings.sh" \
    >"$TMP_ROOT/out7" 2>&1 || no_jq_rc=$?
check 'missing jq exits 2' test "$no_jq_rc" -eq 2
check 'missing jq says so' contains "$TMP_ROOT/out7" 'jq'
check 'missing jq leaves the legacy symlink alone' test -L "$TMP_ROOT/h6/.claude-p/settings.json"

make_root c
rm "$TMP_ROOT/c/claude/settings.json"
make_home h7 .claude-p
no_src_rc=0
render c h7 >"$TMP_ROOT/out7b" 2>&1 || no_src_rc=$?
check 'missing source exits 2' test "$no_src_rc" -eq 2

printf '{ not json\n' >"$TMP_ROOT/c/claude/settings.json"
bad_src_rc=0
render c h7 >"$TMP_ROOT/out7c" 2>&1 || bad_src_rc=$?
check 'invalid source JSON exits 2' test "$bad_src_rc" -eq 2
check 'invalid source writes nothing' test ! -e "$TMP_ROOT/h7/.claude-p/settings.json"

usage_rc=0
render a h1 --bogus >"$TMP_ROOT/out7d" 2>&1 || usage_rc=$?
check 'unknown argument exits 2' test "$usage_rc" -eq 2

# ---------------------------------------------------------------------------
# 8. A HOME with spaces
# ---------------------------------------------------------------------------
make_home 'h 8' .claude .claude-p
render a 'h 8' >/dev/null 2>&1 || bad "render in a HOME with spaces exited non-zero"
check 'HOME with spaces: exclude path keeps the space' \
    json_is "$TMP_ROOT/h 8/.claude-p/settings.json" ".claudeMdExcludes == [\"$TMP_ROOT/h 8/.claude/CLAUDE.md\"]"

# ---------------------------------------------------------------------------
# 9. Install wiring (public layer)
# ---------------------------------------------------------------------------
tilde='~'
check 'install.conf.yaml no longer symlinks ~/.claude-p/settings.json' \
    not_contains "$ROOT/install.conf.yaml" "$tilde/.claude-p/settings.json:"
check 'install.conf.yaml renders the profile settings' \
    contains "$ROOT/install.conf.yaml" 'scripts/render-claude-settings.sh'
check 'install.conf.yaml keeps the plain ~/.claude/settings.json symlink' \
    contains "$ROOT/install.conf.yaml" "$tilde/.claude/settings.json:"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
