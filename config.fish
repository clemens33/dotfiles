# Disable greeting message
set -g fish_greeting

# Claude Code: updates only via scripts/harness-update.sh (row #31);
# autoUpdatesChannel in settings keeps channel choice.
set -gx DISABLE_AUTOUPDATER 1

# Agent temp dir — inside the ae tmux server ONLY: agent test runs churn
# $TMPDIR heavily and Microsoft Defender scans it; ~/projects is Defender-
# excluded, so keep agent temp files there. Shells outside ae keep the
# macOS default TMPDIR. No cleanup daemon: pytest keeps 3 basetemps,
# cargo-mutants deletes its dir.
if set -q TMUX
    set -l _tmux_sock (string split -m 1 , -- $TMUX)[1]
    if test (basename $_tmux_sock) = ae
        set -l _agent_tmp $HOME/projects/.tmp
        test -d $_agent_tmp; or mkdir -p $_agent_tmp
        set -gx TMPDIR $_agent_tmp/
    end
end

# pytest-xdist: `-n auto` starts one worker per physical core (18 on the M-series
# Mac), which starves the other agent sessions on the machine. pytest-xdist reads
# PYTEST_XDIST_AUTO_NUM_WORKERS for `-n auto` and `-n logical`; cap it at two
# thirds of the PHYSICAL cores (floor, minimum 2, never above the core count),
# the same unit xdist's psutil lookup counts for `auto`, so the cap can only
# lower that default. Logical CPUs would be wrong on SMT hosts: 16 logical / 8
# physical would give 10 > 8.
# Darwin: hw.physicalcpu. Linux: unique core,socket pairs from lscpu, falling
# back to nproc (logical) where lscpu is missing or prints nothing. If no count
# can be read, nothing is set (fail-open).
# Override: export your own value before the shell starts, or pass `-n N`.
# CI does not read this file, so CI keeps all cores.
# No jobs-budget call here: it samples for 1 s and would slow every shell start.
if not set -q PYTEST_XDIST_AUTO_NUM_WORKERS
    set -l _ncpu
    switch (uname)
        case Darwin
            set _ncpu (sysctl -n hw.physicalcpu 2>/dev/null)
        case '*'
            # `command -q` guards: fish prints "Unknown command" to stderr for a
            # missing binary even with 2>/dev/null.
            command -q lscpu
            and set _ncpu (lscpu -p=core,socket 2>/dev/null | string match -v '#*' | sort -u | count)
            test "$_ncpu" -gt 0 2>/dev/null
            or begin
                command -q nproc; and set _ncpu (nproc 2>/dev/null)
            end
    end
    if string match -qr '^[1-9][0-9]*$' -- "$_ncpu"
        set -gx PYTEST_XDIST_AUTO_NUM_WORKERS (math "min($_ncpu, max(2, floor($_ncpu * 2 / 3)))")
    end
end

# Homebrew (macOS, Apple Silicon) — early, so brew-installed tools resolve
# before anything below. No-op on Linux/WSL where the path doesn't exist.
# Static copy of `brew shellenv fish` for the /opt/homebrew prefix. The output
# is constant, and the fork cost about 12 ms of CPU per shell. A test compares
# this block with the live output (tests/test-fish-env-drift.sh), so a Homebrew
# change to shellenv shows up in `just test`.
if test -x /opt/homebrew/bin/brew
    set --global --export HOMEBREW_PREFIX "/opt/homebrew"
    set --global --export HOMEBREW_CELLAR "/opt/homebrew/Cellar"
    set --global --export HOMEBREW_REPOSITORY "/opt/homebrew"
    fish_add_path --global --move --path "/opt/homebrew/bin" "/opt/homebrew/sbin"
    if test -n "$MANPATH"; set --global --export MANPATH (string replace --regex '^:*(.*?):*$' ':$1' -- "$MANPATH"); end
    if not set --query INFOPATH; set INFOPATH ''; end; set --global --export INFOPATH "/opt/homebrew/share/info" $INFOPATH
    # keg-only libpq: psql etc. are not linked into the prefix
    fish_add_path -g /opt/homebrew/opt/libpq/bin
end

# mise — runtime manager (node/java/…; replaces fnm + sdkman on macOS).
# Activated before PATH tweaks below so shims resolve.
if command -q mise
    mise activate fish | source
end

# -g (global) everywhere: config-managed paths must NOT leak into universal
# fish_user_paths — that recreates the stale-state problem this repo already
# fought once. -p prepends: installers expect ~/.local/bin to win.
fish_add_path -g -p ~/.local/bin ~/bin

# cargo and cargo-nextest size themselves to ALL cores, so one lone run takes the
# last core the operating system and the endpoint-security scanner need. Default
# both to `jobs-budget --max`, the CPU count minus a small reserve (18 cores -> 16),
# only where unset. --max prints at once with no 1 s sample, so shell start stays
# fast. The cap is static: changing JOBS_BUDGET_RESERVE later does not rewrite a
# value that is already exported, and an exported value is kept by design.
# Override: export your own value before the shell starts, or pass `-j N` /
# `--test-threads N`; JOBS_BUDGET_RESERVE=<n> moves the cap for new shells where
# the worker variable is unset.
# Fail-open: no jobs-budget or an unexpected answer sets nothing.
# Placed after the PATH line above, which puts jobs-budget (~/.local/bin) on PATH.
if command -q jobs-budget
    and not begin
        set -q CARGO_BUILD_JOBS; and set -q NEXTEST_TEST_THREADS
    end
    set -l _cap (jobs-budget --max 2>/dev/null)
    if string match -qr '^[1-9][0-9]*$' -- "$_cap"
        set -q CARGO_BUILD_JOBS; or set -gx CARGO_BUILD_JOBS $_cap
        set -q NEXTEST_TEST_THREADS; or set -gx NEXTEST_TEST_THREADS $_cap
    end
end

# WSL/Windows glue — only inside WSL
if test -d /mnt/c
    alias subl='"/mnt/c/Program Files/Sublime Text/subl.exe"'
    alias expl='"explorer.exe"'
    alias naut='/usr/bin/nautilus'
end

# github cli copilot - fish does not support '?'
alias g='gh copilot suggest -t shell'
alias ghg='gh copilot suggest -t gh'
alias gitg='gh copilot suggest -t git'

# simulate bash export
function export
    for var in $argv
        eval set -gx (string split -m 1 "=" -- $var)
    end
end

# Load private overlay fish functions when present (dotfiles-mic provides
# remaining MIC functions in ~/.config/fish/functions-mic when installed).
# Non-universal + contains-guard: avoids the duplicate-append-on-every-shell
# pollution that `set -U` caused here previously.
if test -d ~/.config/fish/functions-mic
    if not contains ~/.config/fish/functions-mic $fish_function_path
        set -a fish_function_path ~/.config/fish/functions-mic
    end
end

# uv completion: fish/completions/uv.fish (generated; `just uv-completion`
# refreshes it after a uv upgrade). Fish loads it on the first `uv <Tab>`, so no
# `uv generate-shell-completion | source` runs at shell start.

# fnm (Linux node version manager; mise replaces it on macOS)
set FNM_PATH $HOME/.local/share/fnm
if test -d $FNM_PATH
  set -gx PATH $FNM_PATH $PATH
  fnm env --use-on-cd | source
end

# Go (apt/manual install lives in /usr/local/go on Linux; brew handles macOS.
# ~/go/bin is the `go install` target on both.)
fish_add_path -g /usr/local/go/bin ~/go/bin

# opencode
fish_add_path -g ~/.opencode/bin

# Rust — rustup-managed (installed with --no-modify-path; this line replaces
# the env.fish sourcing). Do NOT brew-install rust: it pins a standalone
# compiler that ignores rust-toolchain.toml. See macos/Brewfile §4.
fish_add_path -g ~/.cargo/bin

# sccache — only where installed (apt on Linux, brew on macOS). Env var, not
# cargo-config `rustc-wrapper`: that is a hard requirement on every machine
# sharing the config. Agents launched via `bash -lc` inherit it.
if command -q sccache
    set -gx RUSTC_WRAPPER sccache
end

# >>> grok installer >>>
fish_add_path -g $HOME/.grok/bin
# <<< grok installer <<<

# Command shims — a dir a private overlay may populate with wrappers that
# inject per-launch env and exec the real binary. Must resolve BEFORE
# ~/.local/bin (where the real binaries live), so it goes last here and wins.
# No-op when the dir doesn't exist.
#
# Explicit filter-and-prepend, NOT fish_add_path: fish_add_path -g manages
# fish_user_paths and treats a dir already present in an inherited PATH as
# done — neither -p nor --move reorders it (measured on fish 4.8.1). This form
# guarantees first position and leaves exactly one entry.
#
# Bash login shells (`bash -lc`, how ae launches agents) never read this file,
# but they inherit this PATH and that is enough — measured, not assumed:
# Ubuntu /etc/profile never assigns PATH (noble base-files), and macOS
# path_helper reorders system paths ahead but PRESERVES the relative order of
# inherited entries, so the shim dir still resolves before ~/.local/bin where
# the real binaries live. No bash-side profile hook is needed. If the shim is
# ever bypassed the failure is fail-CLOSED: the real binary runs without the
# gateway keys, so the MCP simply does not authenticate — nothing leaks.
set -l _shims $HOME/.local/shims
if test -d $_shims
    set -gx PATH $_shims (string match -v -- $_shims $PATH)
end

# Docker: colima (VM) + brew docker CLI replaced OrbStack 2026-08-07.
# Nothing to source — the brew formulas are already on PATH and colima
# owns the docker context. `colima start` if the VM is ever down.


# Added by Antigravity CLI installer
# Linux only: on macOS /home is an autofs mount, so a PATH entry there makes
# automountd run od_user_homes on every PATH lookup. The original text stays
# in case the installer greps for it (unverified). agy lives in ~/.local/bin.
if test (uname) = Linux
    set -gx PATH "/home/ckriech/.local/bin" $PATH
end
