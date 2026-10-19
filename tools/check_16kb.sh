#!/usr/bin/env bash
# Verifies 16 KB page-size compatibility of an Android build (PLAN §3.18).
#
#   tools/check_16kb.sh build/android/ionfall.aab
#
# Runs both required checks:
#   1. ELF alignment: every LOAD segment of every native library is aligned
#      to >= 16 KB (0x4000).
#   2. ZIP alignment: the device APKs generated from the AAB pass
#      `zipalign -c -P 16 -v 4`.
# The runtime check (running on a 16 KB device or emulator) is separate.
set -euo pipefail

AAB="${1:?usage: check_16kb.sh <file.aab>}"
SDK="${ANDROID_HOME:-$HOME/Android/Sdk}"
BUILD_TOOLS="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
NDK="$(ls -d "$SDK"/ndk/* | sort -V | tail -1)"
READELF="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
BUNDLETOOL="${BUNDLETOOL:-$HOME/.local/share/ionfall-toolchain/bundletool.jar}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail=0

echo "== 1. ELF LOAD segment alignment"
unzip -q -o "$AAB" '*/lib/*.so' -d "$WORK/aab" || { echo "no native libraries found"; exit 1; }
while IFS= read -r so; do
  bad=""
  for align in $("$READELF" -lW "$so" | awk '$1=="LOAD" { print $NF }'); do
    (( align < 16384 )) && bad="$bad $align"
  done
  if [[ -n "$bad" ]]; then
    echo "FAIL ${so#"$WORK"/aab/}: LOAD alignment $bad"
    fail=1
  else
    echo "ok   ${so#"$WORK"/aab/}"
  fi
done < <(find "$WORK/aab" -name '*.so')

echo "== 2. ZIP alignment of generated APKs"
java -jar "$BUNDLETOOL" build-apks --bundle="$AAB" --output="$WORK/out.apks" --mode=universal >/dev/null
unzip -q -o "$WORK/out.apks" -d "$WORK/apks"
for apk in "$WORK"/apks/*.apk; do
  if "$BUILD_TOOLS/zipalign" -c -P 16 -v 4 "$apk" >/dev/null; then
    echo "ok   $(basename "$apk")"
  else
    echo "FAIL $(basename "$apk")"
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo "16 KB check FAILED"
  exit 1
fi
echo "16 KB checks passed (the runtime check on a 16 KB environment is separate)"
