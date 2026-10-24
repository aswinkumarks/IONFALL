#!/usr/bin/env bash
# Exports the desktop clients in release mode and zips
# them into build/release/ (CI does the same for v* tags). Builds include
# online play when eos_credentials.cfg is present.
#
#   tools/package_release.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -f eos_credentials.cfg ]] || echo "warning: no eos_credentials.cfg: clients are LAN-only" >&2
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
OUT="build/release"
rm -rf "$OUT" && mkdir -p "$OUT"
export_one() {  # preset platform-id file
  local dir="$OUT/stage/$2"
  mkdir -p "$dir"
  python3 tools/write_build_info.py --platform "$2" --arch x86_64 --config release >/dev/null
  godot --headless --export-release "$1" "$dir/$3" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | { grep -E "^ERROR" || true; }
  test -f "$dir/$3"
}
export_one "Linux" linux ionfall.x86_64
export_one "Windows" windows IONFALL.exe
for p in linux windows; do
  (cd "$OUT/stage/$p" && zip -qr "../../ionfall-$VERSION-$p.zip" .)
done
rm -rf "$OUT/stage"
(cd "$OUT" && sha256sum ./*.zip > SHA256SUMS)
ls -lh "$OUT"
