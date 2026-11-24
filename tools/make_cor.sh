#!/bin/bash
# Turn the Vivado bitstream into a MEGA65 core file (.cor) for the flash menu.
# Usage (inside the Vivado container):  ./tools/make_cor.sh [r3|r4|r5|r6]
# Builds the official mega65-tools bit2core (development branch: writes the CRC32
# checksum that current MEGA65 flash menus verify) on first use.
set -e
REV="${1:-r3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
B2C="$ROOT/tools/.bit2core-dev"
if [ ! -x "$B2C/bit2core" ]; then
   mkdir -p "$B2C"
   for f in src/tools/bit2core.c include/m65common.h include/dirtymock.h; do
      curl -sfL "https://raw.githubusercontent.com/MEGA65/mega65-tools/development/$f" -o "$B2C/$(basename $f)"
   done
   echo 'const char *version_string = "mega65-tools bit2core";' > "$B2C/version.c"
   gcc -O2 -o "$B2C/bit2core" "$B2C/bit2core.c" "$B2C/version.c"
fi
REVU=$(echo "$REV" | tr a-z A-Z)
BIT="$ROOT/CORE/CORE-$REVU.runs/impl_1/mega65_$REV.bit"
OUT="$ROOT/archie_$REV.cor"
VER="WIP $(git -C "$ROOT" rev-parse --short HEAD)"
"$B2C/bit2core" "mega65$REV" "$BIT" "Acorn Archimedes" "$VER" "$OUT"
echo
echo "Core file: $OUT"
