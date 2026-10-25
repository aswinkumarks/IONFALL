extends GutTest
## Team deathmatch (PLAN §2.4, §2.5, §3.4): team scoring, team kills,
## suicides, team assignment and balance, the 50-point win and the result.

const PULSE := preload("res://data/weapons/pulse_rifle.tres")

var server: ServerSession


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	server = ServerSession.new()
	server.game_mode = GameMode.TDM
	add_child_autofree(server)
	assert_eq(server.start(-1, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)


func _fill(bots: int) -> void:
	server.add_local_player("Host")
	server.bot_fill = 1 + bots
	server.update_bot_fill()


func test_teams_balance_and_spawn_on_their_side() -> void:
	_fill(5)
	var counts := server.team_counts()
	assert_eq(counts[0], 3)
	assert_eq(counts[1], 3)
	for p: SimPlayer in server.world.players.values():
		assert_true(p.team == 0 or p.team == 1)
	var roster := Protocol.decode_roster(Protocol.encode_roster(1, server.roster(), server.game_mode, server.world.team_scores))
	assert_eq(roster.mode, GameMode.TDM)
	assert_true(roster.players.all(func(r: Dictionary) -> bool: return r.team < 2), "teams in the roster")


func test_team_scoring_rules() -> void:
	_fill(3)
	var w := server.world
	var mates: Array = []
	var enemies: Array = []
	for p: SimPlayer in w.players.values():
		(mates if p.team == 0 else enemies).append(p)
	var killer: SimPlayer = mates[0]
	w._kill(enemies[0], killer.net_id, PULSE, false)
	assert_eq(w.team_scores[0], 1, "enemy kill: +1 team")
	assert_eq(w.scores[killer.net_id], 1)
	w.friendly_fire = true
	w._kill(mates[1], killer.net_id, PULSE, false)
	assert_eq(w.team_scores[0], 0, "team kill: -1 team")
	assert_eq(w.scores[killer.net_id], 0, "and -1 personal")
	w._kill(enemies[1], 0, null, false)
	assert_eq(w.team_scores[1], 0, "suicide: no team change")
	assert_eq(w.scores[enemies[1].net_id], -1, "-1 personal")


func test_friendly_fire_off_by_default() -> void:
	_fill(3)
	assert_true(server.world.teams_enabled)
	assert_false(server.world.friendly_fire)


func test_team_reaching_50_wins() -> void:
	_fill(3)
	server._set_phase(MatchPhase.PLAYING, server.world.tick + 100000)
	server.world.team_scores[1] = GameMode.score_limit(GameMode.TDM)
	await wait_physics_frames(2)
	assert_eq(server.phase, MatchPhase.POST_MATCH)
	var results := server.drain_host_events().filter(func(e: Dictionary) -> bool: return e.type == "results")
	assert_eq(results.size(), 1)
	assert_eq(results[0].mode, GameMode.TDM)
	assert_eq(results[0].winner_team, 1)
	assert_eq(results[0].team_scores[1], 50)
	var host_row: Dictionary = results[0].players.filter(func(r: Dictionary) -> bool: return r.id == server.local_player_id)[0]
	var profile := ProfileData.fresh()
	profile.apply_results(results[0], server.local_player_id)
	assert_eq(profile.data.stats.wins, 1 if host_row.team == 1 else 0, "a team win counts for its players")


func test_respawn_is_five_seconds() -> void:
	assert_eq(server.world.respawn_ticks, 300)


func test_lobby_teams_seat_players() -> void:
	server.team_plan = {"host-uuid": 1}
	var me := server.add_local_player("Host", 0, 0, 0, "host-uuid")
	assert_eq(me.team, 1, "the host on the team it picked in the lobby")
	server.bot_fill = 4
	server.update_bot_fill()
	assert_eq(server.team_counts(), PackedInt32Array([2, 2]), "bots fill around the picked teams")
