extends GutTest
## The host's bot count (MatchConfig.bots → ServerSession.bot_count): that
## many bots stay as humans join, giving way only when the match is full.

var server: ServerSession


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	server = ServerSession.new()
	add_child_autofree(server)
	assert_eq(server.start(-1, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)


## A joined human, as the transport would add one.
func _join(peer: int) -> void:
	var c := ServerSession.Client.new()
	c.id = peer
	c.loaded = true
	server.clients[peer] = c
	server.update_bot_fill()


func test_bots_stay_as_humans_join() -> void:
	server.max_combatants = 6
	server.bot_count = 2
	server.add_local_player("Host")
	assert_eq(server.bots.size(), 2, "the host's two bots")
	_join(11)
	_join(12)
	assert_eq(server.bots.size(), 2, "still two with three humans")


func test_bots_give_way_when_full() -> void:
	server.max_combatants = 4
	server.bot_count = 3
	server.add_local_player("Host")
	assert_eq(server.bots.size(), 3)
	_join(11)
	assert_eq(server.bots.size(), 2, "one place for the new human")
	_join(12)
	_join(13)
	assert_eq(server.bots.size(), 0, "a full match of humans")
	server.clients.erase(13)
	server.update_bot_fill()
	assert_eq(server.bots.size(), 1, "a bot takes the place back")


func test_no_bots_when_the_host_picks_none() -> void:
	server.bot_count = 0
	server.add_local_player("Host")
	_join(11)
	assert_eq(server.bots.size(), 0)
