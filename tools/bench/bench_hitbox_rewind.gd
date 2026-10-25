extends SceneTree
## Lag-compensation rewind: GDScript (HitboxHistory + Hitbox, as SimWorld uses
## them) against the native prototype (HitboxRewindNative, native/).
##
##   native/build.sh && godot --headless --import
##   godot --headless -s tools/bench/bench_hitbox_rewind.gd [-- --players 16 --rounds 7]
##
## Prints the median of `rounds` runs per case, in microseconds per call. For
## numbers that match a shipped build, run it from a release export
## (docs/perf/hitbox-rewind-native.md).

const PELLETS := 10  # Scatter Gun pellets per shot (data/weapons/scatter_gun.tres)
const RAYS := 2000
const MAX_DIST := 60.0


func _init() -> void:
	quit(run(OS.get_cmdline_user_args()))


## The whole benchmark; 0 on success. Static so a release export can call it
## from a scene (export templates ignore `-s`).
static func run(args: PackedStringArray) -> int:
	var players := 16
	var rounds := 7
	for i in args.size() - 1:
		if args[i] == "--players":
			players = maxi(2, int(args[i + 1]))
		elif args[i] == "--rounds":
			rounds = maxi(1, int(args[i + 1]))
	if not RewindFixture.native_available():
		printerr("HitboxRewindNative isn't loaded: run native/build.sh, then godot --headless --import")
		return 1
	print("hitbox rewind, %d players, %s build, median of %d rounds (us per call)" % [
		players, "debug" if OS.is_debug_build() else "release", rounds])
	if not _parity(players):
		return 1
	var f := RewindFixture.new(players, 11, true)

	# Every shot: shooter, view tick, ray.
	var shots: Array = []
	for k in RAYS:
		var shooter := k % players
		shots.append([shooter, f.random_view_tick(), f.random_ray(shooter)])
	var pellet_rays: Array = []
	for p in PELLETS:
		pellet_rays.append(f.random_ray(0, 0.15))

	_row("record (one player, one tick)", _time(func() -> void:
		for t in RAYS:
			f.histories[t % players].record(t, f.states[t % players])
	, rounds) / RAYS, _time(func() -> void:
		for t in RAYS:
			var s := f.states[t % players]
			f.native.record(f.ids[t % players], t, s.position, s.stance, s.alive, s.life_gen, s.discontinuity_gen)
	, rounds) / RAYS)
	# record() above wrote ticks past the fixture's; rebuild it for the rest.
	f = RewindFixture.new(players, 11, true)

	_row("sample (one player)", _time(func() -> void:
		for s: Array in shots:
			f.histories[(s[0] + 1) % players].sample(s[1])
	, rounds) / RAYS, _time(func() -> void:
		for s: Array in shots:
			f.native.sample(f.ids[(s[0] + 1) % players], s[1])
	, rounds) / RAYS)

	_row("hitscan ray vs %d players" % (players - 1), _time(func() -> void:
		for s: Array in shots:
			f.gd_trace(s[0], s[1], s[2][0], s[2][1], MAX_DIST)
	, rounds) / RAYS, _time(func() -> void:
		for s: Array in shots:
			f.native_trace(f.candidates(s[0]), s[1], s[2][0], s[2][1], MAX_DIST)
	, rounds) / RAYS)

	var shot_count := RAYS / PELLETS
	_row("%d-pellet shot vs %d players" % [PELLETS, players - 1], _time(func() -> void:
		for k in shot_count:
			for r: Array in pellet_rays:
				f.gd_trace(0, shots[k][1], r[0], r[1], MAX_DIST)
	, rounds) / shot_count, _time(func() -> void:
		for k in shot_count:
			var cands := f.candidates(0)
			for r: Array in pellet_rays:
				f.native_trace(cands, shots[k][1], r[0], r[1], MAX_DIST)
	, rounds) / shot_count)
	return 0


## Whether both give the same hits on random rays (with deaths and teleports).
static func _parity(players: int) -> bool:
	var probe := RewindFixture.new(players, 12)
	for k in RAYS:
		var shooter := k % players
		var vt := probe.random_view_tick()
		var ray := probe.random_ray(shooter)
		if probe.gd_trace(shooter, vt, ray[0], ray[1], MAX_DIST) != probe.native_trace(probe.candidates(shooter), vt, ray[0], ray[1], MAX_DIST):
			printerr("parity: ray %d differs" % k)
			return false
	print("parity: %d rays give the same hits" % RAYS)
	return true


## Median wall time of `body` over `rounds` runs (after one warm-up), in us.
static func _time(body: Callable, rounds: int) -> float:
	body.call()
	var runs: Array[float] = []
	for r in rounds:
		var t0 := Time.get_ticks_usec()
		body.call()
		runs.append(float(Time.get_ticks_usec() - t0))
	runs.sort()
	return runs[runs.size() / 2]


static func _row(label: String, gd_us: float, native_us: float) -> void:
	print("%-34s GDScript %8.2f   native %7.2f   x%.1f" % [label, gd_us, native_us, gd_us / maxf(native_us, 0.001)])
