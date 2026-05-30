# Disable greeting message
set -g fish_greeting

set -gx PATH $PATH ~/.local/bin
set -gx PATH $PATH ~/bin
set -gx PATH $PATH ~/.nvm/versions/node/v18.16.0/bin
set -gx PATH $PATH ~/.nvm/versions/node/v18.16.0/bin/npm

# relevant for opening folder/files within sublime directly from within wsl
alias subl='"/mnt/c/Program Files/Sublime Text/subl.exe"'
alias expl='"explorer.exe"'
alias naut='/usr/bin/nautilus'

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

uv generate-shell-completion fish | source
# fnm
set FNM_PATH $HOME/.local/share/fnm
if test -d $FNM_PATH
  set -gx PATH $FNM_PATH $PATH
  fnm env --use-on-cd | source
end

# Go
fish_add_path /usr/local/go/bin ~/go/bin

# opencode
fish_add_path /home/ckriech/.opencode/bin
