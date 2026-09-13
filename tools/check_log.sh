#!/usr/bin/env bash
# After a game start: was the mod mounted, and did every shader compile?
# The engine logs nothing on a successful shader compile. A failure is logged as
# "Failed to compile shader" (Vulkan) or "Compile error:" + "Failed creating shader
# state" (DirectX 11), so "none" below is the pass signal.
set -u
LOGS="$HOME/.local/share/Steam/steamapps/compatdata/1158310/pfx/drive_c/users/steamuser/Documents/Paradox Interactive/Crusader Kings III/logs"
NAME="sharp_lowspec_terrain"

echo "== mount (debug.log)"
grep -h "Mounted Data: .*$NAME\|$NAME.mod|" "$LOGS/debug.log" 2>/dev/null || echo "NOT mounted - mod not enabled in the playset?"
echo "== enabled mods (debug.log)"
grep -h "|mod/.*\.mod|" "$LOGS/debug.log" 2>/dev/null | sed 's/^.*\]: //'
echo "== shader errors (error.log, game.log)"
if grep -h -A12 "Failed to compile shader\|Could not find shader file\|Compile error:\|Failed creating shader state" "$LOGS/error.log" "$LOGS/game.log" 2>/dev/null | head -80 | grep .; then
	exit 1
else
	echo "none"
fi
