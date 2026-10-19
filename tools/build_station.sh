#!/usr/bin/env bash
# Rebuilds Meridian Station's presentation and bakes its lightmap (needs a
# display and GPU for the bake). Run after changing maps/station/station_layout.gd.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless -s tools/gen_textures.gd
godot --headless --import >/dev/null 2>&1 || true
godot --headless -s tools/build_map.gd
godot --headless --import >/dev/null 2>&1 || true
tools/bake_lightmaps.sh res://maps/station/presentation.tscn
