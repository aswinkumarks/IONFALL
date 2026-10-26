extends SceneTree
## Bakes MapMaterials' conversions (planar UVs instead of world triplanar,
## back faces culled on the closed kit materials) into the maps' saved
## meshes, in place. The map builders (build_map.gd, build_spire.gd) apply
## the same conversion as they save, so this is only needed for maps built
## before it (their lightmaps stay valid: geometry and UV2 are unchanged).
##
##   godot --headless -s tools/bake_map_materials.gd

const MAPS := ["station", "spire", "foundry"]


func _init() -> void:
	var changed := 0
	for map_id: String in MAPS:
		var scene: Node = (load("res://maps/%s/presentation.tscn" % map_id) as PackedScene).instantiate()
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh := mi.mesh as ArrayMesh
			if mesh == null or not mesh.resource_path.ends_with(".res"):
				continue
			var out := MapMaterials.converted(mesh, MapMaterials.transform_in(mi, scene))
			if out == mesh:
				continue
			var err := ResourceSaver.save(out, mesh.resource_path)
			print("%s: %s" % [mesh.resource_path, "converted" if err == OK else "ERROR %d" % err])
			changed += 1
		scene.free()
	print("%d meshes converted" % changed)
	quit()
