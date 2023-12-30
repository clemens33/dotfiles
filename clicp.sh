#!/bin/bash

# heavily adapated from https://github.com/yongkangchen/cps

# this requires github cli and the github copilot cli extension
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
# https://docs.github.com/en/copilot/github-copilot-in-the-cli/using-github-copilot-in-the-cli

# exit if no command is given
if [ -z "$1" ]; then
  echo -e -n "\033[0;31m" # set color to red
  echo "Error: no command given."
  exit 1
fi

keyword=Suggestion:

command="$(echo "" | gh copilot suggest -t shell "$@" 2>/dev/null | grep $keyword -A2 | grep -v $keyword | xargs)"

if [ -z "$command" ]; then
    #echo -e -n "\033[0;31m" # set color to red
    echo "Error from copilot"
    echo "Aborted."
    exit 1
fi

echo -e -n "\033[0;93m"
echo $command
#echo -e "\033[1m\033[33m$command\033[0m"

# add the command to history
history -s "$command"

# Make the user confirm the command
echo -e -n "\033[0;94m" # Set color to blue
read -s -n 1 -p "Run[Press Enter twice], Abort[any key]: " key_pressed
echo -e -n "\033[0m" # Reset color

if [[ $key_pressed ]]; then  
    echo -e "\033[0;31mAborted."
else
    read -s -n 1 key_pressed_confirm
        
    if [[ $key_pressed_confirm ]]; then
        echo -e "\033[0;31mAborted."
    else
        #echo -e "\033[0;92mRun..."
        #echo $command
        echo -e "\033[0m" # reset color
        eval "$command"
    fi
fi

