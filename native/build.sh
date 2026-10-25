#!/usr/bin/env bash
# Builds the IONFALL native extension for this machine (prototype: Linux and
# Windows desktop). Usage: native/build.sh [template_release|template_debug]
#
# The extension is opt-in: nothing in the repo loads it until this script
# writes native/bin/ionfall_native.gdextension. Without it the game runs the
# GDScript code (always the case on the web, PLAN §3.17 browser rule).
set -euo pipefail

cd "$(dirname "$0")"
TARGET="${1:-template_release}"
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

scons target="$TARGET" -j"$(nproc 2>/dev/null || echo 4)"

cat > bin/ionfall_native.gdextension <<'EOF'
[configuration]

entry_symbol = "ionfall_native_init"
compatibility_minimum = "4.5"

[libraries]

linux.debug.x86_64 = "res://native/bin/libionfall_native.linux.template_debug.x86_64.so"
linux.release.x86_64 = "res://native/bin/libionfall_native.linux.template_release.x86_64.so"
windows.debug.x86_64 = "res://native/bin/libionfall_native.windows.template_debug.x86_64.dll"
windows.release.x86_64 = "res://native/bin/libionfall_native.windows.template_release.x86_64.dll"
EOF
echo "Built native/bin for $TARGET. Run 'godot --headless --import' once so Godot registers it."
