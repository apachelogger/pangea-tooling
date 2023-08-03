#!/bin/sh

set -ex

git submodule init
git submodule update --remote --init --recursive
git config --local include.path ../.gitconfig
git fetch --verbose
