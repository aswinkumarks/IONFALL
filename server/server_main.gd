extends Node
## Dedicated server (PLAN §3.5.2): one ServerSession, no local player.
##
## Arguments (after `--`): `--port N` (default 47710), `--map ID` (maps/maps.gd), `--bots N` fills the match
## with training dummies up to N combatants, `--status-interval S` seconds between status lines,
## `--name NAME` shown in LAN server lists, `--mode ffa|tdm`, `--friendly-fire` (TDM),
## `--bot-difficulty easy|normal|hard|insane`,
## `--no-discovery` stops beacons, `--stop-file PATH` (graceful shutdown, below), `--smoke-test`
## exits right after startup so CI can verify that the exported server boots.
## Logs go to stderr; stdout is reserved for the managed-mode JSON protocol.

const MOVEMENT := preload("res://data/movement_config.tres")

var server: ServerSession
var _status_timer: float = 0.0
var _status_interval: float = 10.0
var _started_ms: int = 0
var _stopping: bool = false
var _stop_file: String = ""
var _stop_poll: float = 0.0
var _step_ms := FrameStats.new(600)  ## server tick wall time (simulation + snapshots)
var _sim_ms := FrameStats.new(600)  ## of which world.step()


func _ready() -> void:
	get_tree().auto_accept_quit = false  # shutdown() quits after telling the clients
	_stop_file = Platform.get_user_arg("--stop-file", OS.get_executable_path().get_base_dir().path_join("ionfall_server.stop"))
	if FileAccess.file_exists(_stop_file):
		DirAccess.remove_absolute(_stop_file)  # left over from a crash
	printerr("IONFALL server %s starting (engine %s, compat %s)" % [
		BuildInfo.display_string(), BuildInfo.engine_version, BuildInfo.compat_hash,
	])
	var port := Platform.get_user_arg("--port", str(Protocol.DEFAULT_PORT)).to_int()
	var bots := clampi(Platform.get_user_arg("--bots", "0").to_int(), 0, Protocol.MAX_PEERS - 1)
	_status_interval = maxf(Platform.get_user_arg("--status-interval", "10").to_float(), 1.0)
	var map := Maps.from_args()
	var gameplay := Maps.gameplay(map)
	add_child(gameplay)
	# Static world bodies become queryable after the first physics step.
	await get_tree().physics_frame
	server = ServerSession.new()
	server.name = "Server"
	server.map_id = map
	server.use_primaries = true
	server.game_mode = GameMode.from_id(Platform.get_user_arg("--mode", "ffa"))
	server.friendly_fire = Platform.user_args.has("--friendly-fire")
	server.bot_difficulty = maxi(BotBrain.DIFFICULTY_IDS.find(Platform.get_user_arg("--bot-difficulty", "normal")), 0)
	add_child(server)
	var loadout := Loadouts.ffa()
	var err := server.start(port, MOVEMENT, loadout, gameplay.spawn_points(), gameplay.pickup_spots())
	if err != OK:
		printerr("IONFALL server: could not listen on UDP port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	var nav := BotNavigation.new()
	nav.name = "BotNavigation"
	add_child(nav)
	nav.build(gameplay)  # async: bots wait until it's ready
	server.bot_nav = nav
	# `--bots N`: bots fill the match up to N combatants and leave as humans join.
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
	_stop_poll += delta
	if _stop_poll >= 1.0:
		_stop_poll = 0.0
		if FileAccess.file_exists(_stop_file):
			DirAccess.remove_absolute(_stop_file)
			shutdown()
	if server == null:
		return
	_status_timer += delta
	if _status_timer < _status_interval:
		return
	_status_timer = 0.0
	printerr(status_line())


## Graceful shutdown (PLAN §3.5.2): the clients are told first, so they
## leave with a clear message instead of timing out, then the server quits.
## Triggered by a close request or the stop file: Godot doesn't hand Unix
## signals to scripts, so `ionfall_server.sh` turns Ctrl+C / SIGTERM into
## the stop file (`--stop-file PATH`, default next to the executable).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


func shutdown() -> void:
	if server == null or _stopping:
		get_tree().quit()
		return
	_stopping = true
	printerr("IONFALL server: shutting down (%d clients)" % server.clients.size())
	server.notify_clients(Protocol.Notice.SERVER_SHUTDOWN)
	await get_tree().create_timer(0.5).timeout  # let the notice leave
	server.transport.close()
	printerr("IONFALL server: stopped")
	get_tree().quit()


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
