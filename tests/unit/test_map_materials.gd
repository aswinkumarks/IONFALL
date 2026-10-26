extends GutTest
## MapMaterials: triplanar becomes planar UVs that sample what triplanar's
## dominant projection did; the kit's closed materials cull back faces.


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


func test_maps_lose_triplanar_and_cull_closed_kit_materials() -> void:
	for map_id in ["station", "spire", "foundry"]:
		var root := Maps.presentation(map_id)
		MapMaterials.apply(root)
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


func test_converted_meshes_are_reused() -> void:
	var a := Maps.presentation("station")
	var b := Maps.presentation("station")
	MapMaterials.apply(a)
	MapMaterials.apply(b)
	var ma := (a.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var mb := (b.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	assert_same(ma, mb, "the menu and a match share the converted mesh")
	a.free()
	b.free()
