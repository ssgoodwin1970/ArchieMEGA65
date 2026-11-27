#!/bin/zsh
# Run on the Mac (NOT inside the Docker container).
# Copies the latest archie_r3.cor into iCloud Documents/MEGA65/cores, named with
# the version it was built from, so either Mac (and the SD card) can pick it up.
# Usage:  ~/vivado-on-silicon-mac-main/archiemega65/tools/publish_cor.sh [r3]
REV="${1:-r3}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
COR="$HERE/archie_$REV.cor"
DEST="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/MEGA65/cores"
[ -d "$HOME/Documents/MEGA65" ] && DEST="$HOME/Documents/MEGA65/cores"
if [ ! -f "$COR" ]; then echo "No $COR - run ./tools/build.sh in the container first."; exit 1; fi
VER=$(git -C "$HERE" log --oneline -1 | cut -c1-7)
mkdir -p "$DEST"
cp "$COR" "$DEST/archie_${REV}_${VER}.cor"
cp "$COR" "$DEST/archie_${REV}_latest.cor"
echo "Copied to: $DEST/archie_${REV}_${VER}.cor (and archie_${REV}_latest.cor)"
