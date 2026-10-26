#!/usr/bin/env bash
# Builds the IONFALL native extension. Usage: native/build.sh [linux] [windows] [android]
# (default: linux). Windows is cross-compiled with mingw-w64 (posix threads);
# android builds arm64 and x86_64 (the emulator's) with the pinned NDK under
# $ANDROID_HOME (NDK r28+ aligns to 16 KB pages, PLAN §3.18).
#
# Only release libraries are built; the .gdextension lists them without a
# debug/release tag, so the editor, debug and release exports all load them.
#
# The extension is opt-in: nothing in the repo loads it until this script
# writes native/bin/ionfall_native.gdextension, listing every library in
# native/bin/. Without it the game runs the GDScript code (always the case on
# the web, PLAN §3.17 browser rule).
set -euo pipefail

cd "$(dirname "$0")"
PLATFORMS=("${@:-linux}")
# godot-cpp 4.5 bindings; GDExtension is forward compatible, so they load in
# the pinned Godot 4.7.2 (docs/toolchain.md).
GODOT_CPP_REF="godot-4.5-stable"
GODOT_CPP_COMMIT="e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77"
# The NDK of Godot 4.7.2's Android template (.github/workflows/ci.yml).
NDK_VERSION="29.0.14206865"
JOBS="$(nproc 2>/dev/null || echo 4)"

if [ ! -d godot-cpp ]; then
	git clone --quiet --depth 1 --branch "$GODOT_CPP_REF" https://github.com/godotengine/godot-cpp godot-cpp
fi
if [ "$(git -C godot-cpp rev-parse HEAD)" != "$GODOT_CPP_COMMIT" ]; then
	echo "native/godot-cpp isn't at the pinned $GODOT_CPP_COMMIT; delete it and re-run" >&2
	exit 1
fi
# Keep Godot's importer out of godot-cpp (it ships test projects).
touch godot-cpp/.gdignore

for p in "${PLATFORMS[@]}"; do
	case "$p" in
		linux)
			scons platform=linux target=template_release -j"$JOBS"
			;;
		windows)
			scons platform=windows use_mingw=yes target=template_release -j"$JOBS"
			;;
		android)
			for arch in arm64 x86_64; do
				ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}" \
					scons platform=android arch=$arch ndk_version="$NDK_VERSION" target=template_release -j"$JOBS"
			done
			;;
		*)
			echo "unknown platform '$p' (linux, windows, android)" >&2
			exit 1
			;;
	esac
done

# Every library built so far, so separate runs add up.
LIBRARIES=""
for lib in bin/libionfall_native.*.template_release.*.so bin/libionfall_native.*.template_release.*.dll; do
	[ -e "$lib" ] || continue
	f="$(basename "$lib")"
	rest="${f#libionfall_native.}"           # linux.template_release.x86_64.so
	os="${rest%%.*}"
	arch="${rest#*.template_release.}"; arch="${arch%.*}"
	LIBRARIES+="$os.$arch = \"res://native/bin/$f\""$'\n'
done

cat > bin/ionfall_native.gdextension <<EOF
[configuration]

entry_symbol = "ionfall_native_init"
compatibility_minimum = "4.5"

[libraries]

$LIBRARIES
EOF
echo "Built native/bin for ${PLATFORMS[*]}; the .gdextension lists:"; printf "%s" "$LIBRARIES"
echo " Run 'godot --headless --import' once so Godot registers it."
