extends GutTest
## Pre-match lobby (LobbySession): members, host-only settings, teams and
## START, over real ENet; and the LOBBY / START / TEAM_PICK wire formats.

var host: LobbySession
var port: int


func before_each() -> void:
	port = 41000 + randi() % 8000
	host = LobbySession.new()
	add_child_autofree(host)
	assert_eq(host.host("Hosty", 4, port), OK)


func _join(player_name: String) -> LobbySession:
	var c := LobbySession.new()
	add_child_autofree(c)
	assert_eq(c.join("127.0.0.1", port, player_name, "uuid-" + player_name), OK)
	return c


func test_lobby_and_start_round_trip() -> void:
	var members := [{"id": 1, "name": "Hosty", "host": true, "team": 0, "ping": 0},
			{"id": 123456789, "name": "Alpha", "host": false, "team": 1, "ping": 37}]
	var l := Protocol.decode_lobby(Protocol.encode_lobby("spire", GameMode.TDM, 15, 8, members))
	assert_eq(l.map, "spire")
	assert_eq(l.mode, GameMode.TDM)
	assert_eq(l.minutes, 15)
	assert_eq(l.max, 8)
	assert_eq(l.members, members)
	var s := Protocol.decode_start(Protocol.encode_start("station", GameMode.FFA, 5))
	assert_eq([s.map, s.mode, s.minutes], ["station", GameMode.FFA, 5])
	assert_eq(Protocol.decode_lobby(PackedByteArray([Protocol.Msg.LOBBY, 3])), {}, "truncated lobby rejected")


func test_players_see_members_and_host_settings() -> void:
	var a := _join("Alpha")
	var b := _join("Bravo")
	await wait_until(func() -> bool: return b.members.size() == 3 and a.members.size() == 3, 5.0)
	assert_eq(a.members.map(func(m: Dictionary) -> String: return m.name), ["Hosty", "Alpha", "Bravo"])
	assert_true(a.members[0].host)
	host.configure("spire", GameMode.TDM, 20)
	await wait_until(func() -> bool: return b.map_id == "spire" and b.minutes == 20, 3.0)
	assert_eq([b.map_id, b.game_mode, b.minutes, b.max_players], ["spire", GameMode.TDM, 20, 4])
	a.leave()
	await wait_until(func() -> bool: return b.members.size() == 2, 5.0)
	assert_eq(host.members.size(), 2, "a player who leaves is removed")


func test_start_reaches_every_player() -> void:
	var a := _join("Alpha")
	await wait_until(func() -> bool: return a.members.size() == 2, 5.0)
	host.configure("spire", GameMode.FFA, 5)
	watch_signals(a)
	watch_signals(host)
	host.start()
	await wait_until(func() -> bool: return get_signal_emit_count(a, "started") > 0, 3.0)
	assert_signal_emitted_with_parameters(a, "started", [{"map": "spire", "mode": GameMode.FFA, "minutes": 5}])
	assert_signal_emitted(host, "started")
	assert_signal_not_emitted(a, "closed", "starting isn't a disconnect")


func test_full_lobby_rejects_and_unknown_settings_fall_back() -> void:
	var joined: Array[LobbySession] = []
	for n in ["Alpha", "Bravo", "Charlie"]:
		joined.append(_join(n))
	await wait_until(func() -> bool: return host.members.size() == 4, 5.0)
	var late := _join("Delta")
	watch_signals(late)
	await wait_until(func() -> bool: return get_signal_emit_count(late, "closed") > 0, 5.0)
	assert_signal_emitted_with_parameters(late, "closed", ["server full"])
	host.configure("nowhere", 9, 7)
	assert_eq([host.map_id, host.game_mode, host.minutes], [Maps.DEFAULT, GameMode.FFA, LobbySession.DEFAULT_MINUTES])


func test_lobby_carries_the_bot_settings() -> void:
	var members := [{"id": 1, "name": "Host", "host": true, "team": 0, "ping": 0}]
	var l := Protocol.decode_lobby(Protocol.encode_lobby("foundry", GameMode.CTF, 10, 16, members, 7, 2, true))
	assert_eq(l.bots, 7)
	assert_eq(l.bot_difficulty, 2)
	assert_true(l.friendly_fire)
	assert_true(Protocol.decode_lobby(Protocol.encode_lobby("foundry", GameMode.CTF, 10, 16, members, 16)).is_empty(),
			"more bots than places is refused")


func test_bot_counts_stay_inside_the_host_cap() -> void:
	var c := MatchConfig.make(MatchConfig.Mode.HOST, "Host")
	assert_eq(c.max_bots(), c.max_combatants() - 1)
	assert_eq(c.clamp_bots(99, true), c.max_bots())
	assert_eq(c.clamp_bots(0, true), 0, "a lobby can have no bots")
	assert_eq(c.clamp_bots(0, false), 1, "single player needs someone to fight")
	assert_true(MatchConfig.friendly_fire_applies(GameMode.TDM))
	assert_true(MatchConfig.friendly_fire_applies(GameMode.CTF))
	assert_false(MatchConfig.friendly_fire_applies(GameMode.FFA))
	assert_false(MatchConfig.friendly_fire_applies(GameMode.WAVES))


func _teams(s: LobbySession) -> Array:
	return s.members.map(func(m: Dictionary) -> int: return m.team)


func test_joiners_fill_the_smaller_team_and_can_switch() -> void:
	host.configure("station", GameMode.TDM, 10)
	var a := _join("Alpha")
	var b := _join("Bravo")
	await wait_until(func() -> bool: return b.members.size() == 3, 5.0)
	assert_eq(_teams(host), [0, 1, 0], "each joiner on the smaller team")
	assert_eq(b.team_of(b.my_id()), 0, "a member knows its own team")
	b.set_team(b.my_id(), 1)
	await wait_until(func() -> bool: return _teams(a) == [0, 1, 1], 3.0)
	assert_eq(_teams(host), [0, 1, 1], "a player switches itself")
	a.set_team(b.my_id(), 0)
	await wait_frames(10)
	assert_eq(_teams(host), [0, 1, 1], "but nobody else")
	host.set_team(b.my_id(), 0)
	assert_eq(_teams(host), [0, 1, 0], "the host moves anyone")


func test_a_full_team_takes_nobody_more() -> void:
	host.configure("station", GameMode.TDM, 10)  # 4 places: 2 a team
	var a := _join("Alpha")
	var b := _join("Bravo")
	await wait_until(func() -> bool: return host.members.size() == 3, 5.0)
	assert_eq(host.team_cap(), 2)
	host.set_team(LobbySession.HOST_ID, 1)
	assert_eq(_teams(host), [1, 1, 0], "team 1 had room")
	host.set_team(b.my_id(), 1)
	assert_eq(_teams(host), [1, 1, 0], "now it is full")
	await wait_until(func() -> bool: return _teams(a) == [1, 1, 0], 3.0)
	assert_eq(_teams(a), [1, 1, 0], "members see the move")


func test_the_team_plan_seats_players_by_uuid() -> void:
	host.host_uuid = "uuid-Hosty"
	var a := _join("Alpha")
	await wait_until(func() -> bool: return host.members.size() == 2, 5.0)
	host.set_team(a.my_id(), 0)
	assert_eq(host.team_plan_now(), {"uuid-Hosty": 0, "uuid-Alpha": 0})
	assert_true(LobbySession.has_teams(GameMode.CTF))
	assert_false(LobbySession.has_teams(GameMode.WAVES), "co-op: one team of humans")
	assert_eq(Protocol.decode_team_pick(Protocol.encode_team_pick(1)), 1)
	assert_eq(Protocol.decode_team_pick(PackedByteArray([Protocol.Msg.TEAM_PICK, 2])), -1, "only two teams")


func test_back_from_a_match_players_keep_their_teams() -> void:
	var again := LobbySession.new()
	add_child_autofree(again)
	again.team_plan = {"uuid-Alpha": 1, "uuid-Bravo": 1}
	var p := port + 1
	assert_eq(again.host("Hosty", 8, p), OK)
	for n in ["Alpha", "Bravo"]:
		var c := LobbySession.new()
		add_child_autofree(c)
		c.join("127.0.0.1", p, n, "uuid-" + n)
	await wait_until(func() -> bool: return again.members.size() == 3, 5.0)
	assert_eq(_teams(again), [0, 1, 1])


func test_the_host_removes_a_player_who_cannot_return() -> void:
	var a := _join("Alpha")
	var b := _join("Bravo")
	await wait_until(func() -> bool: return b.members.size() == 3, 5.0)
	watch_signals(a)
	host.kick(a.my_id())
	assert_eq(host.members.size(), 2, "off the list at once")
	await wait_until(func() -> bool: return get_signal_emit_count(a, "closed") > 0, 3.0)
	assert_signal_emitted_with_parameters(a, "closed", ["LOBBY_KICKED"])
	await wait_until(func() -> bool: return b.members.size() == 2, 3.0)
	assert_eq(b.members.map(func(m: Dictionary) -> String: return m.name), ["Hosty", "Bravo"])
	var again := _join("Alpha")
	watch_signals(again)
	await wait_until(func() -> bool: return get_signal_emit_count(again, "closed") > 0, 5.0)
	assert_signal_emitted_with_parameters(again, "closed", ["LOBBY_KICKED"])  # refused when rejoining
	b.kick(LobbySession.HOST_ID)
	assert_eq(host.members.size(), 2, "only the host removes players")


func test_the_host_names_and_colours_the_teams() -> void:
	var a := _join("Alpha")
	await wait_until(func() -> bool: return a.members.size() == 2, 5.0)
	host.set_team_style(0, "  Wolves\n", 3)
	await wait_until(func() -> bool: return a.team_names[0] == "Wolves", 3.0)
	assert_eq(a.team_colors, PackedInt32Array([3, 1]))
	assert_eq(GameMode.team_name(0, a.team_names), "Wolves")
	assert_eq(GameMode.team_name(1, a.team_names), tr("TEAM_ORANGE"), "unnamed: the default")
	host.set_team_style(1, "Ravens", 3)
	assert_eq(host.team_colors, PackedInt32Array([3, 1]), "both teams can't share a colour")
	assert_eq(host.team_names[1], "Ravens")
	a.set_team_style(0, "Hijack", 5)
	assert_eq(a.team_names[0], "Wolves", "only the host styles teams")
	var w := Protocol.decode_welcome(Protocol.encode_welcome(2, 1, 0, 0, 0, 0, "station", 0,
			PackedStringArray(["Wolves", ""]), PackedInt32Array([3, 1])))
	assert_eq(w.team_names, PackedStringArray(["Wolves", ""]))
	assert_eq(w.team_colors, PackedInt32Array([3, 1]))
	assert_eq(GameMode.clean_team_colors(PackedInt32Array([2, 2])), GameMode.DEFAULT_TEAM_COLORS)
	assert_eq(GameMode.clean_team_colors(PackedInt32Array([0, 99])), GameMode.DEFAULT_TEAM_COLORS)
	assert_eq(GameMode.clean_team_name("x".repeat(40)).length(), GameMode.MAX_TEAM_NAME)


func test_members_see_each_others_latency() -> void:
	var a := _join("Alpha")
	var b := _join("Bravo")
	await wait_until(func() -> bool: return b.members.size() == 3, 5.0)
	await wait_until(func() -> bool: return b.members.all(func(m: Dictionary) -> bool: return m.host or m.ping > 0), 5.0)
	assert_eq(b.members[0].ping, 0, "the host has no latency to itself")
	for m: Dictionary in b.members.slice(1):
		assert_between(m.ping, 1, 1000, "%s's round trip to the host" % m.name)
	assert_eq(a.members.size(), 3)
