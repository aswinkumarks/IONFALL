extends GutTest
## Nameplates (2D) must hide behind walls like the 3D ones did (they'd be a
## wallhack otherwise) and fade out past the range; BlobShadows lie on the
## floor under each player and fade with height.

var _camera: Camera3D


func before_each() -> void:
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_camera.current = true


func _wall(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Sim.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child_autofree(body)


func _visual(at: Vector3) -> PlayerVisual:
	var v := PlayerVisual.new()
	add_child_autofree(v)
	v.setup("Ada", false, Color.ORANGE, 0, "sentinel")
	v.global_position = at
	return v


func _plates(visuals: Array) -> Nameplates:
	var p := Nameplates.new()
	var dict := {}
	for i in visuals.size():
		dict[i] = visuals[i]
	p.visuals = dict
	add_child_autofree(p)
	return p


func test_hidden_behind_a_wall_and_shown_in_the_open() -> void:
	var open := _visual(Vector3(3, 0, -10))
	var hidden := _visual(Vector3(-3, 0, -10))
	_wall(Vector3(-3, 1.5, -5), Vector3(4, 4, 0.5))
	await wait_physics_frames(2)
	var p := _plates([open, hidden])
	for i in 20:
		await wait_process_frames(1)
	assert_true(p._sight[open][0], "in sight")
	assert_gt(p._sight[open][2], 0.9, "shown")
	assert_false(p._sight[hidden][0], "behind the wall")
	assert_lt(p._sight[hidden][2], 0.1, "hidden")


func test_out_of_range_isnt_drawn() -> void:
	var far := _visual(Vector3(0, 0, -(PlayerVisual.NAMEPLATE_RANGE + Nameplates.FADE_METRES + 5.0)))
	var p := _plates([far])
	for i in 5:
		await wait_process_frames(1)
	assert_lt(p._sight.get(far, [true, 0.0, 0.0])[2], 0.1)


func test_hide_nameplate_and_team() -> void:
	var v := _visual(Vector3(0, 0, -5))
	v.set_team(1, Color.RED)
	assert_eq(v.nameplate_team, 1)
	assert_eq(v.nameplate_color, Color.RED)
	v.set_bar(0.0, Balance.PLAYER.max_health * 0.5)
	assert_false(v.bar_on_shield)
	assert_almost_eq(v.bar_fraction, 0.5, 0.001)
	v.hide_nameplate()
	assert_false(v.nameplate_shown)


func test_blob_shadows_lie_on_the_floor_and_fade_with_height() -> void:
	_wall(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	await wait_physics_frames(2)
	var blobs := BlobShadows.new()
	add_child_autofree(blobs)
	blobs.visible = true  # whatever the shadow setting here
	blobs.show_at(PackedVector3Array([Vector3(1, 0, 2), Vector3(0, 1.5, 0), Vector3(0, 10, 0), Vector3.INF]))
	assert_eq(blobs.multimesh.visible_instance_count, 2, "on the floor and 1.5 m up; 10 m up and INF skipped")
	# (The headless renderer keeps no instance data to read back.)
	var on_floor := BlobShadows.place(Vector3(1, 0, 2), Vector3(1, 0, 2), Vector3.UP)
	assert_almost_eq((on_floor[0] as Transform3D).origin, Vector3(1, BlobShadows.LIFT, 2), Vector3.ONE * 0.001)
	assert_almost_eq((on_floor[0] as Transform3D).basis.y, Vector3.UP, Vector3.ONE * 0.001)
	assert_almost_eq(on_floor[1], 1.0, 0.001)
	var up := BlobShadows.place(Vector3(0, 1.5, 0), Vector3.ZERO, Vector3.UP)
	assert_almost_eq(up[1], 0.5, 0.001, "half strength 1.5 m up")
	var ramp_normal := Vector3(0, 1, 1).normalized()
	var ramp := BlobShadows.place(Vector3.ZERO, Vector3.ZERO, ramp_normal)
	assert_almost_eq((ramp[0] as Transform3D).basis.y, ramp_normal, Vector3.ONE * 0.001, "tilted with a ramp")
	assert_almost_eq((ramp[0] as Transform3D).basis.determinant(), 1.0, 0.001, "not mirrored")
