extends GutTest
## Scoring, attribution, assists, match stats and results (PLAN §2.4, §2.6).

const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")

var world: SimWorld
var a: SimPlayer
var b: SimPlayer
var c: SimPlayer


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	world = SimHarness.make_world()
	add_child_autofree(world)
	await wait_physics_frames(2)
	a = world.add_player(1, SimHarness.loadout(), "A", false)
	b = world.add_player(2, SimHarness.loadout(), "B", false)
	c = world.add_player(3, SimHarness.loadout(), "C", true)
	for p in [a, b, c]:
		p.state.spawn_protection_ticks = 0
	world.step({})
	world.drain_events()


func _deaths() -> Array[Dictionary]:
	return world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "death")


func test_assist_needs_40_damage_from_someone_else() -> void:
	world._damage(c, 2, 45.0, false, PULSE, 1)  # B: assist
	world._damage(c, 3, 10.0, false, PULSE, 1)  # self-damage never assists
	world._damage(c, 1, 300.0, true, PULSE, 2)  # A kills with a headshot
	var d := _deaths()
	assert_eq(d.size(), 1)
	assert_eq(d[0].killer, 1)
	assert_true(d[0].headshot)
	assert_eq(d[0].assists, [2] as Array[int])
	assert_eq(world.scores[1], 1)


func test_small_or_old_damage_is_not_an_assist() -> void:
	world._damage(c, 2, 30.0, false, PULSE, 1)
	for i in Balance.PLAYER.assist_ticks + 1:
		world.step({})
	world._damage(c, 2, 20.0, false, PULSE, 2)
	world._damage(c, 1, 300.0, false, PULSE, 3)
	assert_eq(_deaths()[0].assists.size(), 0, "30 dmg too old, 20 dmg too small")


func test_own_explosive_is_a_suicide_even_after_enemy_damage() -> void:
	world._damage(a, 2, 150.0, false, PULSE, 1)
	world._damage(a, 1, 100.0, false, ARC, 1)
	var d := _deaths()[0]
	assert_true(d.suicide)
	assert_eq(world.scores[1], -1)
	assert_eq(world.scores[2], 0, "the enemy gets no kill")
	assert_eq(d.assists, [2] as Array[int], "the enemy's damage still counts as an assist")


func test_environmental_death_credits_last_enemy_within_5_s() -> void:
	world._damage(a, 2, 30.0, false, PULSE, 1)
	world._damage(a, 3, 30.0, false, PULSE, 1)
	SimHarness.place(a, Vector3(0, SimWorld.KILL_Y - 5.0, 0), 0.0)
	world.step({})
	var d := _deaths()[0]
	assert_true(d.environment)
	assert_eq(d.killer, 3, "the last enemy who did damage")
	assert_eq(world.scores[3], 1)


func test_environmental_death_without_recent_damage_is_a_suicide() -> void:
	SimHarness.place(a, Vector3(0, SimWorld.KILL_Y - 5.0, 0), 0.0)
	world.step({})
	var d := _deaths()[0]
	assert_true(d.suicide)
	assert_eq(world.scores[1], -1)


func test_match_stats_classify_vs_bots_per_event() -> void:
	var stats := MatchStats.new()
	for p in [a, b, c]:
		stats.add_player(p.net_id, p.display_name, p.is_bot, 0)
	world._damage(c, 2, 45.0, false, PULSE, 1)
	world._damage(c, 1, 300.0, false, PULSE, 2)  # A kills bot C, B assists
	world._damage(b, 1, 300.0, true, PULSE, 3)  # A kills human B with a headshot
	world.step({})
	for e in world.drain_events():
		stats.on_event(e)
	var la: MatchStats.Line = stats.lines[1]
	assert_eq([la.kills, la.kills_vs_bots, la.headshot_kills, la.best_streak], [2, 1, 1, 2])
	assert_eq(la.weapon_kills.get(&"pulse_rifle"), 2)
	var lb: MatchStats.Line = stats.lines[2]
	assert_eq([lb.assists, lb.assists_vs_bots, lb.deaths, lb.damage_dealt], [1, 1, 1, 45])


func test_leader_needs_a_unique_top_score() -> void:
	assert_eq(MatchPhase.leader({1: 3, 2: 5, 3: 5}), 0)
	assert_eq(MatchPhase.leader({1: 3, 2: 6, 3: 5}), 2)


func test_results_round_trip() -> void:
	var row := {"id": 7, "bot": false, "name": "Ana", "score": 12, "ticks_played": 3600, "weapon_kills": {&"mag_pistol": 3}}
	for k in Protocol.RESULT_COUNTERS:
		row[k] = 4
	var data := Protocol.encode_results(99, "abc-def", 7, 3000, 2, [row])
	var r := Protocol.decode_results(data)
	assert_eq(r.result_id, "abc-def")
	assert_eq(r.winner, 7)
	assert_eq(r.players[0].name, "Ana")
	assert_eq(r.players[0].weapon_kills, {&"mag_pistol": 3})
	assert_eq(r.players[0].hits, 4)
	assert_true(Protocol.decode_results(data.slice(0, data.size() - 1)).is_empty(), "truncated rejected")


func test_tie_at_time_limit_goes_to_sudden_death_then_decides() -> void:
	var server := ServerSession.new()
	add_child_autofree(server)
	assert_eq(server.start(-1, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	server.add_local_player("Host")
	server.bot_fill = 2
	server.update_bot_fill()
	server._set_phase(MatchPhase.PLAYING, server.world.tick + 2)
	var ids := server.world.scores.keys()
	server.world.scores[ids[0]] = 3
	server.world.scores[ids[1]] = 3
	await wait_physics_frames(4)
	assert_eq(server.phase, MatchPhase.SUDDEN_DEATH, "tied at the limit")
	server.world.scores[ids[1]] = 4
	await wait_physics_frames(2)
	assert_eq(server.phase, MatchPhase.POST_MATCH)
	assert_eq(server.last_winner, ids[1])
	var results := server.drain_host_events().filter(func(e: Dictionary) -> bool: return e.type == "results")
	assert_eq(results.size(), 1, "the host gets results")
	assert_eq(results[0].players.size(), 2)


func test_go_starts_everyone_from_a_fresh_spawn() -> void:
	var server := ServerSession.new()
	add_child_autofree(server)
	assert_eq(server.start(-1, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	server.add_local_player("Host")
	server.bot_fill = 3
	server.update_bot_fill()
	server._set_phase(MatchPhase.COUNTDOWN, server.world.tick + 3)
	# Roaming in the countdown ends up next to each other, protection spent.
	var spot := Vector3(0, 0.05, 16.5)
	for p: SimPlayer in server.world.players.values():
		server.world.teleport(p, spot)
		p.state.spawn_protection_ticks = 0
		spot.x += 1.0
	await wait_until(func() -> bool: return server.phase == MatchPhase.PLAYING, 2.0)
	assert_eq(server.phase, MatchPhase.PLAYING)
	var spawns := TestArenaLayout.spawn_points().map(func(t: Transform3D) -> Vector3: return t.origin)
	for p: SimPlayer in server.world.players.values():
		assert_gt(p.state.spawn_protection_ticks, 0, "%d is protected at GO" % p.net_id)
		var nearest := 1e9
		for o: Vector3 in spawns:
			nearest = minf(nearest, Vector2(o.x - p.state.position.x, o.z - p.state.position.z).length())
		assert_lt(nearest, 1.0, "%d starts at a spawn point" % p.net_id)


func test_phase_messages_carry_the_match_seed() -> void:
	var msg := Protocol.decode_phase(Protocol.encode_phase(7, 2, MatchPhase.PLAYING, 100, 200, 0xDEADBEEF))
	assert_eq(msg.seed, 0xDEADBEEF, "a rematch's new spread seed reaches clients")


## Bots that give way to joining players keep their stats lines, so a full
## match can have more participants than MAX_PEERS; the results must still
## decode (they crashed the host's results screen before).
func test_results_survive_more_participants_than_peers() -> void:
	var server := ServerSession.new()
	add_child_autofree(server)
	assert_eq(server.start(-1, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	var host := server.add_local_player("Host")
	server.max_combatants = Protocol.MAX_PEERS
	server.bot_fill = Protocol.MAX_PEERS
	server.update_bot_fill()
	for i in 8:  # players come and go: their bots leave, new ones fill in
		server.remove_bot(server.bots.keys()[0])
		server.update_bot_fill()
	assert_gt(server.stats.lines.size(), Protocol.MAX_PEERS)
	server._set_phase(MatchPhase.PLAYING, server.world.tick + 1000)
	server._end_match(host.net_id)
	var results := server.drain_host_events().filter(func(e: Dictionary) -> bool: return e.type == "results")
	assert_eq(results.size(), 1)
	assert_true(results[0].has("players"), "the results decoded")
	var ids: Array = results[0].players.map(func(p: Dictionary) -> int: return p.id)
	assert_has(ids, host.net_id, "the host has a row")
