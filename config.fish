if status is-interactive
    # Commands to run in interactive sessions can go here
end

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
#alias gg='source clicp_fish.sh'

# simulate bash export
function export
    for var in $argv
        eval set -gx (string split -m 1 "=" -- $var)
    end
end

set -U fish_function_path $fish_function_path ~/.config/fish/functions/mic

uv generate-shell-completion fish | source
# fnm
set FNM_PATH $HOME/.local/share/fnm
if test -d $FNM_PATH
  set -gx PATH $FNM_PATH $PATH
  fnm env --use-on-cd | source
end
