extends GutTest
## MapMaterials: triplanar becomes planar UVs that sample what triplanar's
## dominant projection did; the kit's closed materials cull back faces. The
## saved maps carry the conversion.


func test_planar_uvs_follow_the_dominant_projection() -> void:
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	# One vertex on each kind of face: top (+Y), front (+Z), side (+X).
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(2, 4, 6), Vector3(2, 4, 6), Vector3(2, 4, 6)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.BACK, Vector3.RIGHT])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 0, 0])
	MapMaterials.planar_uvs(arrays, m)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	# Triplanar position: world * scale, y flipped: (1, -2, 3).
	assert_eq(uv[0], Vector2(1, 3), "top faces take xz")
	assert_eq(uv[1], Vector2(1, -2), "front faces take xy")
	assert_eq(uv[2], Vector2(-3, -2), "side faces take zy * (-1, 1)")


func test_saved_maps_have_no_triplanar_and_cull_closed_kit_materials() -> void:
	for map_id in ["station", "spire", "foundry"]:
		var root := Maps.presentation(map_id)
		var triplanar := 0
		var culled := 0
		var double_sided := []
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i) as BaseMaterial3D
				if m == null:
					continue
				triplanar += 1 if m.uv1_triplanar else 0
				if m.resource_name in MapMaterials.CULL_BACK:
					culled += 1 if m.cull_mode == BaseMaterial3D.CULL_BACK else 0
				elif m.cull_mode == BaseMaterial3D.CULL_DISABLED and not double_sided.has(m.resource_name):
					double_sided.append(m.resource_name)
		assert_eq(triplanar, 0, "%s: no triplanar left" % map_id)
		if map_id != "station":
			assert_eq(culled, 20, "%s: five kit materials in four quadrants" % map_id)
			double_sided.sort()
			assert_eq(double_sided, ["MI_Trim_01", "MI_Trim_02"], "%s: open wall panels stay double-sided" % map_id)
		root.free()


## Converting a saved mesh again changes nothing (the bake is complete and
## the builders' output is already final).
func test_saved_meshes_need_no_conversion() -> void:
	for map_id in ["station", "spire", "foundry"]:
		var root := Maps.presentation(map_id)
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh is ArrayMesh:
				assert_same(MapMaterials.converted(mi.mesh, MapMaterials.transform_in(mi, root)), mi.mesh, mi.name)
		root.free()
