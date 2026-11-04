extends SceneTree
## Puts Station's saved meshes on the hull plating (MapDetail.station_panels)
## and the calmer hull and module colours tools/build_map.gd now builds with,
## without a rebuild: materials only, so the baked lightmap stays valid.
##
##   godot --headless -s tools/restyle_station_meshes.gd

const DIR := "res://maps/station/meshes/"
const PANEL_GRID := "res://art/textures/panel_grid.png"
const COLORS := {"hull": Color(0.6, 0.63, 0.68), "module": Color(0.66, 0.68, 0.72)}


func _init() -> void:
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".res"):
			continue
		var mesh: ArrayMesh = load(DIR + f)
		var changed := false
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as StandardMaterial3D
			if m == null or m.albedo_texture == null or m.albedo_texture.resource_path != PANEL_GRID:
				continue
			m = m.duplicate()
			MapDetail.station_panels(m)
			m.albedo_color = COLORS.get(f.get_basename(), m.albedo_color)
			mesh.surface_set_material(i, m)
			changed = true
		if changed:
			print("%s%s" % [DIR + f, "" if ResourceSaver.save(mesh, DIR + f) == OK else " ERROR"])
	quit()
