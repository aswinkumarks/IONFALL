extends GutTest
## Capture the flag (PLAN §2.4): take, drop, return (by touch and by time),
## capture only while our own flag is home, kills don't score for the team,
## 3 captures win, flags and events reach clients, and every map's flag
## bases stand on the floor.

const Held := PlayerCommand.Held

var server: ServerSession
var world: SimWorld
var input: SimHarness.CommandScript


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	server = ServerSession.new()
	server.game_mode = GameMode.CTF
	add_child_autofree(server)
	assert_eq(server.start(-1, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points(), [], null,
			[Vector3(-12, 0, 0), Vector3(12, 0, 0)]), OK)
	world = server.world
	input = SimHarness.CommandScript.new()


## Two players: id 1 on team 0 (west), id 2 on team 1 (east).
func _two_players() -> Array:
	var a := world.add_player(1, SimHarness.loadout(), "west", false)
	var b := world.add_player(2, SimHarness.loadout(), "east", false)
	a.team = 0
	b.team = 1
	SimHarness.place(a, Vector3(-4, 0.05, 15), 0.0)  # away from both flags
	SimHarness.place(b, Vector3(4, 0.05, 15), 0.0)
	world.drain_events()
	return [a, b]


func _step(ticks: int = 1) -> void:
	for i in ticks:
		world.step({1: input.cmd(world.tick), 2: input.cmd(world.tick)})


func _events(type: String) -> Array:
	return world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == type)


func test_teams_and_flags_are_set_up() -> void:
	assert_true(world.teams_enabled)
	assert_false(world.kills_score_for_team, "kills don't score for the team in CTF")
	assert_eq(world.flags.size(), 2)
	assert_eq(world.flags[0].team, 0)
	assert_true(world.flags[0].at_base() and world.flags[1].at_base())


func test_take_and_capture() -> void:
	var pl := _two_players()
	var a: SimPlayer = pl[0]
	SimHarness.place(a, Vector3(12, 0.05, 0), 0.0)  # on the east (enemy) flag
	_step()
	assert_eq(world.flags[1].carrier, 1, "west player takes the east flag")
	var take: Array = _events("flag")
	assert_eq(take.size(), 1)
	assert_eq(take[0].action, "take")
	SimHarness.place(a, Vector3(-12, 0.05, 0), 0.0)  # home, our flag is there
	_step()
	assert_eq(world.team_scores[0], 1, "capture scores for the team")
	assert_eq(world.scores[1], Balance.MODES.capture_points)
	assert_true(world.flags[1].at_base(), "the captured flag goes home")
	assert_eq(_events("flag")[0].action, "capture")


func test_no_capture_while_our_flag_is_away() -> void:
	var pl := _two_players()
	var a: SimPlayer = pl[0]
	var b: SimPlayer = pl[1]
	SimHarness.place(a, Vector3(12, 0.05, 0), 0.0)
	SimHarness.place(b, Vector3(-12, 0.05, 0), 0.0)
	_step()
	assert_eq(world.flags[1].carrier, 1)
	assert_eq(world.flags[0].carrier, 2, "both flags taken")
	SimHarness.place(a, Vector3(-12, 0.05, 0), 0.0)
	SimHarness.place(b, Vector3(0, 0.05, 15), 0.0)
	_step(5)
	assert_eq(world.team_scores[0], 0, "can't capture while our flag is gone")
	assert_eq(world.flags[1].carrier, 1, "still carrying")


func test_carrier_death_drops_and_returns() -> void:
	var pl := _two_players()
	var a: SimPlayer = pl[0]
	var b: SimPlayer = pl[1]
	SimHarness.place(a, Vector3(12, 0.05, 0), 0.0)
	_step()
	SimHarness.place(a, Vector3(5, 0.05, 15), 0.0)
	_step()
	world._kill(a, 2, Weapons.at(Weapons.PULSE), false)
	var f: SimWorld.Flag = world.flags[1]
	assert_eq(f.carrier, 0, "dropped")
	assert_gt(f.return_tick, world.tick)
	assert_almost_eq(f.position.y, 0.0, 0.1, "on the floor where the carrier fell")
	assert_eq(world.team_scores[1], 0, "the kill doesn't score for the team")
	assert_eq(world.scores[2], 1, "but it scores for the killer")
	# The owner team touches it: back home at once.
	SimHarness.place(b, f.position + Vector3(0, 0.05, 0), 0.0)
	world.drain_events()
	_step()
	assert_true(f.at_base(), "returned by touch")
	assert_eq(world.scores[2], 1 + Balance.MODES.return_points)


func test_dropped_flag_returns_by_itself() -> void:
	var pl := _two_players()
	var a: SimPlayer = pl[0]
	SimHarness.place(a, Vector3(12, 0.05, 0), 0.0)
	_step()
	SimHarness.place(a, Vector3(5, 0.05, 15), 0.0)
	_step()
	world._kill(a, 0, null, false)
	var f: SimWorld.Flag = world.flags[1]
	world.tick = f.return_tick
	world.drain_events()
	_step()
	assert_true(f.at_base(), "home after 30 s on the ground")
	assert_eq(_events("flag").filter(func(e: Dictionary) -> bool: return e.action == "return").size(), 1)


func test_leaving_with_the_flag_drops_it() -> void:
	var pl := _two_players()
	var a: SimPlayer = pl[0]
	SimHarness.place(a, Vector3(12, 0.05, 0), 0.0)
	_step()
	world.remove_player(1)
	assert_eq(world.flags[1].carrier, 0)
	assert_false(world.flags[1].at_base(), "on the ground where they left")


func test_three_captures_win() -> void:
	server.add_local_player("Host")
	server.bot_fill = 2
	server.update_bot_fill()
	server._set_phase(MatchPhase.PLAYING, world.tick + 100000)
	world.team_scores[0] = GameMode.score_limit(GameMode.CTF)
	server._update_phase()
	assert_eq(server.phase, MatchPhase.POST_MATCH)
	var results: Array = server.drain_host_events().filter(func(e: Dictionary) -> bool: return e.type == "results")
	assert_eq(results.size(), 1)
	assert_eq(results[0].winner_team, 0)
	assert_eq(results[0].mode, GameMode.CTF)


func test_flags_and_flag_events_go_over_the_wire() -> void:
	var snap := Snapshot.new()
	snap.id = 10
	snap.flags = [{"team": 0, "carrier": 0, "position": Vector3(-12, 0, 0), "return_ticks": 0},
			{"team": 1, "carrier": 1001, "position": Vector3(3, 1, 2), "return_ticks": 0}]
	var back := Snapshot.decode(snap.encode({}, []), {})
	assert_not_null(back)
	assert_eq(back.flags.size(), 2)
	assert_eq(back.flags[1].carrier, 1001)
	assert_almost_eq(back.flags[1].position.x, 3.0, 0.01)
	for action in Protocol.FLAG_ACTIONS:
		var e := {"type": "flag", "id": "x", "action": action, "team": 1, "player": 7, "tick": 99, "position": Vector3(1, 2, 3)}
		var w := Wire.Writer.new()
		assert_true(Protocol.write_event(w, e))
		var r := Protocol.read_event(Wire.Reader.new(w.data()))
		assert_eq(r.action, action)
		assert_eq(r.player, 7)
	var roster := Protocol.decode_roster(Protocol.encode_roster(1, [], GameMode.CTF))
	assert_eq(roster.mode, GameMode.CTF, "new mode ids are accepted")


func test_map_flag_bases_stand_on_the_floor() -> void:
	for id: String in Maps.PLAYABLE:
		var gameplay := Maps.gameplay(id)
		add_child_autofree(gameplay)
		await wait_physics_frames(2)
		var bases: Array = gameplay.flag_bases()
		assert_eq(bases.size(), 2, "%s has two flag bases" % id)
		assert_almost_eq((bases[0] as Vector3).x, -(bases[1] as Vector3).x, 0.01, "%s: mirrored" % id)
		var space := gameplay.get_world_3d().direct_space_state
		for b: Vector3 in bases:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(b + Vector3.UP * 1.5, b + Vector3.DOWN * 1.0,
					Sim.LAYER_WORLD))
			assert_false(hit.is_empty(), "%s: floor under %s" % [id, b])
			if not hit.is_empty():
				assert_almost_eq(hit.position.y, b.y, 0.05, "%s: base %s sits on the floor" % [id, b])
			# A player can stand on the base (a ray from inside a solid block
			# misses it: Station's bases were once inside its end modules).
			var body := CapsuleShape3D.new()
			body.radius = 0.4
			body.height = 1.8
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = body
			q.collision_mask = Sim.LAYER_WORLD
			q.transform = Transform3D(Basis(), b + Vector3.UP * 0.95)
			var in_the_way := space.intersect_shape(q, 8).filter(func(h: Dictionary) -> bool:
				return gameplay.is_ancestor_of(h.collider))  # not the test arena from before_each
			assert_true(in_the_way.is_empty(), "%s: room to stand on base %s" % [id, b])
		gameplay.queue_free()
		await wait_physics_frames(1)


func test_a_joined_client_sees_the_flags() -> void:
	var host_cfg := MatchConfig.make(MatchConfig.Mode.HOST, "Hoster", 1)
	host_cfg.game_mode = GameMode.CTF
	host_cfg.port = SimHarness.free_udp_port()
	MatchConfig.pending = host_cfg
	var host: Node = preload("res://game/match.tscn").instantiate()
	add_child_autofree(host)
	await wait_seconds(0.3)
	var join_cfg := MatchConfig.make(MatchConfig.Mode.JOIN, "Joiner", 0, "127.0.0.1")
	join_cfg.port = host_cfg.port
	MatchConfig.pending = join_cfg
	var joiner: Node = preload("res://game/match.tscn").instantiate()
	add_child_autofree(joiner)
	await wait_until(func() -> bool: return joiner.client != null and joiner.client.flags.size() == 2, 5.0)
	assert_eq(joiner.client.flags.size(), 2, "flags arrive in snapshots")
	assert_eq(joiner.client.game_mode, GameMode.CTF)
	assert_ne(joiner._team_of(joiner.local_id()), GameMode.NO_TEAM, "the client is on a team")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
