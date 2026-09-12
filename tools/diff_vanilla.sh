#!/usr/bin/env bash
# Diff every overridden file against the current Steam copy. Run after a game patch
# to see what Paradox changed underneath the mod. Exit code 0 = only this mod's
# changes remain (i.e. the vanilla file did not change since the mod was built).
set -u
MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="$HOME/.local/share/Steam/steamapps/common/Crusader Kings III/game/gfx/FX"
cd "$MOD/gfx/FX" || exit 1
for f in $(find . -type f -name '*.shader' -o -type f -name '*.fxh' | sed 's|^\./||' | sort); do
	if [ ! -e "$GAME/$f" ]; then echo "== $f: new file (no vanilla counterpart)"; continue; fi
	echo "== $f"
	diff -u --strip-trailing-cr "$GAME/$f" "$f" | grep -c '^[-+][^-+]' | sed 's/^/changed lines: /'
done
echo
echo "Full diff of one file:  diff -u --strip-trailing-cr \"$GAME/<file>\" gfx/FX/<file>"
