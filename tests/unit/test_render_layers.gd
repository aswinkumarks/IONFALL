extends GutTest
## RenderLayers: moving things go on DYNAMIC, which the map's baked lights
## light in real time only where effect lights are on.


func test_baked_lights_follow_the_setting() -> void:
	var map := Node3D.new()
	add_child_autofree(map)
	var baked := OmniLight3D.new()
	baked.light_bake_mode = Light3D.BAKE_STATIC
	map.add_child(baked)
	var sun := DirectionalLight3D.new()
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	map.add_child(sun)
	RenderLayers.light_dynamic_with_baked_lights(map, false)
	assert_eq(baked.light_cull_mask & RenderLayers.DYNAMIC, 0, "phones: baked light leaves moving things to the probes")
	assert_ne(baked.light_cull_mask & 1, 0, "and still lights the default layer")
	assert_ne(sun.light_cull_mask & RenderLayers.DYNAMIC, 0, "the realtime sun lights everything")
	RenderLayers.light_dynamic_with_baked_lights(map, true)
	assert_ne(baked.light_cull_mask & RenderLayers.DYNAMIC, 0, "desktops: back on")


func test_characters_weapons_and_pickups_are_dynamic() -> void:
	var w := WeaponModels.instantiate(&"pulse_rifle")
	add_child_autofree(w)
	for mi: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
		assert_eq(mi.layers, RenderLayers.DYNAMIC, mi.name)
	var v := PlayerVisual.new()
	add_child_autofree(v)
	v.setup("Ada", false, Color.ORANGE, 0, "sentinel")
	for g: VisualInstance3D in v.find_children("*", "GeometryInstance3D", true, false):
		assert_eq(g.layers, RenderLayers.DYNAMIC, g.name)


## Other players' weapons switch to the ~1k-triangle stand-in past
## WeaponModels.FAR_RANGE; only one of the two draws at a time.
func test_weapons_have_a_far_stand_in() -> void:
	var w := WeaponModels.instantiate(&"scatter_gun")
	add_child_autofree(w)
	var near: MeshInstance3D = null
	var far: MeshInstance3D = null
	for mi: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
		if mi.name.ends_with("Far"):
			far = mi
		else:
			near = mi
	assert_not_null(far, "stand-in present (tools/bake_weapon_proxies.gd)")
	if far == null:
		return
	assert_eq(near.visibility_range_end, WeaponModels.FAR_RANGE)
	assert_eq(far.visibility_range_begin, WeaponModels.FAR_RANGE)
	assert_eq(far.transform, near.transform)
	var tris := func(m: Mesh) -> int: return (m.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_lt(tris.call(far.mesh), 1600)
	assert_gt(tris.call(near.mesh), 5000)
	assert_eq(far.mesh.surface_get_format(0), near.mesh.surface_get_format(0), "same pipelines as the model")
	assert_same(far.get_active_material(0), near.get_active_material(0), "and the same material")
