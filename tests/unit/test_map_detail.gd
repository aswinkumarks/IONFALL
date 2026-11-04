extends GutTest
## MapDetail: the maps' look by quality tier (high: full materials, medium:
## no occlusion map, low: colour and lightmap only) and per-map exposure,
## as material copies set once as surface overrides.


func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	MapDetail.station_panels(m)
	return m


func test_station_panels_have_depth() -> void:
	var m := _material()
	assert_true(m.normal_enabled)
	assert_not_null(m.normal_texture)
	assert_true(m.ao_enabled)
	assert_eq(m.roughness_texture_channel, BaseMaterial3D.TEXTURE_CHANNEL_GREEN)
	var hull: ArrayMesh = load("res://maps/station/meshes/hull.res")
	var saved := hull.surface_get_material(0) as StandardMaterial3D
	assert_eq(saved.normal_texture.resource_path, MapDetail.PANEL_NORMAL, "the saved Station meshes carry the plating")


func test_tiers_simplify_materials() -> void:
	var m := _material()
	var medium := MapDetail.simplified(m, "medium")
	assert_false(medium.ao_enabled, "medium: no occlusion map")
	assert_true(medium.normal_enabled, "medium keeps the normal map")
	var low := MapDetail.simplified(m, "low")
	assert_false(low.normal_enabled, "low: no normal map")
	assert_null(low.roughness_texture, "low: no roughness map")
	assert_eq(low.albedo_texture, m.albedo_texture, "low keeps the colour")
	assert_true(m.normal_enabled, "the source material is untouched")


func test_apply_sets_overrides_and_exposure() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var mesh := BoxMesh.new()
	mesh.material = _material()
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.get_mesh_arrays())
	array_mesh.surface_set_material(0, mesh.material)
	var a := MeshInstance3D.new()
	a.mesh = array_mesh
	var b := MeshInstance3D.new()
	b.mesh = array_mesh
	root.add_child(a)
	root.add_child(b)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	root.add_child(we)
	MapDetail.apply(root, "spire", "low")
	var low := a.get_surface_override_material(0) as BaseMaterial3D
	assert_not_null(low)
	assert_false(low.normal_enabled)
	assert_same(b.get_surface_override_material(0), low, "one copy per material")
	assert_almost_eq(we.environment.tonemap_exposure, float(Maps.LIST.spire.exposure), 0.001)
	MapDetail.apply(root, "spire", "high")
	assert_null(a.get_surface_override_material(0), "high: the map's own material")
