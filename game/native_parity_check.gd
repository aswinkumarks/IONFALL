class_name NativeParityCheck
extends Node
## On-device check of the native hitbox rewind (native/, PLAN §3.17): the
## same scripted 8-player, lag-compensated fight in the test arena runs once
## with SimWorld.native_rewind and once on the GDScript path, and every event
## must match. On x86_64 the unit tests prove this; on a phone the engine is
## built with clang, which may fuse multiply-adds the native library doesn't,
## so it's run there too. Prints lines starting "NATIVE_PARITY", with each
## path's time.
##
## Desktop: `godot -- --native-parity` (prints and quits). Android: put
## `--native-parity` in the app's files/launch_args.txt; read the result with
## `adb logcat -s godot`.

signal finished(summary: String)

const CommandScript := preload("res://game/command_script.gd")
const PLAYERS := 8
const TICKS := 1800
const SEED := 5
const MOVEMENT := preload("res://data/movement_config.tres")
const ARENA_GAMEPLAY := preload("res://maps/test_arena/gameplay.tscn")


func _ready() -> void:
	if not ClassDB.class_exists(&"HitboxRewindNative"):
		_finish("NATIVE_PARITY skipped: native rewind off on %s" % OS.get_name())
		return
	add_child(ARENA_GAMEPLAY.instantiate())
	# Static world bodies become queryable after the first physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var native := _fight(true)
	var gdscript := _fight(false)
	print("NATIVE_PARITY begin platform=%s build=%s players=%d ticks=%d" % [
		OS.get_name(), BuildInfo.display_string(), PLAYERS, TICKS])
	print("NATIVE_PARITY native_ms=%d gdscript_ms=%d hits=%d events=%d" % [
		native[2], gdscript[2], native[1], native[0].size()])
	var log_a: Array = native[0]
	var log_b: Array = gdscript[0]
	for i in mini(log_a.size(), log_b.size()):
		if log_a[i] != log_b[i]:
			_finish("NATIVE_PARITY FAIL at event %d: native '%s', gdscript '%s'" % [i, log_a[i], log_b[i]])
			return
	if log_a.size() != log_b.size() or native[1] != gdscript[1]:
		_finish("NATIVE_PARITY FAIL: %d vs %d events, %d vs %d hits" % [
			log_a.size(), log_b.size(), native[1], gdscript[1]])
	elif native[1] < 30:
		_finish("NATIVE_PARITY FAIL: only %d hits, too few to compare" % native[1])
	else:
		_finish("NATIVE_PARITY OK")


func _finish(summary: String) -> void:
	print(summary)
	finished.emit(summary)
	queue_free()


## [event log, hit count, elapsed ms] of the scripted fight.
func _fight(native: bool) -> Array:
	var world := SimWorld.new()
	world.configure(SEED, MOVEMENT, TestArenaLayout.spawn_points())
	if not native:
		world.native_rewind = null
	add_child(world)
	var inputs := start_fight(world, PLAYERS)
	var log: Array[String] = []
	var hits := 0
	var start := Time.get_ticks_msec()
	for t in TICKS:
		world.step(fight_commands(world, inputs, t))
		for e in world.drain_events():
			log.append("%d %s" % [world.tick, e])
			if e.type == "hit":
				hits += 1
	var elapsed := Time.get_ticks_msec() - start
	remove_child(world)
	world.free()
	return [log, hits, elapsed]


## A scripted fight for SimWorld runs that must repeat exactly: `count`
## players on `world` with every primary, lag compensation on. Returns the
## per-player command scripts for fight_commands(). Also used by
## tests/unit/test_hitbox_native.gd and tools/bench/bench_sim_tick.gd.
static func start_fight(world: SimWorld, count: int) -> Dictionary:
	world.lag_compensation = true
	var inputs := {}
	for i in count:
		world.add_player(i + 1, Loadouts.make(i % Loadouts.PRIMARIES.size()), "P%d" % i, false)
		inputs[i + 1] = CommandScript.new()
	return inputs


## Tick `t`'s commands: each player aims near another one's chest (changing
## every 2 s), strafes, crouches now and then, holds and presses fire and claims a view
## tick 3-9 ticks back, as a client would (SimWorld clamps it).
static func fight_commands(world: SimWorld, inputs: Dictionary, t: int) -> Dictionary:
	var commands := {}
	var count := inputs.size()
	for id: int in inputs:
		var s := world.get_player(id).state
		var input: CommandScript = inputs[id]
		@warning_ignore("integer_division")
		var other := world.get_player((id + t / 120) % count + 1)
		if other == world.get_player(id):
			other = world.get_player(id % count + 1)
		var d := other.state.position + Vector3(0, 1.1, 0) - s.position - Vector3(0, 1.6, 0)
		input.yaw = atan2(-d.x, -d.z) + 0.04 * sin(t * 0.07 + id)
		input.pitch = atan2(d.y, Vector2(d.x, d.z).length())
		var held := PlayerCommand.Held.FIRE
		@warning_ignore("integer_division")
		if (t / 90 + id) % 4 == 0:
			held |= PlayerCommand.Held.CROUCH
		# Semi-automatic guns (Scatter Gun, pistol) need a press per shot.
		var press := [PlayerCommand.Action.FIRE] if (t + id) % 20 == 0 else []
		if t % 150 == id:
			press.append(PlayerCommand.Action.RELOAD)
		var c := input.cmd(world.tick, Vector2(sin(t * 0.02 + id * 1.7), 0.0), held, press)
		c.view_tick = world.tick - 3.0 - (id % 7) * 0.93
		commands[id] = c
	return commands
