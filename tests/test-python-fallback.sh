#!/usr/bin/env bash
# Exercise the real just recipe and real uv with isolated interpreter discovery.
set -euo pipefail
repo=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
recipe=${JUSTFILE_UNDER_TEST:-$repo/justfile}
just_bin=$(command -v just) || { echo 'SKIP: just is not installed'; exit 0; }
uv_bin=$(command -v uv) || { echo 'SKIP: uv is not installed'; exit 0; }
uv_cache=$("$uv_bin" cache dir)
probe='import yaml; import importlib.util as u, sys; sys.exit(0 if (u.find_spec("tomllib") or u.find_spec("tomli")) else 1)'
# Absolute recipe candidates cannot be hidden by PATH. State this coverage limit.
for candidate in /opt/homebrew/bin/python3 /usr/bin/python3; do
    if [ "$candidate" = /usr/bin/python3 ] && [ "$(uname -s)" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then continue; fi
    if [ -x "$candidate" ] && "$candidate" -I -c "$probe" >/dev/null 2>&1; then
        echo "SKIP: absolute candidate $candidate already has PyYAML and TOML support"
        exit 0
    fi
done
tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-python-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
# Establish the cache prerequisite separately from the recipe under test.
if ! base=$("$uv_bin" python find --offline --no-python-downloads --managed-python '>=3.11' 2>/dev/null); then
    base=$("$uv_bin" python find --offline --no-python-downloads '>=3.11' 2>/dev/null) || { echo 'SKIP: no local Python >=3.11 for offline uv'; exit 0; }
fi
if ! "$uv_bin" venv --offline --no-python-downloads -q --python "$base" "$tmp/reference" >/dev/null 2>&1 \
    || ! "$uv_bin" pip install --offline -q --python "$tmp/reference/bin/python" pyyaml==6.0.3 >/dev/null 2>&1; then
    echo 'SKIP: uv cache does not contain pyyaml==6.0.3 for the local Python'
    exit 0
fi
"$tmp/reference/bin/python" -I -c "$probe"
mkdir -p "$tmp/bin" "$tmp/uvbin" "$tmp/cache" "$tmp/empty-uv"
# Supply only required shell utilities. No uv or usable PATH Python leaks in.
for utility in bash uname mkdir rm dirname mktemp; do
    ln -s "$(command -v "$utility")" "$tmp/bin/$utility"
done
if command -v xcode-select >/dev/null 2>&1; then ln -s "$(command -v xcode-select)" "$tmp/bin/xcode-select"; fi
printf '#!/bin/sh\nexit 1\n' >"$tmp/bin/python3"
chmod +x "$tmp/bin/python3"
ln -s "$uv_bin" "$tmp/uvbin/uv"
run_recipe() {
    env -u PYTHON PATH="$tmp/uvbin:$tmp/bin" XDG_CACHE_HOME="$tmp/cache" UV_CACHE_DIR="$uv_cache" UV_PYTHON_DOWNLOADS=never \
        "$just_bin" --justfile "$recipe" _python
}
selected=$(run_recipe 2>"$tmp/err") || { cat "$tmp/err" >&2; echo 'FAIL: offline cached uv fallback failed' >&2; exit 1; }
[ -x "$selected" ] || { echo 'FAIL: recipe did not return one executable path' >&2; exit 1; }
"$selected" -I -c "$probe"
case "$selected" in "$tmp/cache/"*) ;; *) echo 'FAIL: fallback interpreter is outside the private cache' >&2; exit 1 ;; esac
# A valid explicit override wins, even when a fallback environment exists.
override=$(env PYTHON="$tmp/reference/bin/python" PATH="$tmp/uvbin:$tmp/bin" XDG_CACHE_HOME="$tmp/cache" UV_CACHE_DIR="$uv_cache" \
    "$just_bin" --justfile "$recipe" _python)
[ "$override" = "$tmp/reference/bin/python" ] || { echo 'FAIL: usable PYTHON override lost precedence' >&2; exit 1; }
if env PYTHON="$tmp/bin/python3" PATH="$tmp/uvbin:$tmp/bin" XDG_CACHE_HOME="$tmp/cache" UV_CACHE_DIR="$uv_cache" \
    "$just_bin" --justfile "$recipe" _python >"$tmp/out" 2>"$tmp/err"; then
    echo 'FAIL: unusable explicit PYTHON override fell back' >&2; exit 1
fi
if env -u PYTHON PATH="$tmp/bin" XDG_CACHE_HOME="$tmp/no-uv-cache" \
    "$just_bin" --justfile "$recipe" _python >"$tmp/out" 2>"$tmp/err"; then
    echo 'FAIL: missing uv unexpectedly succeeded' >&2; exit 1
fi
grep -q 'uv run' "$tmp/err" || { echo 'FAIL: missing-uv error omitted uv hint' >&2; exit 1; }
if env -u PYTHON PATH="$tmp/uvbin:$tmp/bin" XDG_CACHE_HOME="$tmp/cold-cache" UV_CACHE_DIR="$tmp/empty-uv" UV_PYTHON_DOWNLOADS=never \
    "$just_bin" --justfile "$recipe" _python >"$tmp/out" 2>"$tmp/err"; then
    echo 'FAIL: empty offline cache unexpectedly succeeded' >&2; exit 1
fi
grep -q 'uv run' "$tmp/err" || { echo 'FAIL: empty-cache error omitted uv hint' >&2; exit 1; }
echo 'ok: offline uv fallback, override precedence, missing uv, and empty cache'
