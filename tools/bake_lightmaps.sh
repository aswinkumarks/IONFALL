#!/usr/bin/env bash
# Bakes a scene's LightmapGI in the Godot editor (needs a display and GPU).
#   tools/bake_lightmaps.sh res://maps/lighting_test/lighting_test.tscn
# The plugin in addons/ionfall_tools does the work; outputs go to Git LFS.
set -euo pipefail
cd "$(dirname "$0")/.."
IONFALL_BAKE="${1:?scene path}" timeout 900 godot --editor --path . 2>&1 | grep -E "BAKE:|ERROR" || true
