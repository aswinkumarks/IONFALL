extends GutTest
## Pre-match lobby (LobbySession): members, host-only settings and START,
## over real ENet; and the LOBBY / START wire formats.

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
	var members := [{"name": "Hosty", "host": true}, {"name": "Alpha", "host": false}]
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
