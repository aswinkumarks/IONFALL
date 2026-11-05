#!/usr/bin/env bash
# Builds the signed release APK (upload key from outside the repo) and runs
# the 16 KB page-size checks. Doesn't install anything.
#
#   tools/android_release.sh        # → build/android/ionfall.apk
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYS="${IONFALL_KEYS:-$HOME/.local/share/ionfall-keys/upload-key.env}"
TOOLCHAIN="$HOME/.local/share/ionfall-toolchain"
export JAVA_HOME="${JAVA_HOME_17:-$TOOLCHAIN/jdk-17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"
APK="$ROOT/build/android/ionfall.apk"

set -a; source "$KEYS"; set +a
cd "$ROOT"
[[ -f eos_credentials.cfg ]] || echo "warning: no eos_credentials.cfg: this build has no online play" >&2
python3 tools/write_build_info.py --platform android --arch arm64 --config release
mkdir -p build/android
rm -f "$APK"
godot --headless --export-release "Android" "$APK" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | { grep -E "^ERROR" || true; }
test -f "$APK"
bash tools/check_16kb.sh "$APK"
APKSIGNER="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)/apksigner"
echo "Signed: $("$APKSIGNER" verify --print-certs "$APK" | grep -m1 'SHA-256')"
echo "Release APK: $APK ($(du -h "$APK" | cut -f1)), version $(python3 -c 'import json;d=json.load(open("build_info.json"));print(d["version"], "code", d["version_code"])')"
