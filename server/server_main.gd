extends Node
## Dedicated server (PLAN §3.5.2): one ServerSession in the test arena, no
## local player.
##
## Arguments (after `--`): `--port N` (default 47710), `--bots N` fills the match
## with training dummies up to N combatants, `--status-interval S` seconds between status lines,
## `--name NAME` shown in LAN server lists, `--no-discovery` stops beacons, `--smoke-test`
## exits right after startup so CI can verify that the exported server boots.
## Logs go to stderr; stdout is reserved for the managed-mode JSON protocol.

const MOVEMENT := preload("res://data/movement_config.tres")
const ARENA_GAMEPLAY := preload("res://maps/test_arena/gameplay.tscn")

var server: ServerSession
var _status_timer: float = 0.0
var _status_interval: float = 10.0
var _started_ms: int = 0
var _step_ms := FrameStats.new(600)  ## server tick wall time (simulation + snapshots)
var _sim_ms := FrameStats.new(600)  ## of which world.step()


func _ready() -> void:
	printerr("IONFALL server %s starting (engine %s, compat %s)" % [
		BuildInfo.display_string(), BuildInfo.engine_version, BuildInfo.compat_hash,
	])
	var port := Platform.get_user_arg("--port", str(Protocol.DEFAULT_PORT)).to_int()
	var bots := clampi(Platform.get_user_arg("--bots", "0").to_int(), 0, Protocol.MAX_PEERS - 1)
	_status_interval = maxf(Platform.get_user_arg("--status-interval", "10").to_float(), 1.0)
	var gameplay := ARENA_GAMEPLAY.instantiate()
	add_child(gameplay)
	# Static world bodies become queryable after the first physics step.
	await get_tree().physics_frame
	server = ServerSession.new()
	server.name = "Server"
	add_child(server)
	var loadout := Loadouts.ffa()
	var err := server.start(port, MOVEMENT, loadout, gameplay.spawn_points())
	if err != OK:
		printerr("IONFALL server: could not listen on UDP port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	# `--bots N`: dummies fill the match up to N combatants and leave as humans join.
	server.bot_fill = bots
	server.update_bot_fill()
	server.stepped.connect(func() -> void:
		_step_ms.add(server.last_step_usec / 1000.0)
		_sim_ms.add(server.last_sim_usec / 1000.0))
	server.phase_changed.connect(func(p: int) -> void:
		printerr("IONFALL server: phase %s (match %08x)" % [MatchPhase.label_key(p), server.match_id]))
	server.transport.peer_joined.connect(func(id: int) -> void:
		var c: ServerSession.Client = server.clients.get(id)
		printerr("IONFALL server: player joined: %s (id %d)" % [c.name if c else "?", c.player_id if c else 0]))
	server.transport.peer_left.connect(func(id: int) -> void:
		printerr("IONFALL server: peer %d left" % id))
	var server_name := Platform.get_user_arg("--name", "IONFALL server")
	if not Platform.user_args.has("--no-discovery"):
		var advertiser := Discovery.Advertiser.new()
		advertiser.beacon_source = server.beacon.bind(server_name, true, port)
		add_child(advertiser)
	_started_ms = Time.get_ticks_msec()
	printerr("IONFALL server listening on UDP port %d with %d bots" % [port, bots])
	if Platform.user_args.has("--smoke-test"):
		printerr("IONFALL server smoke test OK")
		get_tree().quit(0)


func _process(delta: float) -> void:
	if server == null:
		return
	_status_timer += delta
	if _status_timer < _status_interval:
		return
	_status_timer = 0.0
	printerr(status_line())


## One-line health summary for logs and soak tests.
func status_line() -> String:
	var st := server.transport.stats
	var per_client := PackedStringArray()
	for c: ServerSession.Client in server.clients.values():
		per_client.append("%s rtt %.0f buf %.1f/%.1f stalled %d synth %d view_anom %d" % [c.name, c.rtt_ms, c.buffer_avg, c.target_buffer, c.stalled, c.synthesized, c.view_anomalies])
	return "IONFALL status: up %ds tick %d phase %s clients %d players %d | out %.1f kB/s in %.1f kB/s | snapshot max %d B | anomalies %d ingress_drops %d | step p50 %.2f p99 %.2f ms (sim p50 %.2f p99 %.2f) | rss %.0f MiB" % [
		(Time.get_ticks_msec() - _started_ms) / 1000, server.world.tick, MatchPhase.label_key(server.phase),
		server.clients.size(), server.world.players.size(), st.wire_bytes_out_per_s() / 1000.0,
		st.wire_bytes_in_per_s() / 1000.0, st.max_snapshot, server.anomalies, server.transport.ingress_drops,
		_step_ms.percentile(50.0), _step_ms.percentile(99.0), _sim_ms.percentile(50.0), _sim_ms.percentile(99.0), _rss_mib()] \
		+ ("" if per_client.is_empty() else "\n  " + "\n  ".join(per_client))


## Resident memory from /proc (static-memory counters are debug-only).
static func _rss_mib() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return OS.get_static_memory_usage() / 1048576.0
	# procfs files report size 0: read line by line.
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return line.split(":")[1].strip_edges().to_int() / 1024.0
	return 0.0
