extends GutTest
## ReducedMesh and the character quality tiers (MeshyRig.TIERS): medium and
## low draw and skin their mesh's first and second LOD; first person and the
## character screen keep the full mesh.


func test_compact_keeps_only_used_vertices() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([0, 0, 0, 1, 1, 0, 0, 1, 2, 0, 0, 1, 3, 0, 0, 1])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 1, 2, 3])
	var levels: Array[PackedInt32Array] = [PackedInt32Array([3, 2, 1]), PackedInt32Array([1, 2, 3])]
	var r := ReducedMesh.compact(arrays, levels)
	var out: Array = r[0]
	assert_eq(out[Mesh.ARRAY_VERTEX], PackedVector3Array([Vector3(3, 0, 0), Vector3(2, 0, 0), Vector3(1, 0, 0)]), "vertex 0 dropped")
	assert_eq(out[Mesh.ARRAY_TANGENT], PackedFloat32Array([3, 0, 0, 1, 2, 0, 0, 1, 1, 0, 0, 1]), "strided arrays follow")
	assert_eq(out[Mesh.ARRAY_INDEX], PackedInt32Array([0, 1, 2]))
	assert_eq(r[1][1], PackedInt32Array([2, 1, 0]), "coarser levels remapped")


## The characters halve their triangles and drop over half their vertices.
func test_characters_reduce_to_their_first_lod() -> void:
	for c: String in CharacterRig.SELECTABLE:
		var mesh: ArrayMesh = load(MeshyRig.finger_mesh_path(c))
		var arrays := mesh.surface_get_arrays(0)
		var lods := ReducedMesh.lods_of(mesh, 0)
		assert_gt(lods.size(), 1, c)
		var levels: Array[PackedInt32Array] = []
		for l: Array in lods:
			levels.append(l[1])
		var r := ReducedMesh.compact(arrays, levels)
		var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var tris := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		assert_lt((r[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), verts / 2, c + ": vertices")
		assert_lt((r[1][0] as PackedInt32Array).size() / 3, tris * 6 / 10, c + ": triangles")
		var bones_per := (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / verts
		assert_eq((r[0][Mesh.ARRAY_BONES] as PackedInt32Array).size(),
				(r[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * bones_per, c + ": skin weights kept per vertex")


## The saved tier meshes (tools/bake_character_tiers.gd) are the current
## full meshes: high in full, medium from LOD 1, low from LOD 2, each with
## its coarser LODs and no material.
func test_saved_tier_meshes_match_the_full_ones() -> void:
	for c: String in CharacterRig.SELECTABLE:
		var full: ArrayMesh = load(MeshyRig.finger_mesh_path(c))
		var lods := ReducedMesh.lods_of(full, 0)
		var high: ArrayMesh = load(MeshyRig.tier_mesh_path(c, "high"))
		assert_eq(high.surface_get_array_index_len(0), full.surface_get_array_index_len(0), c + ": high is the full mesh")
		for t: int in [1, 2]:
			var saved: ArrayMesh = load(MeshyRig.tier_mesh_path(c, MeshyRig.TIERS[t]))
			assert_eq(saved.surface_get_array_index_len(0), (lods[t - 1][1] as PackedInt32Array).size(),
					"%s %s: base is LOD %d" % [c, MeshyRig.TIERS[t], t])
			assert_eq(ReducedMesh.lods_of(saved, 0).size(), lods.size() - t, c + ": coarser LODs kept")
			assert_eq(saved.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS,
					full.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS, c + ": same skinning")
		var medium: ArrayMesh = load(MeshyRig.tier_mesh_path(c, "medium"))
		var low: ArrayMesh = load(MeshyRig.tier_mesh_path(c, "low"))
		assert_lt(medium.surface_get_array_len(0), full.surface_get_array_len(0) / 2, c + ": medium skins under half")
		assert_lt(low.surface_get_array_len(0), full.surface_get_array_len(0) / 3, c + ": low skins under a third")
		assert_lt(low.surface_get_array_index_len(0), full.surface_get_array_index_len(0) / 3, c + ": low draws under a third")
		for m: ArrayMesh in [high, medium, low]:
			assert_null(m.surface_get_material(0), c + ": no material (the tier's comes with the rig)")


## Each tier's material: 2K PBR, 1K PBR, one small flat texture on the
## stylized shader.
func test_tier_materials() -> void:
	for c: String in CharacterRig.SELECTABLE:
		var high: ShaderMaterial = load(MeshyRig.tier_material_path(c, "high"))
		var medium: ShaderMaterial = load(MeshyRig.tier_material_path(c, "medium"))
		var low: ShaderMaterial = load(MeshyRig.tier_material_path(c, "low"))
		assert_eq(high.shader, MeshyRig.SHADER)
		assert_eq((high.get_shader_parameter("albedo_tex") as Texture2D).get_width(), 2048, c + ": high 2K")
		assert_eq((medium.get_shader_parameter("normal_tex") as Texture2D).get_width(), 1024, c + ": medium 1K")
		assert_eq(low.shader, MeshyRig.STYLIZED_SHADER)
		assert_eq((low.get_shader_parameter("albedo_tex") as Texture2D).get_width(), 512, c + ": low 512")
		assert_null(low.get_shader_parameter("normal_tex"), c + ": low has no normal map")


func test_rigs_pick_the_tier_for_their_view() -> void:
	var third := MeshyRig.new("vanguard")
	add_child_autofree(third)
	third.setup(Color.ORANGE)
	var close := MeshyRig.new("vanguard")
	close.full_detail = true
	add_child_autofree(close)
	close.setup(Color.ORANGE)
	var mi_of := func(r: Node) -> MeshInstance3D:
		return r.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	assert_eq(third.tier, MeshyRig.current_tier(), "third person: the quality's tier")
	assert_same(mi_of.call(third).mesh, load(MeshyRig.tier_mesh_path("vanguard", third.tier)))
	assert_eq(close.tier, "high", "close-up: high")
	assert_same(mi_of.call(close).mesh, load(MeshyRig.tier_mesh_path("vanguard", "high")))
	var mat := mi_of.call(third).material_override as ShaderMaterial
	assert_ne(mat, load(MeshyRig.tier_material_path("vanguard", third.tier)), "a copy: the colour is per player")
	assert_eq(mat.get_shader_parameter("team_color"), Color.ORANGE)
	assert_true(third.make_first_person())
	var arms: Mesh = mi_of.call(third).mesh
	assert_gt(arms.get_faces().size(), (load(MeshyRig.tier_mesh_path("vanguard", "medium")) as Mesh).get_faces().size() / 10,
			"first person: arms cut from the full mesh")


## The rig scene carries no mesh or material, so a character loads only its
## tier's textures.
func test_rig_scenes_load_no_source_textures() -> void:
	for c: String in CharacterRig.SELECTABLE:
		var model: Node = (load(MeshyRig.rig_scene_path(c)) as PackedScene).instantiate()
		var mis := model.find_children("*", "MeshInstance3D", true, false)
		assert_eq(mis.size(), 1, c)
		assert_null((mis[0] as MeshInstance3D).mesh, c + ": no mesh")
		assert_eq(model.find_children("*", "Skeleton3D", true, false).size(), 1, c + ": skeleton kept")
		model.free()
