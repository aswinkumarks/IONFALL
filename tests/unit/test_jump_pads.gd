extends GutTest
## Jump pads on Halcyon Spire and Vesper Foundry: every pad throws a player
## who walks onto it to its landing point, the same way every time, and
## bots path over them.

const Move := PlayerSimState.Move
const MAPS := ["spire", "foundry"]

var world: SimWorld
var p: SimPlayer
var input: SimHarness.CommandScript


func _setup(map_id: String) -> Node3D:
	var gameplay := Maps.gameplay(map_id)
	add_child_autofree(gameplay)
	world = SimWorld.new()
	world.configure(7, SimHarness.MOVEMENT, gameplay.spawn_points())
	add_child_autofree(world)
	await wait_physics_frames(2)
	p = world.add_player(1, SimHarness.loadout(), "test", false)
	input = SimHarness.CommandScript.new()
	return gameplay


func _run(ticks: int, move: Vector2 = Vector2.ZERO) -> void:
	for i in ticks:
		world.step({1: input.cmd(world.tick, move)})


## Walks onto `pad` from 3 m away (on the side away from its target) and
## returns [launched, landing position, ticks in the air].
func _use(pad: Dictionary) -> Array:
	var away: Vector3 = (pad.position - pad.target) * Vector3(1, 0, 1)
	var start: Vector3 = pad.position + away.normalized() * 3.0 + Vector3(0, 0.05, 0)
	var yaw := atan2(away.x, away.z)  # facing -away (forward is -Z)
	input.yaw = yaw
	SimHarness.place(p, start, yaw)
	_run(10)
	var launched := false
	var air := 0
	for i in 400:
		_run(1, Vector2(0, 1) if not launched else Vector2.ZERO)
		if p.state.move_state == Move.AIR:
			if p.state.velocity.y > 8.0:
				launched = true
			air += 1
		elif launched:
			break
	return [launched, p.state.position, air]


func test_every_pad_lands_on_its_target() -> void:
	for map_id in MAPS:
		var gameplay: Node3D = await _setup(map_id)
		var pads: Array = gameplay.jump_pads()
		assert_eq(pads.size(), 4, "%s has four pads" % map_id)
		for pad: Dictionary in pads:
			var r := _use(pad)
			assert_true(r[0], "%s pad %s launches" % [map_id, pad.position])
			var landed: Vector3 = r[1]
			assert_lt(Vector2(landed.x - pad.target.x, landed.z - pad.target.z).length(), 1.0,
					"%s pad %s lands at %s (got %s)" % [map_id, pad.position, pad.target, landed])
			assert_almost_eq(landed.y, (pad.target as Vector3).y, 0.1, "on the deck")
			assert_eq(p.state.move_state, Move.GROUND)
		gameplay.queue_free()
		world.queue_free()
		await wait_physics_frames(1)


func test_launch_is_deterministic() -> void:
	var gameplay: Node3D = await _setup("spire")
	var pad: Dictionary = gameplay.jump_pads()[0]
	var a := _use(pad)
	var b := _use(pad)
	assert_eq(a[1], b[1], "same landing, bit for bit")
	assert_eq(a[2], b[2], "same flight time")


func test_pads_do_not_fire_in_the_air() -> void:
	var gameplay: Node3D = await _setup("foundry")
	var pad: Dictionary = gameplay.jump_pads()[0]
	# Dropped onto the pad: it fires once landed, not while falling through
	# the trigger zone.
	SimHarness.place(p, pad.position + Vector3(0, 0.4, 0), 0.0)
	_run(1)
	assert_lt(p.state.velocity.y, 1.0, "falling, not launched yet")
	var launched := false
	for i in 30:
		_run(1)
		launched = launched or p.state.velocity.y > 8.0
	assert_true(launched, "launched once on the pad")


func test_bots_path_over_pads() -> void:
	for map_id in MAPS:
		var gameplay: Node3D = await _setup(map_id)
		var nav := BotNavigation.new()
		add_child_autofree(nav)
		await nav.build(gameplay)
		for pad: Dictionary in gameplay.jump_pads():
			var away: Vector3 = ((pad.position - pad.target) * Vector3(1, 0, 1)).normalized()
			var path := nav.path(pad.position + away * 2.0, pad.target)
			var kinds := path.map(func(pt: Array) -> int: return pt[1])
			assert_has(kinds, BotNavigation.Traversal.PAD, "%s: the path to %s takes the pad" % [map_id, pad.target])
		nav.queue_free()
		gameplay.queue_free()
		world.queue_free()
		await wait_physics_frames(1)


func test_a_bot_takes_a_pad_to_the_deck() -> void:
	for map_id in MAPS:
		var gameplay: Node3D = await _setup(map_id)
		var nav := BotNavigation.new()
		add_child_autofree(nav)
		await nav.build(gameplay)
		var pad: Dictionary = gameplay.jump_pads()[1]
		var away: Vector3 = ((pad.position - pad.target) * Vector3(1, 0, 1)).normalized()
		var bot := world.add_player(1000, SimHarness.loadout(), "Bot", true)
		SimHarness.place(bot, pad.position + away * 3.0 + Vector3(0, 0.05, 0), 0.0)
		var brain := BotBrain.new(world, nav, 1000, 3)
		brain.go_to(pad.target + Vector3(0, 0.4, 0))
		var launched := false
		var arrived := -1
		for t in 600:
			world.step({1: input.cmd(world.tick), 1000: brain.command_for(world.tick, bot)})
			launched = launched or bot.state.velocity.y > 8.0
			if bot.state.is_on_floor() and bot.state.position.distance_to(pad.target) < 1.5:
				arrived = t
				break
		assert_true(launched, "%s: the bot used the pad" % map_id)
		assert_gt(arrived, -1, "%s: the bot reached %s (at %s)" % [map_id, pad.target, bot.state.position])
		gut.p("%s: arrived after %d ticks" % [map_id, arrived])
		nav.queue_free()
		gameplay.queue_free()
		world.queue_free()
		await wait_physics_frames(1)


## Over real ENet the client predicts its own launches: walking back and
## forth over a pad causes no visible corrections.
func test_pad_launches_are_predicted_online() -> void:
	var gameplay := Maps.gameplay("foundry")
	add_child_autofree(gameplay)
	await wait_physics_frames(2)
	var port := 0
	var server: ServerSession
	var err := FAILED
	for attempt in 5:
		port = SimHarness.free_udp_port()
		server = ServerSession.new()
		add_child_autofree(server)
		err = server.start(port, SimHarness.MOVEMENT, SimHarness.loadout(), gameplay.spawn_points())
		if err == OK:
			break
		server.queue_free()
	assert_eq(err, OK)
	var pad: Dictionary = gameplay.jump_pads()[0]
	var script := SimHarness.CommandScript.new()
	var c := ClientSession.new()
	# Walk at the pad for 2 s, stand for 2 s (flight and landing), repeat.
	c.input_source = func(t: int) -> PlayerCommand: return script.cmd(t, Vector2(0, 1) if (t / 120) % 2 == 0 else Vector2.ZERO)
	add_child_autofree(c)
	c.join("127.0.0.1", port, SimHarness.MOVEMENT, SimHarness.loadout(), gameplay.spawn_points())
	await wait_until(func() -> bool: return c.is_predicting(), 6.0)
	assert_true(c.is_predicting())
	var me: SimPlayer = server.world.get_player(c.local_id)
	var away: Vector3 = ((pad.position - pad.target) * Vector3(1, 0, 1)).normalized()
	script.yaw = atan2(away.x, away.z)
	server.world.teleport(me, pad.position + away * 2.5 + Vector3(0, 0.05, 0))
	await wait_seconds(0.5)
	c.reset_metrics()
	var launched := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		launched = launched or me.state.velocity.y > 8.0
		await get_tree().process_frame
	gut.p("corrections %d visible %d snaps %d" % [c.corrections, c.visible_corrections, c.snaps])
	assert_true(launched, "the server launched the player")
	assert_lt(me.state.position.distance_to(pad.target), 1.5, "landed on the catwalk (at %s)" % me.state.position)
	assert_eq(c.visible_corrections, 0, "the launch was predicted")
	assert_eq(c.snaps, 0)
