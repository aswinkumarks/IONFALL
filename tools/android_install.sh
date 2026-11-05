#!/usr/bin/env bash
# Builds the signed release APK and installs it on a connected Android device
# (USB or wireless debugging). See docs/toolchain.md.
#
#   tools/android_install.sh            # export + install
#   tools/android_install.sh --no-export  # install the existing build/android/ionfall.apk
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
if [[ "${1:-}" != "--no-export" ]]; then
  python3 tools/write_build_info.py --platform android --arch arm64 --config release
  mkdir -p build/android
  godot --headless --export-release "Android" "$APK" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | { grep -E "^ERROR" || true; }
fi

find_device() {
  adb devices | awk 'NR>1 && $2=="device" && $1 !~ /^emulator/ {print $1; exit}'
}
# A freshly started adb server needs a few seconds to rediscover wireless devices.
DEVICE="${ANDROID_SERIAL:-}"
for _ in $(seq 1 10); do
  [[ -n "$DEVICE" ]] && break
  DEVICE="$(find_device)"
  [[ -z "$DEVICE" ]] && sleep 1
done
if [[ -z "$DEVICE" ]]; then
  echo "No device connected. Wireless debugging: adb connect <ip>:<port> (see docs/toolchain.md)" >&2
  exit 1
fi
echo "Installing on $DEVICE"

echo "Approve the install prompt on the phone if one appears."
adb -s "$DEVICE" install -r "$APK"
adb -s "$DEVICE" shell am start -n io.github.aswinkumarks.ionfall/com.godot.game.GodotAppLauncher >/dev/null
echo "Installed and launched."
