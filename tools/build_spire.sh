#!/usr/bin/env bash
# Rebuilds a kit map's presentation and bakes its lightmap (needs a display
# and GPU for the bake). Run after changing its layout:
#   tools/build_spire.sh           # Halcyon Spire (maps/spire/spire_layout.gd)
#   tools/build_spire.sh foundry   # Vesper Foundry (maps/foundry/foundry_layout.gd)
set -euo pipefail
cd "$(dirname "$0")/.."
map="${1:-spire}"
godot --headless --import >/dev/null 2>&1 || true
godot --headless -s tools/build_spire.gd -- "$map"
godot --headless --import >/dev/null 2>&1 || true
tools/bake_lightmaps.sh "res://maps/$map/presentation.tscn"
