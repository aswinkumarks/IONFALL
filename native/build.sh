#!/usr/bin/env bash
# Builds the IONFALL native extension. Usage: native/build.sh [linux] [windows]
# (default: linux). Windows is cross-compiled with mingw-w64 (posix threads).
#
# Only release libraries are built; the .gdextension lists them without a
# debug/release tag, so the editor, debug and release exports all load them.
#
# The extension is opt-in: nothing in the repo loads it until this script
# writes native/bin/ionfall_native.gdextension, listing the platforms built.
# Without it the game runs the GDScript code (always the case on the web, and
# on Android until it has a build, PLAN §3.17 browser rule).
set -euo pipefail

cd "$(dirname "$0")"
PLATFORMS=("${@:-linux}")
# godot-cpp 4.5 bindings; GDExtension is forward compatible, so they load in
# the pinned Godot 4.7.2 (docs/toolchain.md).
GODOT_CPP_REF="godot-4.5-stable"
GODOT_CPP_COMMIT="e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77"

if [ ! -d godot-cpp ]; then
	git clone --quiet --depth 1 --branch "$GODOT_CPP_REF" https://github.com/godotengine/godot-cpp godot-cpp
fi
if [ "$(git -C godot-cpp rev-parse HEAD)" != "$GODOT_CPP_COMMIT" ]; then
	echo "native/godot-cpp isn't at the pinned $GODOT_CPP_COMMIT; delete it and re-run" >&2
	exit 1
fi
# Keep Godot's importer out of godot-cpp (it ships test projects).
touch godot-cpp/.gdignore

LIBRARIES=""
for p in "${PLATFORMS[@]}"; do
	case "$p" in
		linux)
			scons platform=linux target=template_release -j"$(nproc 2>/dev/null || echo 4)"
			LIBRARIES+='linux.x86_64 = "res://native/bin/libionfall_native.linux.template_release.x86_64.so"'$'\n'
			;;
		windows)
			scons platform=windows use_mingw=yes target=template_release -j"$(nproc 2>/dev/null || echo 4)"
			LIBRARIES+='windows.x86_64 = "res://native/bin/libionfall_native.windows.template_release.x86_64.dll"'$'\n'
			;;
		*)
			echo "unknown platform '$p' (linux, windows)" >&2
			exit 1
			;;
	esac
done

cat > bin/ionfall_native.gdextension <<EOF
[configuration]

entry_symbol = "ionfall_native_init"
compatibility_minimum = "4.5"

[libraries]

$LIBRARIES
EOF
echo "Built native/bin for ${PLATFORMS[*]}. Run 'godot --headless --import' once so Godot registers it."
