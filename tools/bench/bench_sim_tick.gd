extends SceneTree
## Server tick cost of a lag-compensated fight (RewindFixture's script: every
## primary, everyone holding fire) with SimWorld.native_rewind against the
## GDScript path. Times SimWorld.step() only.
##
##   native/build.sh && godot --headless --import
##   godot --headless -s tools/bench/bench_sim_tick.gd [-- --players 16 --seconds 60 --rounds 3]
##
## For numbers that match a shipped build, run it from a release export
## (docs/perf/hitbox-rewind-native.md).

const ARENA := preload("res://maps/test_arena/gameplay.tscn")


func _initialize() -> void:
	quit(await run(self, OS.get_cmdline_user_args()))


## The whole benchmark; 0 on success. Static so a release export can call it
## from a scene (export templates ignore `-s`).
static func run(tree: SceneTree, args: PackedStringArray) -> int:
	var players := 16
	var seconds := 60
	var rounds := 3
	for i in args.size() - 1:
		if args[i] == "--players":
			players = clampi(int(args[i + 1]), 2, 16)
		elif args[i] == "--seconds":
			seconds = maxi(1, int(args[i + 1]))
		elif args[i] == "--rounds":
			rounds = maxi(1, int(args[i + 1]))
	if not RewindFixture.native_available():
		printerr("HitboxRewindNative isn't loaded: run native/build.sh, then godot --headless --import")
		return 1
	# Called from a scene's _ready, the root is still adding children.
	await tree.process_frame
	var arena := ARENA.instantiate()
	tree.root.add_child(arena)
	for i in 2:
		await tree.physics_frame
	print("sim tick, %d players, %d s per run, %s build (ms per SimWorld.step)" % [
		players, seconds, "debug" if OS.is_debug_build() else "release"])
	# Alternate the two so drift on the machine hits both alike.
	for r in rounds:
		for native in [true, false]:
			var res: Array = await _fight(tree, players, seconds * Sim.TICK_RATE, native)
			var st: FrameStats = res[0]
			print("  %-8s p50 %.3f  p95 %.3f  p99 %.3f  max %.3f   (%d shots, %d hits)" % [
				"native" if native else "GDScript", st.percentile(50), st.percentile(95), st.percentile(99),
				st.percentile(100), res[1], res[2]])
	arena.queue_free()
	return 0


## [FrameStats of step() times, shots fired, hits].
static func _fight(tree: SceneTree, players: int, ticks: int, native: bool) -> Array:
	var world := SimWorld.new()
	world.configure(5, SimHarness.MOVEMENT, TestArenaLayout.spawn_points())
	if not native:
		world.native_rewind = null
	tree.root.add_child(world)
	var inputs := RewindFixture.start_fight(world, players)
	var st := FrameStats.new(ticks)
	var shots := 0
	var hits := 0
	for t in ticks:
		var commands := RewindFixture.fight_commands(world, inputs, t)
		var t0 := Time.get_ticks_usec()
		world.step(commands)
		st.add((Time.get_ticks_usec() - t0) / 1000.0)
		for e in world.drain_events():
			shots += 1 if e.type == "fire" else 0
			hits += 1 if e.type == "hit" else 0
	tree.root.remove_child(world)
	world.free()
	await tree.physics_frame
	return [st, shots, hits]
