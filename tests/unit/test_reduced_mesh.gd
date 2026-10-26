extends GutTest
## ReducedMesh: third-person characters draw and skin their first LOD; first
## person and the character screen keep the full mesh.


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


## The saved third-person meshes (tools/bake_reduced_characters.gd) are
## the reduction of the current full meshes, with the coarser LODs kept.
func test_saved_reduced_meshes_match_the_full_ones() -> void:
	for c: String in CharacterRig.SELECTABLE:
		var full: ArrayMesh = load(MeshyRig.finger_mesh_path(c))
		var saved: ArrayMesh = load(MeshyRig.reduced_mesh_path(c))
		var lods := ReducedMesh.lods_of(full, 0)
		assert_eq(saved.surface_get_array_index_len(0), (lods[0][1] as PackedInt32Array).size(), c + ": base is LOD 1")
		assert_lt(saved.surface_get_array_len(0), full.surface_get_array_len(0) / 2, c + ": vertices")
		assert_eq(ReducedMesh.lods_of(saved, 0).size(), lods.size() - 1, c + ": coarser LODs kept")
		assert_eq(saved.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS,
				full.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS, c + ": same skinning")


func test_rigs_pick_the_mesh_for_their_view() -> void:
	var full: ArrayMesh = load(MeshyRig.finger_mesh_path("vanguard"))
	var reduced: ArrayMesh = load(MeshyRig.reduced_mesh_path("vanguard"))
	var third := MeshyRig.new("vanguard")
	add_child_autofree(third)
	third.setup(Color.ORANGE)
	var close := MeshyRig.new("vanguard")
	close.full_detail = true
	add_child_autofree(close)
	close.setup(Color.ORANGE)
	var mesh_of := func(r: Node) -> Mesh:
		return (r.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	assert_same(mesh_of.call(third), reduced, "third person: reduced")
	assert_same(mesh_of.call(close), full, "close-up: full")
	assert_true(third.make_first_person())
	assert_ne(mesh_of.call(third), reduced, "first person cuts its arms from the full mesh")
