if status is-interactive
    # SSH agent - cache passphrase for 24h (86400 seconds)
    if not set -q SSH_AUTH_SOCK
        set -l agent_file $HOME/.ssh/ssh-agent.fish
        if test -f $agent_file
            source $agent_file >/dev/null
        end
        if not ssh-add -l >/dev/null 2>&1
            eval (ssh-agent -c) >/dev/null
            set -e SSH_AGENT_LAUNCHER
            echo "set -gx SSH_AUTH_SOCK $SSH_AUTH_SOCK" >$agent_file
            echo "set -gx SSH_AGENT_PID $SSH_AGENT_PID" >>$agent_file
            ssh-add -t 86400 ~/.ssh/id_ed25519
        end
    end
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

# Go
fish_add_path /usr/local/go/bin ~/go/bin

# opencode
fish_add_path /home/ckriech/.opencode/bin
