extends GutTest
## Netcode over real ENet on localhost: one ServerSession and one
## ClientSession in this process (PLAN §5 netcode correctness).

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action

var server: ServerSession
var client: ClientSession
var port: int
var script_input: SimHarness.CommandScript
## tick -> Array of actions to press at that tick
var presses_at: Dictionary = {}
var walk_pattern: bool = true


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)
	port = 41000 + randi() % 8000
	server = ServerSession.new()
	add_child_autofree(server)
	assert_eq(server.start(port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	client = ClientSession.new()
	add_child_autofree(client)
	script_input = SimHarness.CommandScript.new()
	presses_at = {}
	client.input_source = _scripted_input
	if gut.get_current_test_object().name == "test_join_under_latency":
		client.transport.conditioner.rtt_ms = 150.0
	assert_eq(client.join("127.0.0.1", port, SimHarness.MOVEMENT, SimHarness.loadout(), TestArenaLayout.spawn_points()), OK)
	await wait_until(func() -> bool: return client.is_predicting(), 5.0)
	if not client.is_predicting():
		gut.p("join stalled: local_id=%d pings=%d snapshot=%s server clients=%d" % [client.local_id,
				client.clock.sample_count(), client.latest_snapshot != null, server.clients.size()])
	assert_true(client.is_predicting(), "client joined and started predicting")


## Scripted movement: walk in a slowly turning circle with periodic sprint.
func _scripted_input(tick: int) -> PlayerCommand:
	var move := Vector2.ZERO
	var held := 0
	if walk_pattern:
		script_input.yaw = fposmod(tick * 0.01, TAU)
		move = Vector2(sin(tick * 0.03) * 0.5, 1.0)
		held = Held.SPRINT if (tick / 120) % 2 == 0 else 0
	return script_input.cmd(tick, move, held, presses_at.get(tick, []))


func _server_player() -> SimPlayer:
	return server.world.get_player(client.local_id)


func test_prediction_without_corrections_on_clean_network() -> void:
	await wait_seconds(1.0)
	client.reset_metrics()
	await wait_seconds(4.0)
	assert_eq(client.visible_corrections, 0, "no visible corrections on a clean network")
	assert_eq(client.snaps, 0)
	var s := _server_player()
	assert_not_null(s)
	assert_gt(s.state.position.distance_to(Vector3.ZERO), 0.0)
	var c: ServerSession.Client = server.clients.values()[0]
	gut.p("corrections=%d (any size), server synthesized=%d" % [client.corrections, c.synthesized])
	assert_eq(c.view_anomalies, 0, "view ticks validated without anomalies")
	var errs := server.view_errors
	gut.p("view error ticks: min %.2f p5 %.2f p50 %.2f p95 %.2f max %.2f (n=%d) interp=%d rtt=%.1f srv_rtt=%.1f" % [
			errs.percentile(0.0), errs.percentile(5.0), errs.percentile(50.0), errs.percentile(95.0), errs.percentile(100.0),
			errs.count(), client.interp_ticks, client.clock.rtt_ms, c.rtt_ms])


func test_three_lost_packets_lose_no_presses() -> void:
	walk_pattern = false
	await wait_seconds(1.0)
	var jump_tick := client.pred_tick + 30
	presses_at[jump_tick] = [Action.JUMP]
	await wait_until(func() -> bool: return client.pred_tick >= jump_tick, 2.0)
	client.transport.conditioner.drop_next_outgoing = 3
	var jumped := false
	for i in 60:
		await wait_physics_frames(1)
		var p := _server_player()
		if p != null and p.state.velocity.y > 1.0:
			jumped = true
			break
	assert_true(jumped, "the server executed the jump despite 3 lost command packets")


func test_corrections_at_100ms_rtt_2pct_loss() -> void:
	client.transport.conditioner.rtt_ms = 100.0
	client.transport.conditioner.jitter_ms = 10.0
	client.transport.conditioner.loss = 0.02
	await wait_seconds(3.0)
	client.reset_metrics()
	await wait_seconds(15.0)
	var per_min := client.visible_corrections / client.minutes_measured()
	gut.p("visible corrections/min=%.2f snaps=%d all corrections=%d rtt=%.0f interp=%d" % [
			per_min, client.snaps, client.corrections, client.clock.rtt_ms, client.interp_ticks])
	assert_lte(per_min, 1.0, "visible corrections <= 1/min (PLAN §3.2)")
	assert_eq(client.snaps, 0, "no snaps outside respawn/teleport")


## Regression (found on Wi-Fi): snapshots that arrive before the server has
## processed any command must not move the prediction tick.
func test_join_under_latency() -> void:
	await wait_seconds(3.0)
	var c: ServerSession.Client = server.clients.values()[0]
	var synth_before := c.synthesized
	await wait_seconds(2.0)
	assert_lt(client.pred_tick, server.world.tick + 60, "prediction tick stays near server time")
	assert_lt(c.synthesized - synth_before, 10, "the server uses the client's own commands")
	assert_gt(c.buffer_avg, 0.5, "commands arrive ahead of time")


## Wi-Fi bunches packets: the server grows the client's command buffer
## instead of synthesizing commands (found on the Mi 11X).
func test_jittery_link_grows_command_buffer() -> void:
	client.transport.conditioner.rtt_ms = 30.0
	client.transport.conditioner.jitter_ms = 40.0
	await wait_seconds(5.0)
	var c: ServerSession.Client = server.clients.values()[0]
	var synth_before := c.synthesized
	client.reset_metrics()
	await wait_seconds(5.0)
	gut.p("target buffer %.2f, avg %.2f, synthesized in 5 s: %d, stalled %d, corrections %d, visible %d" % [
			c.target_buffer, c.buffer_avg, c.synthesized - synth_before, c.stalled, client.corrections, client.visible_corrections])
	assert_gt(c.target_buffer, float(ServerSession.TARGET_BUFFER), "buffer target grew")
	assert_lt(c.synthesized - synth_before, 15, "few synthesized commands once adapted")
	assert_eq(client.visible_corrections, 0, "late commands wait instead of being guessed")


## Wi-Fi power saving holds packets and releases them in a burst: the server
## waits for the late commands instead of guessing (found on the Mi 11X).
func test_command_bursts_cause_no_visible_corrections() -> void:
	client.transport.conditioner.burst_every_ms = 2000
	client.transport.conditioner.burst_hold_ms = 120
	await wait_seconds(4.0)
	var c: ServerSession.Client = server.clients.values()[0]
	var synth_before := c.synthesized
	client.reset_metrics()
	await wait_seconds(10.0)
	gut.p("bursts: stalled %d, synthesized %d, corrections %d, visible %d, target buffer %.1f" % [
			c.stalled, c.synthesized - synth_before, client.corrections, client.visible_corrections, c.target_buffer])
	assert_gt(c.stalled, 0, "the server waited for late commands")
	assert_eq(client.visible_corrections, 0)
	assert_lte(client.corrections, 2, "no guessing, so (almost) nothing to correct")
	assert_lte(c.view_anomalies, 2, "bursts don't trip view-tick validation")


func test_snapshots_keep_decoding_under_heavy_loss() -> void:
	client.transport.conditioner.loss = 0.3
	await wait_seconds(2.0)
	var before := client.latest_snapshot.id
	await wait_seconds(2.0)
	assert_gt(client.latest_snapshot.id, before, "snapshots keep arriving")
	assert_eq(client.undecodable_snapshots, 0, "acked baselines: lost snapshots never break decoding")


func test_view_tick_validation() -> void:
	# Client 100 ms RTT, interp 4: expected = arrival - 3 - 4.
	assert_eq(server.validate_view_tick(493.5, 500.0, 100.0, 4), 493.5, "plausible claim accepted")
	assert_eq(server.validate_view_tick(480.0, 500.0, 100.0, 4), 493.0, "too old: replaced by expected")
	assert_eq(server.validate_view_tick(0.0, 500.0, 100.0, 4), 0.0, "no claim = no rewind")


func test_handshake_rejections() -> void:
	var good := Protocol.decode_hello(Protocol.encode_hello(BuildInfo.compat_hash, "b", "u", "Name"))
	var bad_compat := good.duplicate()
	bad_compat.compat = "something-else"
	assert_ne(server._validate_hello(9001, bad_compat), "")
	var bad_version := good.duplicate()
	bad_version.version = 99
	assert_ne(server._validate_hello(9002, bad_version), "")
	assert_true(Protocol.decode_hello(PackedByteArray([1, 2, 3])).is_empty(), "malformed hello")


func test_fuzzed_client_messages_never_crash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var before := server.anomalies
	for i in 2000:
		var data := PackedByteArray()
		data.resize(rng.randi_range(0, 120))
		for j in data.size():
			data[j] = rng.randi() & 0xFF
		if i % 3 == 0 and data.size() > 0:
			data[0] = [Protocol.Msg.CMD, Protocol.Msg.PING, Protocol.Msg.PONG, Protocol.Msg.LOADED][i % 4]
		server._on_message(server.clients.keys()[0], data)
	assert_gt(server.anomalies, before, "malformed messages counted")
	assert_not_null(_server_player(), "the session survived")
