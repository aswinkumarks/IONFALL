extends Node
## Dedicated server (PLAN §3.5.2): one ServerSession in the test arena, no
## local player.
##
## Arguments (after `--`): `--port N` (default 47710), `--bots N` training
## dummies, `--status-interval S` seconds between status lines, `--smoke-test`
## exits right after startup so CI can verify that the exported server boots.
## Logs go to stderr; stdout is reserved for the managed-mode JSON protocol.

const MOVEMENT := preload("res://data/movement_config.tres")
const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")
const ARENA_GAMEPLAY := preload("res://maps/test_arena/gameplay.tscn")

var server: ServerSession
var _status_timer: float = 0.0
var _status_interval: float = 10.0
var _started_ms: int = 0
var _step_ms := FrameStats.new(600)  ## server tick wall time (simulation + snapshots)


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
	var loadout: Array[WeaponData] = [PULSE, ARC]
	var err := server.start(port, MOVEMENT, loadout, gameplay.spawn_points())
	if err != OK:
		printerr("IONFALL server: could not listen on UDP port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	for i in bots:
		server.add_bot("Dummy %d" % (i + 1), TargetDummyDriver.new(i * 50))
	server.stepped.connect(func() -> void: _step_ms.add(server.last_step_usec / 1000.0))
	server.phase_changed.connect(func(p: int) -> void:
		printerr("IONFALL server: phase %s (match %08x)" % [MatchPhase.label_key(p), server.match_id]))
	server.transport.peer_joined.connect(func(id: int) -> void:
		var c: ServerSession.Client = server.clients.get(id)
		printerr("IONFALL server: player joined: %s (id %d)" % [c.name if c else "?", c.player_id if c else 0]))
	server.transport.peer_left.connect(func(id: int) -> void:
		printerr("IONFALL server: peer %d left" % id))
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
	return "IONFALL status: up %ds tick %d phase %s clients %d players %d | out %.1f kB/s in %.1f kB/s | snapshot max %d B | anomalies %d ingress_drops %d | step p50 %.2f p99 %.2f ms | mem %.0f MiB" % [
		(Time.get_ticks_msec() - _started_ms) / 1000, server.world.tick, MatchPhase.label_key(server.phase),
		server.clients.size(), server.world.players.size(), st.wire_bytes_out_per_s() / 1000.0,
		st.wire_bytes_in_per_s() / 1000.0, st.max_snapshot, server.anomalies, server.transport.ingress_drops,
		_step_ms.percentile(50.0), _step_ms.percentile(99.0), OS.get_static_memory_usage() / 1048576.0]
