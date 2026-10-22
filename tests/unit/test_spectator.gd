extends GutTest
## Spectator mode (PLAN §2.6): watching a bots-only match from a bot's eyes.
## The spectator keeps the match running like a player would, but takes no
## combatant slot and earns nothing.

const MATCH := preload("res://game/match.tscn")


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_server_runs_the_match_for_a_spectator() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	var server := ServerSession.new()
	add_child_autofree(server)
	assert_eq(server.start(-1, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	server.bot_fill = 4
	server.add_local_spectator()
	assert_eq(server.phase, MatchPhase.COUNTDOWN, "a spectator starts the match")
	assert_eq(server.world.players.size(), 4, "every slot goes to a bot")
	assert_false(server.world.players.has(ServerSession.LOCAL_PLAYER_ID), "no player for the spectator")
	assert_eq(server.combatants(), 4)


func test_offline_match_follows_a_bot_and_switches() -> void:
	var config := MatchConfig.make(MatchConfig.Mode.OFFLINE, "Watcher", 3)
	config.spectate = true
	MatchConfig.pending = config
	var m := MATCH.instantiate()
	add_child_autofree(m)
	await wait_seconds(1.0)
	assert_true(m.spectating())
	assert_eq(m.server.world.players.size(), 4, "1 + 3 bots, all bots")
	assert_true(m.server.bots.has(m.local_id()), "the view follows a bot")
	assert_false(m._visuals.has(m.local_id()), "the watched bot isn't drawn over the view")
	assert_eq(m._visuals.size(), 3)
	assert_false(m.input.enabled, "no input while watching")
	var first: int = m.local_id()
	m._cycle_spectator(1)
	assert_ne(m.local_id(), first, "next player")
	m._cycle_spectator(-1)
	assert_eq(m.local_id(), first, "and back")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	assert_eq(m._spectator_switch(click), 1, "a click (or tap) watches the next player")
	click.button_index = MOUSE_BUTTON_RIGHT
	assert_eq(m._spectator_switch(click), -1)


func test_spectating_earns_no_xp() -> void:
	var config := MatchConfig.make(MatchConfig.Mode.OFFLINE, "Watcher", 1)
	config.spectate = true
	MatchConfig.pending = config
	var m := MATCH.instantiate()
	add_child_autofree(m)
	await wait_seconds(0.5)
	var xp_before := Profile.data.xp()
	var watched: int = m.local_id()
	var row := {"id": watched, "bot": true, "name": "Bot", "score": 25, "team": GameMode.NO_TEAM,
			"ticks_played": 6000, "weapon_kills": {}}
	for k in Protocol.RESULT_COUNTERS:
		row[k] = 0
	var results := {"type": "results", "id": "results-spectate-test", "match_id": 1, "result_id": "spectate-test",
			"winner": watched, "duration_ticks": 6000, "humans": 0, "mode": GameMode.FFA,
			"winner_team": GameMode.NO_TEAM, "team_scores": PackedInt32Array([0, 0]), "players": [row]}
	m._handle_event(results)
	assert_eq(Profile.data.xp(), xp_before, "watching a bot win gives us nothing")
	assert_true(m._results.visible, "but the results still show")
	assert_ne(m._results.title.text, tr("RESULTS_VICTORY").to_upper(), "the bot's win isn't our victory")
