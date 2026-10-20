extends GutTest
## Connection lifecycle (PLAN §3.4, §3.5.1): reconnect tokens, bots giving
## way to humans, combatant caps and host notices, over real ENet.

var server: ServerSession
var port: int
var _clients: Array[ClientSession] = []


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	port = 41000 + randi() % 8000
	server = ServerSession.new()
	add_child_autofree(server)
	assert_eq(server.start(port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	_clients.clear()


func _join(player_name: String, token: int = 0) -> ClientSession:
	var c := ClientSession.new()
	c.player_name = player_name
	c.uuid = "uuid-" + player_name
	c.reconnect_token = token
	add_child_autofree(c)
	assert_eq(c.join("127.0.0.1", port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	_clients.append(c)
	return c


func _wait_predicting(c: ClientSession) -> void:
	await wait_until(func() -> bool: return c.is_predicting(), 5.0)
	assert_true(c.is_predicting(), "%s joined" % c.player_name)


func test_reconnect_token_restores_player_and_score() -> void:
	var a := _join("Alpha")
	await _wait_predicting(a)
	var id := a.local_id
	var token := a.reconnect_token
	assert_ne(token, 0, "welcome carries a reconnect token")
	server.world.scores[id] = 7
	a.leave()
	await wait_until(func() -> bool: return server.clients.is_empty(), 3.0)
	assert_false(server.world.players.has(id), "player removed when the client left")
	var back := _join("Alpha", token)
	await _wait_predicting(back)
	assert_eq(back.local_id, id, "same player id after reconnecting")
	assert_eq(server.world.scores.get(id, 0), 7, "score restored")
	assert_eq(back.reconnect_token, token)


func test_reconnect_takes_over_a_stale_connection() -> void:
	var a := _join("Alpha")
	await _wait_predicting(a)
	var id := a.local_id
	server.world.scores[id] = 3
	# The old connection is still open (as after a short suspension).
	var back := _join("Alpha", a.reconnect_token)
	await _wait_predicting(back)
	assert_eq(back.local_id, id, "the new connection got the same player")
	assert_eq(server.world.scores.get(id, 0), 3)
	assert_eq(server.clients.size(), 1, "the stale connection was dropped")


func test_unknown_token_is_a_new_join() -> void:
	var a := _join("Alpha", 123456789)
	await _wait_predicting(a)
	assert_ne(a.reconnect_token, 123456789, "a fresh token is issued")


func test_bots_give_way_to_humans_and_cap_applies() -> void:
	server.max_combatants = 2
	server.bot_fill = 2
	server.update_bot_fill()
	assert_eq(server.bots.size(), 2)
	var a := _join("Alpha")
	await _wait_predicting(a)
	assert_eq(server.bots.size(), 1, "one dummy left for the human")
	var b := _join("Bravo")
	await _wait_predicting(b)
	assert_eq(server.bots.size(), 0)
	var failed := [""]
	var c := _join("Charlie")
	c.failed.connect(func(reason: String) -> void: failed[0] = reason)
	await wait_until(func() -> bool: return failed[0] != "", 5.0)
	assert_eq(failed[0], "server full", "third human rejected at the cap")
	b.leave()
	await wait_until(func() -> bool: return server.bots.size() == 1, 3.0)
	assert_eq(server.bots.size(), 1, "a dummy fills the free slot again")


func test_host_notice_and_silence() -> void:
	var a := _join("Alpha")
	await _wait_predicting(a)
	assert_lt(a.seconds_silent(), 0.5)
	server.notify_clients(Protocol.Notice.HOST_PAUSED)
	await wait_until(func() -> bool: return a.host_paused, 2.0)
	assert_true(a.host_paused, "client knows the host paused")
	server.process_mode = Node.PROCESS_MODE_DISABLED  # a suspended host sends nothing
	await wait_seconds(1.0)
	assert_gt(a.seconds_silent(), 0.5, "silence is measured")
	server.process_mode = Node.PROCESS_MODE_INHERIT
	server.notify_clients(Protocol.Notice.HOST_RESUMED)
	await wait_until(func() -> bool: return not a.host_paused, 2.0)
	assert_false(a.host_paused)


func test_tdm_reconnect_rejoins_the_same_team() -> void:
	server.game_mode = GameMode.TDM
	server.world.teams_enabled = true
	server.bot_fill = 4
	server.update_bot_fill()
	var a := _join("Alpha")
	await _wait_predicting(a)
	var id := a.local_id
	var token := a.reconnect_token
	var team: int = server.world.players[id].team
	await wait_until(func() -> bool: return a.team_of(id) == team, 3.0)
	assert_eq(a.team_of(id), team, "the client learns its team from the roster")
	a.leave()
	await wait_until(func() -> bool: return server.clients.is_empty(), 3.0)
	# Tip the balance so a fresh join would go to the other team.
	server.world.players.values().filter(func(p: SimPlayer) -> bool: return p.is_bot and p.team != team)[0].team = team
	var back := _join("Alpha", token)
	await _wait_predicting(back)
	assert_eq(back.local_id, id)
	assert_eq(server.world.players[id].team, team, "same team after reconnecting")
