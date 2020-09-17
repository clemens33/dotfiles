#!/bin/bash

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# vim
ln -s ${BASEDIR}/vimrc ~/.vimrc

# tmux
ln -s ${BASEDIR}/tmux.conf ~/.tmux.conf

# git
ln -s ${BASEDIR}/gitconfig ~/.gitconfig
#cat ${BASEDIR}/gitconfig >> ~/.gitconfig

# zsh
#ln -s ${BASEDIR}/zshrc ~/.zshrc

# git
#ln -s ${BASEDIR}/gitconfig ~/.gitconfig
