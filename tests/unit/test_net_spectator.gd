extends GutTest
## Network spectators (PLAN §2.7) over real ENet on localhost: a spectator
## gets snapshots of every combatant but has no player, sends no commands,
## takes no combatant slot and does not start the match on its own.

var server: ServerSession
var port: int


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	port = 41000 + randi() % 8000
	server = ServerSession.new()
	add_child_autofree(server)
	assert_eq(server.start(port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)


func _join(spectate: bool, player_name: String) -> ClientSession:
	var c := ClientSession.new()
	c.player_name = player_name
	c.spectate = spectate
	add_child_autofree(c)
	assert_eq(c.join("127.0.0.1", port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	return c


func test_hello_carries_the_spectate_flag() -> void:
	for spectate in [false, true]:
		var hello := Protocol.decode_hello(Protocol.encode_hello("c", "b", "u", "Name", 0, 0, 0, 0, spectate))
		assert_eq(hello.spectate, spectate)


func test_spectator_sees_players_without_playing() -> void:
	var player := _join(false, "Player")
	await wait_until(func() -> bool: return player.is_predicting(), 5.0)
	assert_true(player.is_predicting(), "player joined")
	var watcher := _join(true, "Watcher")
	await wait_until(func() -> bool: return watcher.is_live(), 5.0)
	assert_true(watcher.is_live(), "spectator receives snapshots")
	assert_false(watcher.is_predicting(), "spectator has no player to predict")
	assert_ne(watcher.local_id, 0)
	assert_false(server.world.players.has(watcher.local_id), "no player in the world")
	assert_eq(server.world.players.size(), 1)
	await wait_seconds(0.5)
	assert_true(watcher.remote_states().has(player.local_id), "the player arrives as a remote entity")
	assert_eq(server.combatants(), 1, "the spectator takes no combatant slot")
	for c: ServerSession.Client in server.clients.values():
		if c.spectator:
			assert_eq(c.queue.size(), 0, "no commands from the spectator")
	assert_eq(server.anomalies, 0)


func test_spectator_alone_does_not_start_the_match() -> void:
	var watcher := _join(true, "Watcher")
	await wait_until(func() -> bool: return watcher.is_live(), 5.0)
	assert_true(watcher.is_live())
	assert_eq(server.phase, MatchPhase.WAITING, "a spectator alone does not start the countdown")


func test_spectator_joins_a_full_server() -> void:
	server.max_combatants = 1
	var player := _join(false, "Player")
	await wait_until(func() -> bool: return player.is_predicting(), 5.0)
	var late := _join(false, "Late")
	var failed := [""]
	late.failed.connect(func(reason: String) -> void: failed[0] = reason)
	await wait_until(func() -> bool: return failed[0] != "", 5.0)
	assert_eq(failed[0], "server full", "a second player is turned away")
	var watcher := _join(true, "Watcher")
	await wait_until(func() -> bool: return watcher.is_live(), 5.0)
	assert_true(watcher.is_live(), "spectators have their own limit")
