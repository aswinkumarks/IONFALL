extends GutTest
## Browser-ready hosting (PLAN §3.20): one server serves an ENet client and
## a WebSocket client (what a browser uses) at once through CompositePeer.

var server: ServerSession
var port: int


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	# Random ports can still be taken (a TCP port in TIME_WAIT from an
	# earlier test): try a few.
	var err := FAILED
	for attempt in 5:
		port = 41000 + randi() % 8000
		server = ServerSession.new()
		server.transport.web_port = port + 1
		add_child_autofree(server)
		err = server.start(port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points())
		if err == OK:
			break
		server.queue_free()
	assert_eq(err, OK)
	assert_true(server.transport.api.multiplayer_peer is CompositePeer)


func _join(web: bool, player_name: String) -> ClientSession:
	var c := ClientSession.new()
	c.player_name = player_name
	add_child_autofree(c)
	var peer: MultiplayerPeer = null
	if web:
		var ws := WebSocketMultiplayerPeer.new()
		assert_eq(ws.create_client("ws://127.0.0.1:%d" % (port + 1)), OK)
		peer = ws
	assert_eq(c.join("127.0.0.1", port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points(), peer), OK)
	return c


func test_enet_and_websocket_clients_play_together() -> void:
	var native := _join(false, "Native")
	var browser := _join(true, "Browser")
	await wait_until(func() -> bool: return native.is_predicting() and browser.is_predicting(), 6.0)
	assert_true(native.is_predicting(), "ENet client plays")
	assert_true(browser.is_predicting(), "WebSocket client plays")
	assert_ne(native.local_id, browser.local_id)
	assert_eq(server.world.players.size(), 2)
	var composite: CompositePeer = server.transport.api.multiplayer_peer
	var kinds := {}
	for c: ServerSession.Client in server.clients.values():
		kinds[composite.adapter_of(c.id).get_class()] = true
	assert_eq(kinds.keys().size(), 2, "one client on each transport: %s" % [kinds.keys()])
	await wait_seconds(0.5)
	assert_true(native.remote_states().has(browser.local_id), "the native client sees the browser player")
	assert_true(browser.remote_states().has(native.local_id), "the browser client sees the native player")
	assert_eq(server.anomalies, 0)


func test_websocket_client_leaving_frees_its_player() -> void:
	var browser := _join(true, "Browser")
	await wait_until(func() -> bool: return browser.is_predicting(), 6.0)
	assert_eq(server.world.players.size(), 1)
	browser.leave()
	await wait_until(func() -> bool: return server.world.players.is_empty(), 3.0)
	assert_true(server.world.players.is_empty(), "the server saw exactly one disconnect")
	assert_eq(server.clients.size(), 0)


func test_websocket_client_goes_through_the_handshake() -> void:
	var ws := WebSocketMultiplayerPeer.new()
	assert_eq(ws.create_client("ws://127.0.0.1:%d" % (port + 1)), OK)
	var transport := Transport.new()
	add_child_autofree(transport)
	var failed := [""]
	transport.connection_failed.connect(func(reason: String) -> void: failed[0] = reason)
	transport.join_peer(ws, Protocol.encode_hello("wrong-compat", "b", "u", "Name"))
	await wait_until(func() -> bool: return failed[0] != "", 5.0)
	assert_string_contains(failed[0], "version mismatch")
	assert_eq(server.clients.size(), 0, "never admitted")


func test_websocket_lobby_member_gets_start() -> void:
	var lobby := LobbySession.new()
	lobby.transport.web_port = port + 3
	add_child_autofree(lobby)
	assert_eq(lobby.host("Hosty", 4, port + 2), OK)
	var ws := WebSocketMultiplayerPeer.new()
	assert_eq(ws.create_client("ws://127.0.0.1:%d" % (port + 3)), OK)
	var member := LobbySession.new()
	add_child_autofree(member)
	assert_eq(member.join("127.0.0.1", port + 2, "Browser", "uuid-b", ws), OK)
	await wait_until(func() -> bool: return member.members.size() == 2, 5.0)
	assert_eq(member.members.size(), 2, "browser member listed")
	watch_signals(member)
	lobby.start()
	await wait_seconds(0.5)
	lobby.leave()  # as the lobby screen does before opening the match
	await wait_until(func() -> bool: return get_signal_emit_count(member, "started") > 0, 3.0)
	assert_signal_emitted(member, "started")
	assert_signal_not_emitted(member, "closed")


func test_browser_commands_at_30_hz_keep_prediction_clean() -> void:
	var browser := _join(true, "Browser")
	await wait_until(func() -> bool: return browser.is_predicting(), 6.0)
	assert_true(browser.transport.is_stream_client())
	var c: ServerSession.Client = server.clients.values()[0]
	assert_true(server.transport.is_stream(c.id))
	await wait_seconds(1.0)
	browser.reset_metrics()
	await wait_seconds(2.0)
	var rate := browser.transport.stats.packets_out_per_s
	assert_between(rate, 25, 40, "about 30 command packets a second (plus pings)")
	assert_eq(browser.visible_corrections, 0, "no visible corrections at 30 Hz commands")
	assert_lt(c.synthesized, 10, "the server rarely has to guess a command")
	gut.p("corrections=%d synthesized=%d stalled=%d packets/s=%d" % [browser.corrections, c.synthesized, c.stalled, rate])


class BackedUpTransport:
	extends Transport
	var backlog: int = 0

	func is_stream(_id: int) -> bool:
		return true

	func buffered_bytes(_id: int) -> int:
		return backlog


func test_backed_up_stream_coalesces_then_resyncs_then_drops() -> void:
	var s := ServerSession.new()
	var t := BackedUpTransport.new()
	s.transport = t
	var c := ServerSession.Client.new()
	c.sent = {5: {}}
	assert_true(s._stream_ready(c), "an empty queue sends")
	t.backlog = ServerSession.STREAM_BACKLOG_BYTES + 1
	assert_false(s._stream_ready(c), "a backed-up queue skips the snapshot")
	assert_eq(c.coalesced, 1)
	c.backlog_since_ms = Time.get_ticks_msec() - ServerSession.STREAM_RESYNC_MS - 10
	assert_false(s._stream_ready(c))
	assert_true(c.resync, "a long backlog asks for a full state")
	t.backlog = 0
	assert_true(s._stream_ready(c))
	assert_true(c.sent.is_empty(), "no baseline: the next snapshot is full")
	assert_eq(c.backlog_since_ms, 0)
	t.free()
	s.free()


## Under TCP loss (PLAN §3.20 rule 4). Run inside a network namespace with
## netem on loopback, e.g.:
##   unshare -rn sh -c 'ip link set lo up; tc qdisc add dev lo root netem delay 40ms loss 2%;
##       IONFALL_NETEM=1 godot --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json \
##       -gselect=test_composite_peer.gd -gunit_test_name=tcp_loss -gexit'
func test_browser_stays_playable_under_tcp_loss() -> void:
	if OS.get_environment("IONFALL_NETEM") != "1":
		pass_test("needs netem (see the comment above)")
		return
	var browser := _join(true, "Browser")
	await wait_until(func() -> bool: return browser.is_predicting(), 10.0)
	assert_true(browser.is_predicting())
	await wait_seconds(1.0)
	browser.reset_metrics()
	await wait_seconds(10.0)
	var c: ServerSession.Client = server.clients.values()[0] if not server.clients.is_empty() else null
	assert_not_null(c, "still connected after 10 s of loss")
	if c != null:
		gut.p("corrections=%d visible=%d snaps=%d coalesced=%d synthesized=%d stalled=%d rtt=%.0f" % [
				browser.corrections, browser.visible_corrections, browser.snaps, c.coalesced, c.synthesized, c.stalled,
				browser.clock.rtt_ms])
		assert_lt(browser.snaps, 3, "no more than the odd snap correction")
