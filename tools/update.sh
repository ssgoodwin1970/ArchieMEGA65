#!/bin/bash
# Make this copy match GitHub exactly (discards Vivado's local project-file edits).
# Usage: ./tools/update.sh
set -e
cd "$(dirname "$0")/.."
git fetch origin
git reset --hard origin/master
git submodule update --init --recursive
echo
echo "Now at: $(git log --oneline -1)"
