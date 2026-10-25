extends GutTest
## Shader warm-up reveal (presentation/warmup.gd): the match is held back and
## shown a batch of materials a frame under an overhead camera, then put back
## exactly as it was; and the loading cover in front of it.


func _scene() -> Array:
	var root := Node3D.new()
	add_child_autofree(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var meshes: Array[MeshInstance3D] = []
	for i in 5:
		var m := MeshInstance3D.new()
		m.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(i * 0.2, 0.5, 0.5)
		m.material_override = mat
		m.position = Vector3(i * 10.0 - 20.0, 0.0, i * 3.0)
		m.layers = 1 | (2 if i == 2 else 0)
		root.add_child(m)
		meshes.append(m)
	var hidden := MeshInstance3D.new()
	hidden.mesh = BoxMesh.new()
	hidden.visible = false
	root.add_child(hidden)
	var probe := ReflectionProbe.new()
	root.add_child(probe)
	return [root, cam, meshes, hidden, probe]


func test_reveal_restores_layers_camera_and_probes() -> void:
	var s := _scene()
	var root: Node3D = s[0]
	var cam: Camera3D = s[1]
	var warm := Warmup.new()
	root.add_child(warm)
	var fractions: Array[float] = []
	warm.progress.connect(func(f: float) -> void: fractions.append(f))
	var mask := cam.cull_mask
	await warm._reveal(cam)
	for m: MeshInstance3D in s[2]:
		assert_eq(m.layers, 1 | (2 if m == s[2][2] else 0), "layers put back")
	assert_eq((s[3] as MeshInstance3D).layers, 1, "hidden geometry left alone")
	assert_true((s[4] as ReflectionProbe).visible, "probe shown again")
	assert_eq(cam.cull_mask, mask)
	assert_true(cam.current, "the match camera is current again")
	assert_false(get_viewport().disable_3d)
	assert_gt(fractions.size(), 1)
	for i in range(1, fractions.size()):
		assert_gte(fractions[i], fractions[i - 1], "progress only goes up")


func test_overview_sees_the_whole_map() -> void:
	var bounds := AABB(Vector3(-40, -2, -25), Vector3(80, 30, 50))
	var cam := Warmup._overview(bounds, 1)
	add_child_autofree(cam)
	assert_eq(cam.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_gte(cam.size, 80.0)
	assert_gt(cam.global_position.y, bounds.end.y)
	assert_lte(cam.global_position.y - cam.far, bounds.position.y, "far plane reaches below the floor")
	assert_almost_eq(-cam.global_basis.z, Vector3.DOWN, Vector3.ONE * 0.001, "looks straight down")


func test_cover_shows_the_map_and_never_goes_back() -> void:
	var config := MatchConfig.new()
	config.map = "spire"
	config.game_mode = GameMode.CTF
	var cover := LoadingCover.new()
	add_child_autofree(cover)
	cover.show_config(config)
	assert_eq(cover._map.text, tr("MAP_SPIRE").to_upper())
	assert_eq(cover._mode.text, tr("MODE_CTF").to_upper())
	assert_not_null(cover._art.texture)
	cover.set_progress(0.6)
	cover.set_progress(0.3)
	assert_eq(cover._target, 0.6)
	for i in 120:
		cover._process(1.0 / 60.0)
	assert_lte(cover._shown, 0.6)
	assert_gt(cover._shown, 0.5)


func test_take_adopts_the_menu_cover() -> void:
	var menu_cover := LoadingCover.new()
	get_tree().root.add_child(menu_cover)
	var owner := Node.new()
	add_child_autofree(owner)
	var config := MatchConfig.new()
	var cover := LoadingCover.take(owner, config)
	assert_same(cover, menu_cover)
	assert_eq(cover.get_parent(), owner)
	assert_null(get_tree().root.get_node_or_null(NodePath(LoadingCover.NAME)))


func test_preload_lists_existing_mesh_files_map_first() -> void:
	for map_id: String in Maps.PLAYABLE:
		var files := MatchPreload.paths(map_id)
		assert_gt(files.size(), 20, map_id)
		for f in files:
			assert_true(ResourceLoader.exists(f), f)
		var scene: String = Maps.LIST[map_id].presentation
		assert_true(files.has(scene))
		assert_true(files.has(WeaponModels.DIR + "pulse_rifle.glb"), "weapons listed")
		for dep in MatchPreload._dependencies(scene):
			if files.has(dep):
				assert_lt(files.find(dep), files.find(scene), "%s loads before the map scene" % dep)


func test_idle_pool_wait_returns_and_preload_holds_until_release() -> void:
	await MatchPreload.wait_for_idle_pool(get_tree())
	await MatchPreload.run(get_tree(), PackedStringArray([WeaponModels.DIR + "mag_pistol.glb", "res://missing.glb"]))
	assert_eq(MatchPreload._held.size(), 1)
	MatchPreload.release()
	assert_eq(MatchPreload._held.size(), 0)
