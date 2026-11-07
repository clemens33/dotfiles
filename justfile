# Checks and maintenance for this dotfiles repo. `just` lists the recipes.
#
#   just check       lint + contract + test; offline, read-only, what CI runs
#   just versions    installed harness versions (informational, never fails)
#   just update      explicit: update harnesses (network)   just brew / install likewise
#
# Every recipe runs under bash (3.2-safe, no bash-4 features), never the login
# shell. Output uses three words: ok, FAIL, SKIP. A SKIP names why and how to enable
# the step; a missing REQUIRED tool is a FAIL, never a quiet pass.
# See README.md "Commands (just)".

set shell := ["bash", "-euo", "pipefail", "-c"]
set positional-arguments

# Shared by the shebang recipes: result counters and the one-line tally.
lib := '''
set -u
n_ok=0; n_fail=0; n_skip=0; skipped=""
ok()   { printf '  ok    %s\n' "$*"; n_ok=$((n_ok + 1)); }
bad()  { printf '  FAIL  %s%s\n' "$1" "${2:+: $2}"; n_fail=$((n_fail + 1)); }
skip() { printf '  SKIP  %s%s\n' "$1" "${2:+ ($2)}"; n_skip=$((n_skip + 1)); skipped="$skipped $1"; }
tally() {
    printf '%s: %d ok, %d failed, %d skipped%s\n' "$1" "$n_ok" "$n_fail" "$n_skip" "${skipped:+ (${skipped# })}"
    [ "$n_fail" -eq 0 ]
}
'''

# python hint printed when no interpreter has PyYAML and a TOML parser
py_hint := "install PyYAML for python3 (apt install python3-yaml | brew install pyyaml), or run: uv run --no-project --python 3.12 --with pyyaml==6.0.3 just check"

# list the recipes
default:
    @"{{just_executable()}}" --justfile "{{justfile()}}" --list --unsorted

# every offline gate (lint, contract, test); runs all, names each failed gate
check:
    #!/usr/bin/env bash
    set -u
    failed=""
    for gate in lint contract test; do
        printf '\n'
        "{{just_executable()}}" --justfile "{{justfile()}}" "$gate" || failed="$failed $gate"
    done
    printf '\n'
    if [ -n "$failed" ]; then
        printf 'check: FAIL (failed gates:%s)\n' "$failed"
        exit 1
    fi
    printf 'check: all gates passed\n'

# static checks of tracked files: shell syntax, fish, shellcheck, configs, skills
lint:
    #!/usr/bin/env bash
    {{lib}}
    echo "==> lint"
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-lint.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT HUP INT TERM
    git -c core.quotePath=false ls-files -s | while IFS=$'\t' read -r meta f; do
        [ -f "$f" ] || continue
        case "$f" in
            *.fish) printf '%s\n' "$f" >>"$tmp/fish"; continue ;;
        esac
        case "${meta%% *}:$f" in
            100755:*|*:*.sh) ;;
            *) continue ;;
        esac
        first=$(LC_ALL=C head -n 1 "$f" 2>/dev/null || true)
        case "$first" in
            '#!/bin/sh'*|'#!/usr/bin/env sh'*) printf '%s\n' "$f" >>"$tmp/sh" ;;
            '#!'*bash*) printf '%s\n' "$f" >>"$tmp/bash" ;;
            *) case "$f" in *.sh) printf '%s\n' "$f" >>"$tmp/bash" ;; esac ;;
        esac
    done
    touch "$tmp/sh" "$tmp/bash" "$tmp/fish"
    n_sh=$(wc -l <"$tmp/sh" | tr -d ' ')
    n_bash=$(wc -l <"$tmp/bash" | tr -d ' ')

    # syntax_check TOOL LISTFILE: run `TOOL -n` on each listed file, collect the first error line per file
    syntax_check() {
        while IFS= read -r f; do
            "$1" -n "$f" 2>"$tmp/err" || printf '%s: %s\n' "$f" "$(head -n 1 "$tmp/err")" >>"$tmp/errs"
        done <"$2"
    }

    # 1. shell syntax (required)
    : >"$tmp/errs"; syntax_check sh "$tmp/sh"; syntax_check bash "$tmp/bash"
    if [ ! -s "$tmp/errs" ]; then ok "shell syntax ($n_sh sh, $n_bash bash files)"
    else bad "shell-syntax"; sed 's/^/        /' "$tmp/errs"; fi

    # 2. fish syntax (optional: needs fish)
    if [ ! -s "$tmp/fish" ]; then skip "fish-syntax" "no tracked .fish files"
    elif ! command -v fish >/dev/null 2>&1; then skip "fish-syntax" "optional: fish not installed"
    else
        : >"$tmp/errs"; syntax_check fish "$tmp/fish"
        if [ ! -s "$tmp/errs" ]; then ok "fish syntax ($(wc -l <"$tmp/fish" | tr -d ' ') files)"
        else bad "fish-syntax"; sed 's/^/        /' "$tmp/errs"; fi
    fi

    # 3. shellcheck (optional: needs shellcheck). -e SC1007: the intentional `CDPATH= cd` idiom.
    if ! command -v shellcheck >/dev/null 2>&1; then
        skip "shellcheck" "optional: shellcheck not installed"
    else
        cat "$tmp/sh" "$tmp/bash" | tr '\n' '\0' | xargs -0 shellcheck -S warning -e SC1007 -x >"$tmp/sc" 2>&1 \
            && ok "shellcheck ($n_sh sh, $n_bash bash files, severity warning)" \
            || { bad "shellcheck"; sed 's/^/        /' "$tmp/sc"; }
    fi

    # 4. config parse (required): tracked json, jsonc, toml, yaml, plus gitconfig
    if ! py=$("{{just_executable()}}" --justfile "{{justfile()}}" _python 2>"$tmp/pyerr"); then
        bad "config-parse" "no usable python"; sed 's/^/        /' "$tmp/pyerr"
    else
        git -c core.quotePath=false ls-files '*.json' '*.jsonc' '*.toml' '*.yaml' '*.yml' >"$tmp/configs"
        if "$py" -I - "$tmp/configs" >"$tmp/cfg" 2>&1 <<'PY'
    import json, re, sys, os
    try:
        import tomllib
    except ImportError:
        import tomli as tomllib
    import yaml

    def strip_jsonc(s):
        out, i, n, in_str = [], 0, len(s), False
        while i < n:
            c = s[i]
            if in_str:
                out.append(c)
                if c == "\\" and i + 1 < n:
                    out.append(s[i + 1]); i += 2; continue
                if c == '"':
                    in_str = False
                i += 1; continue
            if c == '"':
                in_str = True; out.append(c); i += 1; continue
            if s.startswith("//", i):
                j = s.find("\n", i); i = n if j < 0 else j; out.append(" "); continue
            if s.startswith("/*", i):
                j = s.find("*/", i + 2)
                if j < 0:
                    raise ValueError("unterminated /* comment")
                i = j + 2; out.append(" "); continue
            out.append(c); i += 1
        return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

    def parse(path):
        if path.endswith(".json"):
            json.load(open(path, encoding="utf-8"))
        elif path.endswith(".jsonc"):
            json.loads(strip_jsonc(open(path, encoding="utf-8").read()))
        elif path.endswith(".toml"):
            tomllib.load(open(path, "rb"))
        else:
            list(yaml.safe_load_all(open(path, encoding="utf-8")))

    paths = [p for p in open(sys.argv[1]).read().splitlines() if p and os.path.isfile(p)]
    errors = []
    for p in paths:
        try:
            parse(p)
        except Exception as e:
            errors.append("%s: %s: %s" % (p, type(e).__name__, str(e).splitlines()[0] if str(e) else ""))
    for e in errors:
        print(e)
    print("%d files parsed, %d invalid" % (len(paths), len(errors)))
    sys.exit(1 if errors else 0)
    PY
        then ok "config parse ($(tail -n 1 "$tmp/cfg"))"
        else bad "config-parse"; sed 's/^/        /' "$tmp/cfg"; fi
        if [ -f gitconfig ]; then
            git config --file gitconfig --list >/dev/null 2>"$tmp/err" && ok "gitconfig syntax" \
                || { bad "gitconfig"; sed 's/^/        /' "$tmp/err"; }
        fi
    fi
    # 5. skills lint, the same call CI makes (required; the script finds its own interpreter unless we pin ours)
    if env ${py:+PYTHON="$py"} scripts/lint-skills.sh skills/ >"$tmp/skills" 2>&1; then ok "skills lint ($(tail -n 1 "$tmp/skills"))"
    else bad "skills-lint"; sed 's/^/        /' "$tmp/skills"; fi
    tally lint

# contract: render in a temp HOME (always), then compare the really installed targets
contract:
    #!/usr/bin/env bash
    {{lib}}
    echo "==> contract"
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-contract.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT HUP INT TERM
    # 1. self-test: render into every identity of a throwaway HOME, then --check must be clean
    h="$tmp/home"
    mkdir -p "$h/.claude" "$h/.claude-p" "$h/.claude-mic" "$h/.codex" "$h/.config/opencode" "$h/.gemini/config" "$h/.copilot"
    if env HOME="$h" COPILOT_HOME="$h/.copilot" scripts/render-contract.sh >"$tmp/render" 2>&1 \
        && env HOME="$h" COPILOT_HOME="$h/.copilot" scripts/render-contract.sh --check >"$tmp/selfcheck" 2>&1; then
        ok "contract renders from current sources ($(tail -n 1 "$tmp/selfcheck"))"
    else
        bad "contract-render"; cat "$tmp/render" "$tmp/selfcheck" 2>/dev/null | sed 's/^/        /'
    fi
    # 2. installed targets (read-only; never repairs). render-contract.sh bakes the absolute source path into every header, so a
    #    target rendered from another checkout (the live clone seen from a worktree) always reads stale. Compare body and mode
    #    with the temp render: a header-only difference is a SKIP (known limit), body or mode drift is a FAIL. A checkout
    #    without the private overlay tolerates exactly one tail: the MIC addendum an overlay machine appended.
    rc=0; scripts/render-contract.sh --check >"$tmp/real" 2>&1 || rc=$?
    summary=$(tail -n 1 "$tmp/real")
    body() { awk 'f { print } /^-->$/ { f = 1 }' "$1"; }
    same_body() { # same_body INSTALLED RENDERED
        body "$1" >"$tmp/ib"; body "$2" >"$tmp/rb"
        cmp -s "$tmp/ib" "$tmp/rb" && return 0
        [ ! -f dotfiles-mic/AGENTS-MIC.md ] || return 1
        n=$(wc -c <"$tmp/rb" | tr -d ' ')
        head -c "$n" "$tmp/ib" | cmp -s - "$tmp/rb" || return 1
        case $(tail -c +"$((n + 1))" "$tmp/ib" | head -n 4 | tr '\n' '~') in '~---~~<!-- MIC addendum'*) return 0 ;; esac
        return 1
    }
    ch=${COPILOT_HOME:-$HOME/.copilot}
    counterpart() {
        case "$1" in
            "$ch"/*) echo "$h/.copilot/${1#"$ch"/}" ;;
            "$HOME"/*) echo "$h/${1#"$HOME"/}" ;;
        esac
    }
    if [ "$rc" -eq 0 ]; then
        case "$summary" in
            'contract: 0 up to date,'*) skip "installed-contract" "optional: no installed harness identity found; nothing to compare" ;;
            *) ok "installed contract ($summary)" ;;
        esac
    elif [ "$rc" -eq 1 ]; then
        sed -n 's/^stale //p' "$tmp/real" >"$tmp/stale"
        : >"$tmp/real_stale"; : >"$tmp/hdr_only"
        while IFS= read -r t; do
            c=$(counterpart "$t")
            if [ -n "$c" ] && [ -f "$t" ] && [ ! -L "$t" ] && [ -n "$(find "$t" -perm 644 -print)" ] && [ -f "$c" ] \
                && same_body "$t" "$c"; then printf '%s\n' "$t" >>"$tmp/hdr_only"
            else printf '%s\n' "$t" >>"$tmp/real_stale"; fi
        done <"$tmp/stale"
        if [ -s "$tmp/real_stale" ]; then
            bad "installed-contract" "stale; this recipe never repairs, run ./install"
            sed 's/^/        stale /' "$tmp/real_stale"
            [ ! -s "$tmp/hdr_only" ] || printf '        (%s more target(s) differ only in the header source path)\n' "$(wc -l <"$tmp/hdr_only" | tr -d ' ')"
        elif [ -s "$tmp/hdr_only" ]; then
            src=$(sed -n 's/^Source 1: //p' "$(head -n 1 "$tmp/hdr_only")" | head -n 1)
            skip "installed-contract" "known limit: $(wc -l <"$tmp/hdr_only" | tr -d ' ') installed target(s) were rendered from $src, so only the header path (and the MIC addendum, if this checkout has no overlay) differs; body and mode match. Run ./install here to re-render"
        else
            bad "installed-contract" "render-contract.sh --check exit 1 without a stale target"; sed 's/^/        /' "$tmp/real"
        fi
    else
        bad "installed-contract" "render-contract.sh exit $rc"; sed 's/^/        /' "$tmp/real"
    fi
    tally contract

# run tests/test-*.sh and scripts/*-test.sh serially; submodule-gated tests SKIP when the submodule is absent
test:
    #!/usr/bin/env bash
    {{lib}}
    echo "==> test"
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT HUP INT TERM
    if ! py=$("{{just_executable()}}" --justfile "{{justfile()}}" _python 2>"$tmp/pyerr"); then
        bad "python" "no usable interpreter; several tests parse YAML"; sed 's/^/        /' "$tmp/pyerr"
        tally test; exit
    fi
    # the tests call jq directly; fail once, clearly, instead of a dozen opaque "jq: not found" lines
    if ! command -v jq >/dev/null 2>&1; then
        bad "jq" "required by the tests but not installed (brew install jq | sudo apt install jq)"
        tally test; exit
    fi
    # tests that call bare python3 get the same interpreter the lint uses
    mkdir "$tmp/pybin"
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$py" >"$tmp/pybin/python3"; chmod +x "$tmp/pybin/python3"
    export PYTHON="$py" PATH="$tmp/pybin:$PATH"
    # prerequisite marker | what is missing | how to enable (a test absent here runs unconditionally)
    needs() {
        case "$1" in
            tests/test-install-blocks.sh) echo "dotbot/dotbot/util/common.py|the dotbot submodule|git submodule update --init dotbot" ;;
            tests/test-render-contract.sh) echo "dotfiles-mic/AGENTS-MIC.md|the private overlay dotfiles-mic|git submodule update --init dotfiles-mic" ;;
            scripts/eval-skills-test.sh) echo "dotfiles-mic/skills|the private overlay dotfiles-mic|git submodule update --init dotfiles-mic" ;;
        esac
    }
    n=0
    for t in tests/test-*.sh scripts/*-test.sh; do
        [ -f "$t" ] || continue
        n=$((n + 1))
        req=$(needs "$t")
        if [ -n "$req" ]; then
            marker=${req%%|*}; rest=${req#*|}
            if [ ! -e "$marker" ]; then skip "$t" "optional: needs ${rest%%|*}; enable: ${rest#*|}"; continue; fi
        fi
        case $(LC_ALL=C head -n 1 "$t") in '#!/bin/sh'*) run=sh ;; *) run=bash ;; esac
        SECONDS=0; rc=0
        "$run" "$t" >"$tmp/log" 2>&1 || rc=$?
        if [ "$rc" -eq 0 ]; then ok "$t (${SECONDS}s)"
        else bad "$t" "exit $rc"; sed 's/^/        /' "$tmp/log"; fi
    done
    if [ "$n" -eq 0 ]; then bad "tests" "no test files found (tests/test-*.sh, scripts/*-test.sh)"; fi
    tally test

# installed harness versions: runs only `<tool> --version`; informational, always exit 0
versions:
    #!/usr/bin/env bash
    set -u
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-versions.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT HUP INT TERM
    limit=${VERSIONS_TIMEOUT:-10}
    case "$limit" in ''|*[!0-9]*) limit=10 ;; esac
    pline=1
    # job control gives every background probe its own process group, so a stuck probe and its children die together
    set -m
    # probe NAME CMD...: output line $pline of CMD. After $limit seconds the probe gets TERM, 2 more seconds, then KILL
    # (stock macOS has no timeout(1)). The whole process group is supervised, not just the leader.
    probe() {
        local name=$1 path pid waited rc
        shift
        path=$(command -v "$1") || { printf '  SKIP  %-9s not installed\n' "$name"; return 0; }
        ( CI=1 NO_COLOR=1 exec "$@" ) </dev/null >"$tmp/out" 2>&1 &
        pid=$!
        waited=0
        while kill -0 "$pid" 2>/dev/null; do
            if [ "$waited" -ge $((limit * 10)) ]; then
                kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
                waited=0
                while kill -0 -- "-$pid" 2>/dev/null && [ "$waited" -lt 20 ]; do sleep 0.1; waited=$((waited + 1)); done
                # KILL the group even when the leader is gone: a child may have ignored TERM and outlived it
                kill -KILL -- "-$pid" 2>/dev/null || true
                kill -KILL "$pid" 2>/dev/null || true
                break
            fi
            sleep 0.1; waited=$((waited + 1))
        done
        rc=0; wait "$pid" 2>/dev/null || rc=$?
        if [ "$rc" -ge 128 ]; then printf '  ??    %-9s no answer within %ss (probe killed)  %s\n' "$name" "$limit" "$path"
        elif [ "$rc" -ne 0 ]; then printf '  ??    %-9s exit %s  %s\n' "$name" "$rc" "$path"
        else printf '  ok    %-9s %s  (%s)\n' "$name" "$(sed -n "${pline}p" "$tmp/out")" "$path"; fi
    }
    # a copilot on PATH that resolves to a VS Code copilot-shim is not the real CLI: never execute it. Same test as
    # harness-update.sh (leaf symlinks followed, parent directory canonicalized with pwd -P). Unresolvable counts as a shim.
    copilot_is_shim() {
        local t=$1 seen=0 l d
        while [ -L "$t" ]; do
            seen=$((seen + 1)); [ "$seen" -le 32 ] || return 0
            l=$(readlink "$t") || return 0
            case "$l" in /*) t=$l ;; *) t=$(dirname "$t")/$l ;; esac
        done
        d=$(CDPATH='' cd -- "$(dirname "$t")" 2>/dev/null && pwd -P) || return 0
        case "$d/$(basename "$t")" in *copilot-shim*) return 0 ;; esac
        return 1
    }
    echo "==> versions (read-only; each tool runs only --version)"
    # 2>/dev/null: job control makes bash print harmless "setpgid" race warnings when it forks a probe
    for tool in claude codex agy grok opencode ae; do probe "$tool" "$tool" --version 2>/dev/null; done
    if ! cp=$(command -v copilot); then printf '  SKIP  %-9s not installed\n' copilot
    elif copilot_is_shim "$cp"; then printf '  SKIP  %-9s only the VS Code shim is installed (not executed)  %s\n' copilot "$cp"
    else probe copilot copilot --version 2>/dev/null; fi
    if mp=$(command -v muse); then printf '  SKIP  %-9s not probed (self-updating launcher)  %s\n' muse "$mp"
    else printf '  SKIP  %-9s not installed\n' muse; fi
    echo "==> toolchain"
    printf '  ok    %-9s %s  (%s)\n' bash "${BASH_VERSION}" "$BASH"
    for tool in just git jq uv python3 fish; do probe "$tool" "$tool" --version 2>/dev/null; done
    pline=2; probe shellcheck shellcheck --version 2>/dev/null

# explicit and networked: harness versions installed vs latest (scripts/harness-update.sh --check; writes only its log under ~/.local/state)
outdated *args:
    scripts/harness-update.sh --check "$@"

# explicit and networked: update the AI harnesses; arguments go to scripts/harness-update.sh (--only TOOL, --check, --include-ae)
update *args:
    scripts/harness-update.sh "$@"

# explicit and networked, macOS only: install what macos/Brewfile lists
brew:
    #!/usr/bin/env bash
    if [ "$(uname -s)" != Darwin ]; then echo "  SKIP  brew: macOS only (this is $(uname -s))"; exit 0; fi
    command -v brew >/dev/null 2>&1 || { echo "  FAIL  brew not found on PATH" >&2; exit 1; }
    brew bundle --file macos/Brewfile

# explicit: link the dotfiles (./install; fetches the dotbot submodule); arguments go to ./install
install *args:
    ./install "$@"

# private: print the python interpreter that has PyYAML and a TOML parser, else explain and fail
_python:
    #!/usr/bin/env bash
    probe='import yaml; import importlib.util as u, sys; sys.exit(0 if (u.find_spec("tomllib") or u.find_spec("tomli")) else 1)'
    usable() { command -v "$1" >/dev/null 2>&1 && "$1" -I -c "$probe" >/dev/null 2>&1; }
    if [ -n "${PYTHON:-}" ]; then
        if usable "$PYTHON"; then command -v "$PYTHON"; exit 0; fi
        echo "PYTHON=$PYTHON is not usable (needs PyYAML and tomllib or tomli); {{py_hint}}" >&2
        exit 1
    fi
    for c in python3 /opt/homebrew/bin/python3 /usr/bin/python3; do
        # on macOS /usr/bin/python3 is a stub that opens an installer dialog unless the command line tools exist
        if [ "$c" = /usr/bin/python3 ] && [ "$(uname -s)" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then continue; fi
        if usable "$c"; then command -v "$c"; exit 0; fi
    done
    echo "no python with PyYAML and tomllib/tomli found; {{py_hint}}" >&2
    exit 1
