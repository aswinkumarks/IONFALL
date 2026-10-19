extends Node
## Headless test clients (PLAN §5, M1b soak): N ClientSessions in one process,
## each driven by WanderInput, joined to a server. Prints a status line every
## interval and a verdict at the end.
##
## Run: godot --headless -- --test-clients 8 --join 127.0.0.1 [--port N]
##      [--duration S] [--status-interval S]
## Exit code 0 when every client stayed connected with clean snapshots.

const MOVEMENT := preload("res://data/movement_config.tres")
const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")
const ARENA_GAMEPLAY := preload("res://maps/test_arena/gameplay.tscn")

var clients: Array[ClientSession] = []
var failures: PackedStringArray = []
var _duration: float = 0.0
var _elapsed: float = 0.0
var _status_interval: float = 30.0
var _status_timer: float = 0.0


func _ready() -> void:
	var count := clampi(Platform.get_user_arg("--test-clients", "8").to_int(), 1, Protocol.MAX_PEERS)
	var address := Platform.get_user_arg("--join", "127.0.0.1")
	var port := Platform.get_user_arg("--port", str(Protocol.DEFAULT_PORT)).to_int()
	_duration = Platform.get_user_arg("--duration", "0").to_float()
	_status_interval = maxf(Platform.get_user_arg("--status-interval", "30").to_float(), 1.0)
	var gameplay := ARENA_GAMEPLAY.instantiate()
	add_child(gameplay)
	await get_tree().physics_frame
	var loadout: Array[WeaponData] = [PULSE, ARC]
	printerr("IONFALL test clients: %d joining %s:%d" % [count, address, port])
	for i in count:
		var c := ClientSession.new()
		c.name = "TestClient%d" % (i + 1)
		c.player_name = "Test %d" % (i + 1)
		var bot := WanderInput.new(1000 + i)
		c.input_source = bot.command_for
		add_child(c)
		var index := i
		c.failed.connect(func(reason: String) -> void: _fail(index, "failed: " + reason))
		c.left.connect(func(reason: String) -> void: _fail(index, "left: " + reason))
		var err := c.join(address, port, MOVEMENT, loadout, gameplay.spawn_points())
		if err != OK:
			_fail(i, "join error %s" % error_string(err))
		clients.append(c)
		# Stagger joins like real players.
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(3.0).timeout
	for c in clients:
		c.reset_metrics()


func _process(delta: float) -> void:
	if clients.is_empty():
		return
	_elapsed += delta
	_status_timer += delta
	if _status_timer >= _status_interval:
		_status_timer = 0.0
		printerr(status_line())
	if _duration > 0.0 and _elapsed >= _duration:
		set_process(false)
		printerr(status_line())
		var ok := failures.is_empty()
		for c in clients:
			ok = ok and c.is_predicting() and c.undecodable_snapshots == 0
		printerr("IONFALL test clients: %s after %.0f s%s" % ["PASS" if ok else "FAIL", _elapsed,
				"" if failures.is_empty() else " (" + "; ".join(failures) + ")"])
		for c in clients:
			c.leave()
		get_tree().quit(0 if ok else 1)


func status_line() -> String:
	var predicting := 0
	var corrections := 0
	var visible := 0
	var snaps := 0
	var bad := 0
	var minutes := 0.0001
	var rtt := 0.0
	var max_snapshot := 0
	var bytes_in := 0
	for c in clients:
		predicting += 1 if c.is_predicting() else 0
		corrections += c.corrections
		visible += c.visible_corrections
		snaps += c.snaps
		bad += c.undecodable_snapshots
		minutes = maxf(minutes, c.minutes_measured())
		rtt = maxf(rtt, c.clock.rtt_ms)
		max_snapshot = maxi(max_snapshot, c.transport.stats.max_snapshot)
		bytes_in += c.transport.stats.wire_bytes_in_per_s()
	return "IONFALL clients: up %ds predicting %d/%d | corrections %d visible %d (%.2f/min/client) snaps %d bad_snapshots %d | max rtt %.0f ms | snapshot max %d B | in %.1f kB/s total | failures %d" % [
		int(_elapsed), predicting, clients.size(), corrections, visible, visible / minutes / clients.size(), snaps, bad,
		rtt, max_snapshot, bytes_in / 1000.0, failures.size()]


func _fail(index: int, reason: String) -> void:
	var line := "client %d %s" % [index + 1, reason]
	failures.append(line)
	printerr("IONFALL test clients: " + line)
