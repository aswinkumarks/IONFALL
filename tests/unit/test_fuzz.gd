extends GutTest
## Fuzz tests (PLAN §5, M5): malformed, truncated and oversized input at every
## entry point a remote player can reach: message decoders, LAN beacons,
## snapshots, handshakes, the lobby, and the transport's ingress limits.
## Nothing may crash, raise script errors or leave invalid state behind.

const ROUNDS := 3000

var rng := RandomNumberGenerator.new()


func before_each() -> void:
	rng.seed = 20261022


func _junk(max_size: int, first: int = -1) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(rng.randi_range(0, max_size))
	for i in data.size():
		data[i] = rng.randi() & 0xFF
	if first >= 0 and data.size() > 0:
		data[0] = first
	return data


func test_decoders_survive_random_bytes() -> void:
	var decoders: Array[Callable] = [Protocol.decode_hello, Protocol.decode_hello_reply, Protocol.decode_commands,
			Protocol.decode_ping, Protocol.decode_pong, Protocol.decode_welcome, Protocol.decode_phase,
			Protocol.decode_roster, Protocol.decode_results, Protocol.decode_notice, Protocol.decode_loadout,
			Protocol.decode_loaded, Protocol.decode_event_message, Protocol.decode_lobby, Protocol.decode_start,
			Protocol.decode_team_pick]
	var types: Array = Protocol.Msg.values()
	var decoded := 0
	for i in ROUNDS:
		var data := _junk(300, types[i % types.size()] if i % 2 == 0 else -1)
		for decode in decoders:
			var out: Variant = decode.call(data)
			if out is Dictionary and not (out as Dictionary).is_empty():
				decoded += 1
	assert_true(true, "%d junk inputs decoded to something; none crashed" % decoded)


func test_lobby_and_start_reject_bad_values() -> void:
	# Valid framing, hostile contents: too many members, bad mode, long names.
	var w := Wire.Writer.new().u8(Protocol.Msg.LOBBY).str8("station").u8(1).u8(10).u8(8).u8(200)
	assert_eq(Protocol.decode_lobby(w.data()), {}, "member count over the limit")
	w = Wire.Writer.new().u8(Protocol.Msg.LOBBY).str8("station").u8(7).u8(10).u8(8).u8(0)
	assert_eq(Protocol.decode_lobby(w.data()), {}, "unknown mode")
	w = Wire.Writer.new().u8(Protocol.Msg.START).str8("x".repeat(200)).u8(0).u8(10)
	assert_eq(Protocol.decode_start(w.data()), {}, "map id too long")
	var ok := Protocol.encode_start("station", 0, 10)
	ok.append(0)
	assert_eq(Protocol.decode_start(ok), {}, "trailing bytes")


func test_snapshots_and_beacons_survive_random_bytes() -> void:
	for i in ROUNDS:
		var snap := Snapshot.decode(_junk(400, Protocol.Msg.SNAPSHOT if i % 2 == 0 else -1), {})
		if snap != null:
			assert_true(snap.entities is Dictionary)
		var beacon := Discovery.decode(_junk(200))
		if beacon != null:
			assert_true(beacon.max_combatants <= Protocol.MAX_PEERS)
	# A real beacon with its magic but random tail.
	var good := Discovery.encode(Discovery.Beacon.new())
	for i in 500:
		var data := good.slice(0, rng.randi_range(0, good.size()))
		data.append_array(_junk(20))
		Discovery.decode(data)
	assert_true(true, "no crash")


func test_lobby_client_ignores_junk_and_keeps_valid_state() -> void:
	var c := LobbySession.new()
	add_child_autofree(c)
	var types := [Protocol.Msg.LOBBY, Protocol.Msg.START, Protocol.Msg.WELCOME, Protocol.Msg.SNAPSHOT]
	watch_signals(c)
	for i in ROUNDS:
		c._done = false  # keep listening as if still connected
		c._on_message(1, _junk(120, types[i % types.size()]))
		assert_true(Maps.has(c.map_id), "map stays a real map")
		assert_true(c.game_mode >= 0 and c.game_mode < GameMode.IDS.size(), "mode stays valid")
		assert_true(c.members.size() <= Protocol.MAX_PEERS)
	for s: String in ["started", "in_match"]:
		for i in get_signal_emit_count(c, s):
			var params: Array = get_signal_parameters(c, s, i)
			if s == "started":
				assert_true(params[0].mode < GameMode.IDS.size())


func test_hello_validators_reject_junk() -> void:
	var lobby := LobbySession.new()
	add_child_autofree(lobby)
	lobby.max_players = 4
	for i in ROUNDS:
		var hello := Protocol.decode_hello(_junk(160))
		if hello.is_empty():
			continue
		assert_ne(lobby._validate_hello(1000 + i, hello), "", "random handshakes are rejected")
	assert_true(lobby._names.is_empty(), "no junk player was admitted")


func test_ingress_limits_drop_floods_and_oversized_packets() -> void:
	var port := 41000 + randi() % 8000
	var host := LobbySession.new()
	add_child_autofree(host)
	assert_eq(host.host("Hosty", 4, port), OK)
	var c := LobbySession.new()
	add_child_autofree(c)
	assert_eq(c.join("127.0.0.1", port, "Flooder", "uuid-flood"), OK)
	await wait_until(func() -> bool: return host.members.size() == 2, 5.0)
	assert_eq(host.members.size(), 2)
	for i in 400:
		var data := PackedByteArray()
		data.resize(Protocol.MAX_CLIENT_PACKET + 1 + rng.randi_range(0, 900) if i % 2 == 0 else rng.randi_range(1, 64))
		for j in data.size():
			data[j] = rng.randi() & 0xFF
		c.transport.send(1, data, Protocol.CH_GAME, false)
	await wait_seconds(1.0)
	assert_gt(host.transport.ingress_drops, 0, "oversized and flooding packets were dropped before decoding")
	assert_eq(host.members.size() <= 2, true, "the host still runs")
