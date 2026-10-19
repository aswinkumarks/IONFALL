#!/usr/bin/env bash
# Rebuilds Halcyon Spire's presentation and bakes its lightmap (needs a
# display and GPU for the bake). Run after changing maps/spire/spire_layout.gd.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --import >/dev/null 2>&1 || true
godot --headless -s tools/build_spire.gd
godot --headless --import >/dev/null 2>&1 || true
tools/bake_lightmaps.sh res://maps/spire/presentation.tscn
