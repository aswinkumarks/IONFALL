class_name RewindFixture
extends RefCounted
## Shared by tests/unit/test_hitbox_native.gd and tools/bench/bench_*.gd:
## the same lag-compensation history in GDScript (HitboxHistory) and in the
## native extension (HitboxRewindNative, native/), plus the SimWorld._trace
## player loop on each. The native class is only reached through ClassDB, so
## this parses when the extension isn't built.

const NATIVE_CLASS := "HitboxRewindNative"
## Ticks recorded; the "current" tick is TICKS (not recorded yet, as in SimWorld).
const TICKS := HitboxHistory.LENGTH

var count: int
var states: Array[PlayerSimState] = []
var histories: Array[HitboxHistory] = []
var native: RefCounted  # HitboxRewindNative, or null without the extension
var ids := PackedInt32Array()
var life_gens := PackedInt32Array()
var rng := RandomNumberGenerator.new()


static func native_available() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## `count` players with TICKS ticks of history: walking, changing stance, and
## (unless `clean`) dying, respawning and teleporting now and then.
func _init(player_count: int, seed_value: int = 1, clean: bool = false) -> void:
	count = player_count
	rng.seed = seed_value
	if native_available():
		native = ClassDB.instantiate(NATIVE_CLASS)
	for i in count:
		var s := PlayerSimState.new()
		s.position = Vector3(rng.randf_range(-20, 20), rng.randf_range(0, 4), rng.randf_range(-20, 20))
		states.append(s)
		histories.append(HitboxHistory.new())
		ids.append(i + 1)
	var walk: Array[Vector3] = []
	for i in count:
		walk.append(Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12)))
	for tick in TICKS:
		for i in count:
			var s := states[i]
			s.position += walk[i]
			if rng.randf() < 0.05:
				s.stance = rng.randi_range(0, 2) as PlayerSimState.Stance
			if not clean:
				if s.alive and rng.randf() < 0.01:
					s.alive = false
				elif not s.alive and rng.randf() < 0.3:
					s.alive = true
					s.life_gen += 1
					s.discontinuity_gen += 1
					s.position = Vector3(rng.randf_range(-20, 20), 0.0, rng.randf_range(-20, 20))
				elif rng.randf() < 0.01:
					s.discontinuity_gen += 1
					s.position += Vector3(rng.randf_range(-3, 3), 0.0, rng.randf_range(-3, 3))
			histories[i].record(tick, s)
			if native != null:
				native.record(ids[i], tick, s.position, s.stance, s.alive, s.life_gen, s.discontinuity_gen)
	for s in states:
		life_gens.append(s.life_gen)


## A lag-compensated view tick inside SimWorld's rewind window.
func random_view_tick() -> float:
	return rng.randf_range(float(TICKS - HitboxHistory.MAX_REWIND_TICKS), float(TICKS - 1))


## [origin, normalized dir]: from `shooter`'s eye towards another player's
## chest, `spread` radians off, so roughly half the rays hit someone.
func random_ray(shooter: int, spread: float = 0.08) -> Array:
	var origin := states[shooter].position + Vector3(0, 1.5, 0)
	var other := (shooter + 1 + rng.randi_range(0, count - 2)) % count
	var dir := (states[other].position + Vector3(0, 1.1, 0) - origin).normalized()
	dir = dir.rotated(Vector3.UP, rng.randf_range(-spread, spread))
	dir = dir.rotated(dir.cross(Vector3.UP).normalized(), rng.randf_range(-spread, spread)).normalized()
	return [origin, dir]


## Players other than `shooter` as SimWorld._trace would filter them (alive
## now): [ids, life_gens, history indices].
func candidates(shooter: int) -> Array:
	var c_ids := PackedInt32Array()
	var c_gens := PackedInt32Array()
	var index := PackedInt32Array()
	for i in count:
		if i == shooter or not states[i].alive:
			continue
		c_ids.append(ids[i])
		c_gens.append(life_gens[i])
		index.append(i)
	return [c_ids, c_gens, index]


## SimWorld._trace's player loop in GDScript (HitboxHistory.sample + _pose's
## life_gen check + Hitbox.intersect): [player index, distance, part] or [].
func gd_trace(shooter: int, view_tick: float, origin: Vector3, dir: Vector3, max_dist: float) -> Array:
	var target := -1
	var best: Hitbox.Hit = null
	for i in count:
		if i == shooter or not states[i].alive:
			continue
		var pose := histories[i].sample(view_tick)
		if pose == null or pose.life_gen != life_gens[i]:
			continue
		var hit := Hitbox.intersect(pose.position, pose.stance, origin, dir, max_dist)
		if hit != null and (best == null or hit.distance < best.distance):
			best = hit
			target = i
	return [] if best == null else [target, best.distance, best.part]


## The same through HitboxRewindNative.trace(), given candidates(shooter).
func native_trace(cands: Array, view_tick: float, origin: Vector3, dir: Vector3, max_dist: float) -> Array:
	var r: PackedFloat64Array = native.trace(cands[0], cands[1], view_tick, origin, dir, max_dist)
	return [] if r.is_empty() else [(cands[2] as PackedInt32Array)[int(r[0])], r[1], int(r[2])]


## A scripted fight for SimWorld runs that must repeat exactly: `count`
## players on `world` with every primary, lag compensation on. Returns the
## per-player CommandScripts for fight_commands().
static func start_fight(world: SimWorld, count: int) -> Dictionary:
	world.lag_compensation = true
	var inputs := {}
	for i in count:
		world.add_player(i + 1, Loadouts.make(i % Loadouts.PRIMARIES.size()), "P%d" % i, false)
		inputs[i + 1] = SimHarness.CommandScript.new()
	return inputs


## Tick `t`'s commands: each player aims near another one's chest (changing
## every 2 s), strafes, crouches now and then, holds and presses fire and claims a view
## tick 3-9 ticks back, as a client would (SimWorld clamps it).
static func fight_commands(world: SimWorld, inputs: Dictionary, t: int) -> Dictionary:
	var commands := {}
	var count := inputs.size()
	for id: int in inputs:
		var s := world.get_player(id).state
		var input: SimHarness.CommandScript = inputs[id]
		var other := world.get_player((id + t / 120) % count + 1)
		if other == world.get_player(id):
			other = world.get_player(id % count + 1)
		var d := other.state.position + Vector3(0, 1.1, 0) - s.position - Vector3(0, 1.6, 0)
		input.yaw = atan2(-d.x, -d.z) + 0.04 * sin(t * 0.07 + id)
		input.pitch = atan2(d.y, Vector2(d.x, d.z).length())
		var held := PlayerCommand.Held.FIRE
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
