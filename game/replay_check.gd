class_name ReplayCheck
extends Node
## Cross-platform replay check (PLAN §3.2, M1b exit): a fixed 60-second,
## 4-player session in the test arena (movement, combat, deaths, respawns),
## driven by seeded WanderInput. Prints player positions every second with
## the prefix "REPLAY" so runs on different platforms can be compared with
## tools/compare_replay.py. The PLAN bound is ≤ 1 cm divergence.
##
## Desktop: `godot -- --replay-check` (prints and quits). Android: the
## diagnostics overlay's button; read the result with `adb logcat -s godot`.

signal finished(summary: String)

const VERSION := 1
const TICKS := 3600
const PLAYERS := 4
const CHECKPOINT_TICKS := 60
const SEED := 20261019
const MOVEMENT := preload("res://data/movement_config.tres")
const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")
const ARENA_GAMEPLAY := preload("res://maps/test_arena/gameplay.tscn")


func _ready() -> void:
	var arena := ARENA_GAMEPLAY.instantiate()
	add_child(arena)
	# Static world bodies become queryable after the first physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := SimWorld.new()
	world.configure(SEED, MOVEMENT, TestArenaLayout.spawn_points())
	add_child(world)
	var loadout: Array[WeaponData] = [PULSE, ARC]
	var inputs := {}
	for i in PLAYERS:
		var id := i + 1
		world.add_player(id, loadout, "Replay %d" % id, true)
		inputs[id] = WanderInput.new(SEED + id)
	var start := Time.get_ticks_msec()
	var deaths := 0
	var shots := 0
	var lines := PackedStringArray()
	lines.append("REPLAY begin v%d platform=%s build=%s ticks=%d" % [VERSION, OS.get_name(), BuildInfo.display_string(), TICKS])
	for t in TICKS:
		var commands := {}
		for id in inputs:
			commands[id] = _duel_command(world, id, inputs[id].command_for(world.tick))
		world.step(commands)
		for e in world.drain_events():
			deaths += 1 if e.type == "death" else 0
			shots += 1 if e.type == "fire" else 0
		if (t + 1) % CHECKPOINT_TICKS == 0:
			var parts := PackedStringArray(["REPLAY t=%d" % (t + 1)])
			for id in inputs:
				var s := world.get_player(id).state
				parts.append("%d:%.6f,%.6f,%.6f" % [id, s.position.x, s.position.y, s.position.z])
			lines.append(" ".join(parts))
	var summary := "REPLAY end deaths=%d shots=%d elapsed_ms=%d" % [deaths, shots, Time.get_ticks_msec() - start]
	lines.append(summary)
	for line in lines:
		print(line)
	finished.emit(summary)
	queue_free()


## Wander input, but facing the nearest living opponent, circle-strafing and
## firing inside 30 m, so the session includes hits, deaths and respawns.
static func _duel_command(world: SimWorld, id: int, c: PlayerCommand) -> PlayerCommand:
	var me := world.get_player(id).state
	var best := INF
	var target := Vector3.ZERO
	for other_id in world.players:
		var o: PlayerSimState = world.get_player(other_id).state
		if other_id == id or not o.alive:
			continue
		var d := me.position.distance_to(o.position)
		if d < best:
			best = d
			target = o.position
	if best == INF:
		return c
	var to := target - me.position
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	c.set_look(yaw, pitch)
	@warning_ignore("integer_division")
	var strafe := 1.0 if (world.tick / 120 + id) % 2 == 0 else -1.0
	c.set_move(Vector2(strafe, 1.0 if best > 8.0 else 0.0).limit_length(1.0))
	if best < 30.0:
		c.held |= PlayerCommand.Held.FIRE
	return c
