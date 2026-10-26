extends SceneTree
## Saves each selectable character's third-person mesh (ReducedMesh: its
## first LOD as the base level, unused vertices dropped) next to the full
## one, as MeshyRig.reduced_mesh_path. Run again after
## tools/rig_meshy_fingers.gd rebuilds a character's mesh:
##
##   xvfb-run godot --rendering-driver vulkan -s tools/bake_reduced_characters.gd


func _init() -> void:
	for c: String in CharacterRig.SELECTABLE:
		var full: ArrayMesh = load(MeshyRig.finger_mesh_path(c))
		var reduced := ReducedMesh.build(full)
		if reduced == full:
			push_error("%s: no LODs to reduce to" % c)
			continue
		var err := ResourceSaver.save(reduced, MeshyRig.reduced_mesh_path(c))
		print("%s: %d -> %d triangles%s" % [MeshyRig.reduced_mesh_path(c), full.surface_get_array_index_len(0) / 3,
				reduced.surface_get_array_index_len(0) / 3, "" if err == OK else " ERROR %d" % err])
	quit()
