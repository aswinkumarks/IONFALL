extends GutTest
## The native rewind (native/, PLAN §3.17) must give exactly the
## GDScript hits. Skipped when the extension isn't built (CI, the web).

const Stance := PlayerSimState.Stance


func _skipped() -> bool:
	if RewindFixture.native_available():
		return false
	# Passes, not pending: CI needs GUT's "All tests passed!".
	pass_test("skipped: native extension not built (native/build.sh)")
	return true


func test_sample_matches_hitbox_history() -> void:
	if _skipped():
		return
	var f := RewindFixture.new(16, 3)
	var checked := 0
	for i in f.count:
		# Whole and fractional ticks, the window's edges and outside it.
		for k in 400:
			var vt := f.rng.randf_range(-2.0, float(RewindFixture.TICKS + 2))
			if k % 4 == 0:
				vt = floorf(vt)
			var gd := f.histories[i].sample(vt)
			var nat: Array = f.native.sample(f.ids[i], vt)
			assert_eq(nat.is_empty(), gd == null, "player %d at %f" % [i, vt])
			if gd != null and not nat.is_empty():
				assert_eq(nat[0], gd.position)
				assert_eq(nat[1], gd.stance)
				assert_eq(nat[2], gd.life_gen)
				checked += 1
	assert_gt(checked, 1000)


func test_trace_matches_gdscript_bit_for_bit() -> void:
	if _skipped():
		return
	var f := RewindFixture.new(16, 5)
	var hits := 0
	for k in 4000:
		var shooter := k % f.count
		var vt := f.random_view_tick()
		var ray := f.random_ray(shooter)
		var gd := f.gd_trace(shooter, vt, ray[0], ray[1], 60.0)
		var nat := f.native_trace(f.candidates(shooter), vt, ray[0], ray[1], 60.0)
		assert_eq(nat, gd, "ray %d" % k)
		if not gd.is_empty():
			hits += 1
	assert_gt(hits, 200, "the rays should hit often enough to compare")


func test_intersect_matches_hitbox() -> void:
	if _skipped():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for k in 3000:
		var feet := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var stance: int = k % 3
		var from := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 2.5), 8.0)
		var dir := (feet + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0, 1.9), 0) - from).normalized()
		var gd := Hitbox.intersect(feet, stance, from, dir, 20.0)
		var nat: PackedFloat64Array = ClassDB.class_call_static(RewindFixture.NATIVE_CLASS, &"intersect", feet, stance, from, dir, 20.0)
		assert_eq(nat.is_empty(), gd == null, "ray %d" % k)
		if gd != null and not nat.is_empty():
			assert_eq(nat[0], gd.distance)
			assert_eq(int(nat[1]), gd.part)


func test_removed_player_has_no_pose() -> void:
	if _skipped():
		return
	var n: RefCounted = ClassDB.instantiate(RewindFixture.NATIVE_CLASS)
	n.record(4, 10, Vector3(1, 0, 1), Stance.CROUCH, true, 0, 0)
	assert_eq(n.sample(4, 10.0), [Vector3(1, 0, 1), Stance.CROUCH, 0])
	n.remove(4)
	assert_eq(n.sample(4, 10.0), [])


## SimWorld with native_rewind against SimWorld on the GDScript path: the
## same scripted fight (every primary, lag-compensated view ticks) gives the
## same events, tick for tick.
func test_match_is_identical_with_native_rewind() -> void:
	if _skipped():
		return
	var arena := SimHarness.make_arena()
	add_child_autofree(arena)
	await wait_physics_frames(2)
	var with_native: Array = await _scripted_match(true)
	var gdscript: Array = await _scripted_match(false)
	assert_gt(with_native[1], 30, "the script should land hits")
	assert_eq(with_native[1], gdscript[1], "hits")
	assert_eq(with_native[0].size(), gdscript[0].size(), "events")
	for i in mini(with_native[0].size(), gdscript[0].size()):
		if with_native[0][i] != gdscript[0][i]:
			assert_eq(with_native[0][i], gdscript[0][i], "event %d" % i)
			return


## [event log, hit count] of RewindFixture's scripted fight, 8 players, 30 s.
func _scripted_match(native: bool) -> Array:
	var world := SimHarness.make_world(5)
	if not native:
		world.native_rewind = null
	add_child(world)
	var inputs := RewindFixture.start_fight(world, 8)
	var log: Array[String] = []
	var hits := 0
	for t in 1800:
		world.step(RewindFixture.fight_commands(world, inputs, t))
		for e in world.drain_events():
			log.append("%d %s" % [world.tick, e])
			if e.type == "hit":
				hits += 1
	remove_child(world)
	world.free()
	await wait_physics_frames(1)
	return [log, hits]
