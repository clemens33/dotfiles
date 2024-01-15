if status is-interactive
    # Commands to run in interactive sessions can go here
end

# relevant for opening folder/files within sublime directly from within wsl
alias subl='"/mnt/c/Program Files/Sublime Text/subl.exe"'
alias expl='"explorer.exe"'
alias naut='/usr/bin/nautilus'

# github cli copilot - fish does not support '?'
alias g='gh copilot suggest -t shell'
alias ghg='gh copilot suggest -t gh'
alias gitg='gh copilot suggest -t git'
#alias gg='source clicpf'

# simulate bash export
function export
    for var in $argv
        eval set -gx (string split -m 1 "=" -- $var)
    end
end