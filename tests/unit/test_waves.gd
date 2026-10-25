extends GutTest
## Co-op waves (PLAN §2.4): humans on team 0 against bot waves on team 1;
## waves grow, dead wave bots leave, fallen humans wait for the end of the
## wave, clearing wave 10 wins, everyone down loses; the wave status and
## events reach clients.

var server: ServerSession
var world: SimWorld


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	server = ServerSession.new()
	server.game_mode = GameMode.WAVES
	add_child_autofree(server)
	assert_eq(server.start(-1, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	world = server.world
	server.max_combatants = 8
	server.add_local_player("Host")
	server.bot_fill = 4
	server.update_bot_fill()


func _tick(n: int = 1) -> void:
	for i in n:
		server._physics_process(0.0)


func _play() -> void:
	server._set_phase(MatchPhase.PLAYING, world.tick + 100000)
	server.waves.reset(world.tick)


func _until_fighting() -> void:
	for i in Balance.MODES.wave_intermission_ticks + 5:
		if server.waves.fighting:
			return
		_tick()


func _kill_wave() -> void:
	for id: int in server.bots.keys():
		var bot: SimPlayer = world.players[id]
		if bot.state.alive:
			world._kill(bot, ServerSession.LOCAL_PLAYER_ID, Weapons.at(Weapons.PULSE), false)
	_tick(WaveDirector.CLEANUP_TICKS + 2)


func test_setup_has_no_fill_bots_and_humans_on_team_0() -> void:
	assert_eq(server.bots.size(), 0, "the waves bring their own bots")
	assert_eq(world.players[ServerSession.LOCAL_PLAYER_ID].team, GameMode.HUMANS)
	assert_true(world.teams_enabled)
	assert_false(world.friendly_fire)


func test_first_wave_arrives_after_the_intermission() -> void:
	_play()
	_tick(Balance.MODES.wave_intermission_ticks - 10)
	assert_false(server.waves.fighting)
	_until_fighting()
	assert_true(server.waves.fighting)
	assert_eq(server.waves.wave, 1)
	assert_eq(server.bots.size(), server.waves.wave_size(1, 1))
	for id in server.bots:
		assert_eq(world.players[id].team, GameMode.WAVE_TEAM, "wave bots on the other team")


func test_cleared_wave_scores_and_revives() -> void:
	_play()
	_until_fighting()
	var me: SimPlayer = world.players[ServerSession.LOCAL_PLAYER_ID]
	# A second human keeps the team standing while we're down.
	var mate := world.add_player(2, SimHarness.loadout(), "mate", false)
	server._join_team(mate)
	world._kill(me, 0, null, false)
	_tick(400)
	assert_false(me.state.alive, "no respawn during the wave")
	assert_eq(me.state.respawn_tick, WaveDirector.NEVER)
	_kill_wave()
	assert_eq(server.bots.size(), 0, "dead wave bots leave")
	assert_false(server.waves.fighting, "wave cleared")
	assert_eq(world.team_scores[GameMode.HUMANS], 1, "one wave cleared")
	_tick(2)
	assert_true(me.state.alive, "back when the wave is cleared")
	_until_fighting()
	assert_eq(server.waves.wave, 2)
	assert_gt(server.waves.wave_size(2, 2), server.waves.wave_size(1, 2), "waves grow")


func test_everyone_down_loses() -> void:
	_play()
	_until_fighting()
	world._kill(world.players[ServerSession.LOCAL_PLAYER_ID], 0, null, false)
	_tick(2)
	assert_eq(server.phase, MatchPhase.POST_MATCH)
	var results: Array = server.drain_host_events().filter(func(e: Dictionary) -> bool: return e.type == "results")
	assert_eq(results.size(), 1)
	assert_eq(results[0].winner_team, GameMode.WAVE_TEAM)
	assert_eq(results[0].mode, GameMode.WAVES)


func test_clearing_the_last_wave_wins() -> void:
	_play()
	server.waves.wave = Balance.MODES.wave_count - 1
	_until_fighting()
	assert_eq(server.waves.wave, Balance.MODES.wave_count)
	_kill_wave()
	assert_eq(server.phase, MatchPhase.POST_MATCH)
	var results: Array = server.drain_host_events().filter(func(e: Dictionary) -> bool: return e.type == "results")
	assert_eq(results[0].winner_team, GameMode.HUMANS)
	assert_eq(results[0].team_scores[GameMode.HUMANS], Balance.MODES.wave_count)


func test_later_waves_get_harder() -> void:
	server.bot_difficulty = BotBrain.Difficulty.EASY
	assert_eq(server.waves.wave_difficulty(1), BotBrain.Difficulty.EASY)
	assert_gt(server.waves.wave_difficulty(7), BotBrain.Difficulty.EASY)
	assert_eq(server.waves.wave_difficulty(99), BotBrain.Difficulty.INSANE)
	assert_lte(server.waves.wave_size(50, 1), server.max_combatants - 1, "capped by the combatant limit")


func test_wave_status_and_events_go_over_the_wire() -> void:
	var snap := Snapshot.new()
	snap.wave = {"wave": 3, "fighting": true, "left": 4, "next": 0}
	var back := Snapshot.decode(snap.encode({}, []), {})
	assert_eq(back.wave.wave, 3)
	assert_true(back.wave.fighting)
	assert_eq(back.wave.left, 4)
	var plain := Snapshot.decode(Snapshot.new().encode({}, []), {})
	assert_true(plain.wave.is_empty(), "no wave block outside co-op")
	for action in ["start", "cleared"]:
		var w := Wire.Writer.new()
		assert_true(Protocol.write_event(w, {"type": "wave", "id": "x", "action": action, "wave": 5, "tick": 9, "enemies": 6}))
		var e := Protocol.read_event(Wire.Reader.new(w.data()))
		assert_eq(e.action, action)
		assert_eq(e.wave, 5)
