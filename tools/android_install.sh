#!/usr/bin/env bash
# Builds the signed release AAB and installs it on a connected Android device
# (USB or wireless debugging). See docs/toolchain.md.
#
#   tools/android_install.sh            # export + install
#   tools/android_install.sh --no-export  # install the existing build/android/ionfall.aab
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYS="${IONFALL_KEYS:-$HOME/.local/share/ionfall-keys/upload-key.env}"
TOOLCHAIN="$HOME/.local/share/ionfall-toolchain"
export JAVA_HOME="${JAVA_HOME_17:-$TOOLCHAIN/jdk-17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$ANDROID_HOME/platform-tools:$JAVA_HOME/bin:$PATH"
BUNDLETOOL="${BUNDLETOOL:-$TOOLCHAIN/bundletool.jar}"
AAB="$ROOT/build/android/ionfall.aab"
APKS="$ROOT/build/android/ionfall.apks"

set -a; source "$KEYS"; set +a

cd "$ROOT"
if [[ "${1:-}" != "--no-export" ]]; then
  python3 tools/write_build_info.py --platform android --arch arm64 --config release
  mkdir -p build/android
  godot --headless --export-release "Android" "$AAB" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | { grep -E "^ERROR" || true; }
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

# Pass the keystore password through a private temp file, never the command line.
PASSFILE="$(mktemp)"
trap 'rm -f "$PASSFILE"' EXIT
chmod 600 "$PASSFILE"
printf '%s' "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" > "$PASSFILE"

rm -f "$APKS"
java -jar "$BUNDLETOOL" build-apks --bundle="$AAB" --output="$APKS" --connected-device \
  --device-id="$DEVICE" --adb="$(command -v adb)" \
  --ks="$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" --ks-key-alias="$GODOT_ANDROID_KEYSTORE_RELEASE_USER" \
  --ks-pass="file:$PASSFILE" --key-pass="file:$PASSFILE"
echo "Approve the install prompt on the phone if one appears."
java -jar "$BUNDLETOOL" install-apks --apks="$APKS" --device-id="$DEVICE" --adb="$(command -v adb)"
adb -s "$DEVICE" shell am start -n io.github.aswinkumarks.ionfall/com.godot.game.GodotAppLauncher >/dev/null
echo "Installed and launched."
