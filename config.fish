# Disable greeting message
set -g fish_greeting

# Homebrew (macOS, Apple Silicon) — early, so brew-installed tools resolve
# before anything below. No-op on Linux/WSL where the path doesn't exist.
# Explicit `fish` arg: shellenv's auto-detection can emit POSIX syntax.
if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv fish | source
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
# org-specific k8s/argo helpers in ~/.config/fish/functions-mic when installed).
# Non-universal + contains-guard: avoids the duplicate-append-on-every-shell
# pollution that `set -U` caused here previously.
if test -d ~/.config/fish/functions-mic
    if not contains ~/.config/fish/functions-mic $fish_function_path
        set -a fish_function_path ~/.config/fish/functions-mic
    end
end

if command -q uv
    uv generate-shell-completion fish | source
end

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

# >>> grok installer >>>
fish_add_path -g $HOME/.grok/bin
# <<< grok installer <<<
