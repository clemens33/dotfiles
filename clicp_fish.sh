#!/usr/bin/env fish

# NOT WORKING YET

# heavily adapted from https://github.com/yongkangchen/cps

# this requires github cli and the github copilot cli extension
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
# https://docs.github.com/en/copilot/github-copilot-in-the-cli/using-github-copilot-in-the-cli

# exit if no command is given
if test -z "$argv[1]"
    set_color red
    echo "Error: no command given."
    exit 1
end

set keyword Suggestion:

set command (echo "" | gh copilot suggest -t shell $argv ^/dev/null | grep $keyword -A2 | grep -v $keyword | xargs)

if test -z "$command"
    set_color normal
    echo "Error from copilot"
    echo "Aborted."
    exit 1
end

set_color yellow
echo $command

# add the command to history
builtin history add "$command"

# Make the user confirm the command
set_color blue
echo -n "Run[Press Enter twice], Abort[any key]: "
read -l key_pressed
set_color normal

if test -n "$key_pressed" 
    echo (set_color red)"Aborted."
else
    # echo -n "Confirm[Press Enter again]: "
    read -l key_pressed_confirm
        
    if test -n "$key_pressed_confirm"
        echo (set_color red)"Aborted."
    else
        set_color normal
        eval $command
    end
end
