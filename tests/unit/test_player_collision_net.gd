extends GutTest
## Player collision over real ENet: the server keeps players apart, and the
## walker's client predicts the bump (SimWorld.push_out_of) instead of being
## corrected every time it walks into someone.


func test_walking_into_a_player_is_predicted() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	var port := 0
	var server: ServerSession
	var err := FAILED
	for attempt in 5:  # a random port can be taken
		port = 41000 + randi() % 8000
		server = ServerSession.new()
		add_child_autofree(server)
		err = server.start(port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points())
		if err == OK:
			break
		server.queue_free()
	assert_eq(err, OK)
	var cs := []
	for i in 2:
		var c := ClientSession.new()
		var script := SimHarness.CommandScript.new()
		var walker := i == 0
		c.input_source = func(t: int) -> PlayerCommand: return script.cmd(t, (Vector2(0, 1) if (t / 90) % 2 == 0 else Vector2(0, -1)) if walker else Vector2.ZERO)
		add_child_autofree(c)
		c.set_meta("script", script)
		c.join("127.0.0.1", port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points())
		cs.append(c)
	await wait_until(func() -> bool: return cs[0].is_predicting() and cs[1].is_predicting(), 6.0)
	var a: SimPlayer = server.world.get_player(cs[0].local_id)
	var b: SimPlayer = server.world.get_player(cs[1].local_id)
	server.world.teleport(a, Vector3(0, 0.05, 17.5))
	server.world.teleport(b, Vector3(0, 0.05, 15.5))
	cs[0].get_meta("script").yaw = 0.0
	await wait_seconds(1.0)
	for c in cs:
		c.reset_metrics()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		cs[0].remote_states()  # what rendering does every frame
		cs[1].remote_states()
		await get_tree().process_frame
	for c in cs:
		gut.p("client %d: corrections %d visible %d snaps %d" % [c.local_id, c.corrections, c.visible_corrections, c.snaps])
	var gap := Vector2(a.state.position.x - b.state.position.x, a.state.position.z - b.state.position.z).length()
	assert_gt(gap, 0.7, "the server kept them apart (%.2f m)" % gap)
	assert_lt(cs[0].visible_corrections, 4, "the walker's bumps were predicted")
	assert_eq(cs[0].snaps, 0)
