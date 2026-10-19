class_name ClientSession
extends Node
## Client side of a networked match (PLAN §3.3): clock sync, local player
## prediction + reconciliation, remote interpolation, and the metrics M1b is
## judged on (corrections, bandwidth).

signal joined
signal failed(reason: String)
signal left(reason: String)

const HISTORY_TICKS := 120
const VISIBLE_CORRECTION_M := 0.05
const SNAP_CORRECTION_M := 1.0
const CORRECTION_BLEND_TICKS := 6.0

var transport := Transport.new()
var world: SimWorld  ## client-side world: only the predicted local player
var movement: MovementConfig
var loadout: Array[WeaponData] = []
## func(tick: int) -> PlayerCommand. Set by the presentation (InputAdapter) or a test bot.
var input_source: Callable
var player_name: String = "Player"

var local_id: int = 0
var match_id: int = 0
var phase: int = MatchPhase.WAITING
var phase_seq: int = 0
var phase_ends_tick: int = 0
var match_seed: int = 1
var roster: Array = []
var clock := ClockSync.new()
var interpolator := RemoteInterpolator.new()
var interp_ticks: int = 4
var pred: SimPlayer
var pred_tick: int = 0
var latest_snapshot: Snapshot
var server_state: PlayerSimState  ## latest authoritative owner state
var projectiles: Array = []

# Metrics
var corrections: int = 0
var visible_corrections: int = 0
var snaps: int = 0
var undecodable_snapshots: int = 0
var correction_offset := Vector3.ZERO

var _commands: Dictionary = {}  ## tick -> PlayerCommand
var _predicted: Dictionary = {}  ## tick -> PlayerSimState after that command
var _baselines: Dictionary = {}  ## snapshot id -> {id -> NetEntity}
var _events: Array[Dictionary] = []
var _acc: float = 0.0
var _rate: float = 1.0
var _ready_to_predict: bool = false
var _loaded_sent: bool = false
var _ping_timer: float = 0.0
var _pings_sent: int = 0
var _arrival_jitter := FrameStats.new(60)
var _metrics_start_ms: int = 0


func join(address: String, port: int, movement_config: MovementConfig, weapons: Array[WeaponData], spawns: Array[Transform3D]) -> Error:
	movement = movement_config
	loadout = weapons
	world = SimWorld.new()
	world.name = "ClientWorld"
	world.configure(1, movement, spawns)
	add_child(world)
	add_child(transport)
	transport.connection_failed.connect(func(reason: String) -> void: failed.emit(reason))
	transport.disconnected.connect(func() -> void: left.emit("disconnected"))
	transport.message.connect(_on_message)
	var uuid := "%08x-test" % (randi() & 0xFFFFFFFF)
	return transport.join(address, port, Protocol.encode_hello(BuildInfo.compat_hash, BuildInfo.artifact_id, uuid, player_name))


func leave() -> void:
	transport.close()


func is_predicting() -> bool:
	return _ready_to_predict and pred != null


## Remote players at the current render time.
func remote_states() -> Dictionary:
	return interpolator.sample(render_tick())


func render_tick() -> float:
	return clock.server_time() - interp_ticks


## Fraction of the way to the next prediction tick (for rendering).
func alpha() -> float:
	return clampf(_acc / Sim.TICK_DT, 0.0, 1.0)


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


func minutes_measured() -> float:
	return maxf((Time.get_ticks_msec() - _metrics_start_ms) / 60000.0, 0.0001)


func reset_metrics() -> void:
	corrections = 0
	visible_corrections = 0
	snaps = 0
	_metrics_start_ms = Time.get_ticks_msec()


# --- Per frame ---

func _process(delta: float) -> void:
	if local_id == 0:
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		transport.send(1, Protocol.encode_ping(Time.get_ticks_msec() & 0xFFFFFFFF), Protocol.CH_GAME, false)
		_pings_sent += 1
		_ping_timer = 0.1 if _pings_sent < 6 else 1.0
	if not _loaded_sent and clock.sample_count() >= 3:
		transport.send(1, Protocol.encode_loaded(match_id), Protocol.CH_CONTROL, true)
		_loaded_sent = true
	if not is_predicting():
		return
	correction_offset = correction_offset.move_toward(Vector3.ZERO,
			correction_offset.length() / CORRECTION_BLEND_TICKS * delta * Sim.TICK_RATE + 0.0001)
	_acc += delta * _rate
	var steps := 0
	while _acc >= Sim.TICK_DT and steps < 8:
		_acc -= Sim.TICK_DT
		_predict_tick()
		steps += 1


func _predict_tick() -> void:
	var cmd: PlayerCommand = input_source.call(pred_tick) if input_source.is_valid() else PlayerCommand.new()
	cmd.tick = pred_tick
	cmd.view_tick = maxf(render_tick(), 0.001)
	cmd.interp_ticks = interp_ticks
	_commands[pred_tick] = cmd
	var recent: Array[PlayerCommand] = []
	for t in range(pred_tick - Protocol.CMD_REDUNDANCY + 1, pred_tick + 1):
		if _commands.has(t):
			recent.append(_commands[t])
	var ack := latest_snapshot.id if latest_snapshot != null else 0
	transport.send(1, Protocol.encode_commands(match_id, ack, interp_ticks, recent), Protocol.CH_GAME, false)
	_simulate(cmd, true)
	_predicted[pred_tick] = pred.state.copy()
	_commands.erase(pred_tick - HISTORY_TICKS)
	_predicted.erase(pred_tick - HISTORY_TICKS)
	pred_tick += 1


func _simulate(cmd: PlayerCommand, emit: bool) -> void:
	var executed := ActionInput.consume(pred.state, cmd)
	var shots := PlayerSimulation.step(pred, cmd, executed, match_seed)
	if emit:
		for shot in shots:
			_events.append(_predicted_fire_event(shot))


## A local copy of our own shot, with the same ID the server will use, so the
## effect plays immediately and the server's copy is ignored (PLAN §3.1).
func _predicted_fire_event(shot: WeaponSim.Shot) -> Dictionary:
	var e := {"type": "fire", "id": "%d:%d:%d" % [local_id, pred.entity_gen, shot.action_seq], "shooter": local_id,
			"weapon": shot.weapon.id, "origin": shot.origin, "direction": shot.direction, "predicted": true}
	if not shot.weapon.is_projectile():
		var space := pred.get_world_3d().direct_space_state
		var end := shot.origin + shot.direction * shot.weapon.max_range
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(shot.origin, end, Sim.LAYER_WORLD))
		e["end"] = hit.position if not hit.is_empty() else end
		e["hit_world"] = not hit.is_empty()
		e["hit_player"] = false
	return e


# --- Messages ---

func _on_message(_id: int, data: PackedByteArray) -> void:
	match Protocol.message_type(data):
		Protocol.Msg.SNAPSHOT:
			_on_snapshot(data)
		Protocol.Msg.PONG:
			var pong := Protocol.decode_pong(data)
			if not pong.is_empty():
				clock.on_pong(pong.echo, pong.tick, pong.fraction)
		Protocol.Msg.PING:
			var ping := Protocol.decode_ping(data)
			if not ping.is_empty():
				transport.send(1, Wire.Writer.new().u8(Protocol.Msg.PONG).u32(ping.time).u32(0).f32(0.0).data(),
						Protocol.CH_GAME, false)
		Protocol.Msg.WELCOME:
			var w := Protocol.decode_welcome(data)
			if not w.is_empty():
				local_id = w.id
				match_id = w.match_id
				phase = w.phase
				phase_seq = w.phase_seq
				match_seed = w.seed
				_metrics_start_ms = Time.get_ticks_msec()
				joined.emit()
		Protocol.Msg.PHASE:
			var p := Protocol.decode_phase(data)
			if not p.is_empty():
				match_id = p.match_id
				phase = p.phase
				phase_seq = p.phase_seq
				phase_ends_tick = p.ends
		Protocol.Msg.ROSTER:
			var r := Protocol.decode_roster(data)
			if not r.is_empty():
				roster = r.players
		Protocol.Msg.EVENT:
			var e := Protocol.decode_event_message(data)
			if not e.is_empty():
				_events.append(e)


func _on_snapshot(data: PackedByteArray) -> void:
	var snap := Snapshot.decode(data, _baselines)
	if snap == null:
		undecodable_snapshots += 1
		return
	if snap.match_id != match_id or (latest_snapshot != null and snap.id <= latest_snapshot.id):
		return  # stale match or older than what we have (PLAN §3.3.3)
	transport.stats.on_snapshot(data.size())
	latest_snapshot = snap
	_baselines[snap.id] = snap.entities
	for t in _baselines.keys():
		if t < snap.id - 128:
			_baselines.erase(t)
	interpolator.push(snap.id, snap.entities)
	_arrival_jitter.add(clock.server_time() - snap.id)
	var jitter := _arrival_jitter.percentile(95.0) - _arrival_jitter.percentile(5.0)
	interp_ticks = clampi(roundi(2 * ServerSession.SNAPSHOT_INTERVAL + jitter), 3, 9)
	projectiles = snap.projectiles
	_events.append_array(snap.events)
	# Time dilation (PLAN §3.3.2): run up to 5% faster or slower to keep the
	# server's command buffer at its target, instead of hard resyncs.
	_rate = clampf(1.0 - snap.buffer_delta / 10.0 * 0.02, 0.95, 1.05)
	if snap.owner_state != null:
		server_state = snap.owner_state
		_reconcile(snap)


## PLAN §3.2: restore the authoritative state at the last processed command
## and replay the newer commands. Small differences are blended out visually.
func _reconcile(snap: Snapshot) -> void:
	if pred == null:
		pred = world.add_predicted_player(local_id, snap.owner_gen, loadout)
		pred.restore(snap.owner_state)
		pred_tick = ceili(clock.server_time() + clock.one_way_ticks()) + ServerSession.TARGET_BUFFER + 1
		_ready_to_predict = true
		return
	pred.entity_gen = snap.owner_gen
	var server := snap.owner_state
	var c := snap.last_cmd_tick
	# Keep the prediction a sane distance ahead of the server; resync if not.
	var ahead := pred_tick - c
	if ahead < 0 or ahead > HISTORY_TICKS - 10:
		pred.restore(server)
		pred_tick = maxi(pred_tick, c + 1 + ServerSession.TARGET_BUFFER)
		_commands.clear()
		_predicted.clear()
		return
	var predicted: PlayerSimState = _predicted.get(c)
	if predicted != null and not _differs(predicted, server):
		return
	var before := pred.state.position
	var before_disc := pred.state.discontinuity_gen
	pred.restore(server)
	for t in range(c + 1, pred_tick):
		var cmd: PlayerCommand = _commands.get(t)
		if cmd == null:
			continue
		_simulate(cmd, false)
		_predicted[t] = pred.state.copy()
	corrections += 1
	var error := before.distance_to(pred.state.position)
	if before_disc != pred.state.discontinuity_gen or error > SNAP_CORRECTION_M:
		if before_disc == pred.state.discontinuity_gen:
			snaps += 1
		correction_offset = Vector3.ZERO
	else:
		correction_offset += before - pred.state.position
		if error > VISIBLE_CORRECTION_M:
			visible_corrections += 1


## Prediction-relevant differences (health/shield come from the server only).
static func _differs(a: PlayerSimState, b: PlayerSimState) -> bool:
	return a.position.distance_squared_to(b.position) > 1e-8 or a.velocity.distance_squared_to(b.velocity) > 1e-8 \
			or a.move_state != b.move_state or a.stance != b.stance or a.alive != b.alive \
			or a.weapon_slot != b.weapon_slot or a.action_seq != b.action_seq or a.mag != b.mag \
			or a.reload != b.reload or a.air_jumps_left != b.air_jumps_left or a.switch_ticks != b.switch_ticks
