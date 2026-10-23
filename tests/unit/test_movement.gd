extends GutTest
## Movement against the real test arena collision.

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action
const Move := PlayerSimState.Move

var world: SimWorld
var p: SimPlayer
var input: SimHarness.CommandScript


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	world = SimHarness.make_world()
	add_child_autofree(world)
	await wait_physics_frames(2)
	p = world.add_player(1, SimHarness.loadout(), "test", false)
	input = SimHarness.CommandScript.new()


func _run(ticks: int, move: Vector2 = Vector2.ZERO, held: int = 0, press_first: Array = []) -> void:
	for i in ticks:
		var press: Array = press_first if i == 0 else []
		world.step({1: input.cmd(world.tick, move, held, press)})


## Puts the player on open floor at (0, 0, 16) facing -Z (towards the centre).
func _place_open(feet: Vector3 = Vector3(0, 0.05, 16.5), yaw: float = 0.0) -> void:
	input.yaw = yaw
	SimHarness.place(p, feet, yaw)
	_run(10)


func test_lands_on_floor() -> void:
	_place_open()
	assert_eq(p.state.move_state, Move.GROUND)
	assert_almost_eq(p.state.position.y, 0.0, 0.05)


func test_walk_and_sprint_speeds() -> void:
	_place_open(Vector3(-2, 0.05, 19), PI * 0.5)  # facing -X along the south wall
	_run(40, Vector2(0, 1))
	var walk := Vector2(p.state.velocity.x, p.state.velocity.z).length()
	assert_almost_eq(walk, 6.0, 0.05, "walk speed")
	_run(40, Vector2(0, 1), Held.SPRINT)
	var sprint := Vector2(p.state.velocity.x, p.state.velocity.z).length()
	assert_almost_eq(sprint, 8.5, 0.05, "sprint speed")


func test_only_one_air_jump() -> void:
	_place_open()
	_run(1, Vector2.ZERO, 0, [Action.JUMP])
	assert_eq(p.state.move_state, Move.AIR)
	_run(10)
	_run(1, Vector2.ZERO, 0, [Action.JUMP])
	assert_eq(p.state.air_jumps_left, 0, "double jump used")
	var vy := p.state.velocity.y
	_run(1, Vector2.ZERO, 0, [Action.JUMP])
	assert_lt(p.state.velocity.y, vy, "third jump does nothing, gravity continues")


func test_coyote_time_allows_late_jump() -> void:
	# Walk off the east edge of the centre platform (top 2.0 m) and jump 4 ticks later.
	input.yaw = -PI * 0.5  # facing +X
	SimHarness.place(p, Vector3(3.3, 2.05, 2), input.yaw)
	_run(10)
	assert_eq(p.state.move_state, Move.GROUND)
	var ticks := 0
	while p.state.move_state == Move.GROUND and ticks < 60:
		_run(1, Vector2(0, 1))
		ticks += 1
	assert_eq(p.state.move_state, Move.AIR, "walked off the edge")
	_run(3, Vector2(0, 1))
	_run(1, Vector2(0, 1), 0, [Action.JUMP])
	assert_gt(p.state.velocity.y, 5.0, "ground jump within coyote time")
	assert_eq(p.state.air_jumps_left, 1, "the double jump is still available")


func test_slide_from_sprint() -> void:
	_place_open(Vector3(-2, 0.05, 19), PI * 0.5)
	_run(40, Vector2(0, 1), Held.SPRINT)
	_run(1, Vector2(0, 1), Held.SPRINT | Held.CROUCH)
	assert_eq(p.state.move_state, Move.SLIDE)
	assert_eq(p.state.stance, PlayerSimState.Stance.SLIDE)
	var speed := Vector2(p.state.velocity.x, p.state.velocity.z).length()
	assert_gt(speed, 10.5, "slide boost")
	_run(1, Vector2(0, 1), Held.SPRINT)
	assert_ne(p.state.move_state, Move.SLIDE, "releasing crouch ends the slide")


func _mantle_attempt(ledge_x: float, double_jump: bool) -> float:
	# Ledges are 2 m deep, front face at z = 13. Start 0.6 m away, facing -Z.
	input.yaw = 0.0
	SimHarness.place(p, Vector3(ledge_x, 0.05, 13.6), 0.0)
	_run(5)
	_run(1, Vector2(0, 1), Held.JUMP, [Action.JUMP])
	if double_jump:
		_run(18, Vector2(0, 1), Held.JUMP)
		_run(1, Vector2(0, 1), Held.JUMP, [Action.JUMP])
	# Hold forward + jump until the mantle finishes, then let go (otherwise the
	# player walks straight off the far side of the 2 m deep ledge).
	var mantled := false
	for i in 80:
		_run(1, Vector2(0, 1), Held.JUMP)
		mantled = mantled or p.state.move_state == Move.MANTLE
		if mantled and p.state.move_state == Move.GROUND:
			break
	_run(20)
	return p.state.position.y


func test_mantle_onto_1_5m_ledge() -> void:
	assert_almost_eq(_mantle_attempt(-11.0, false), 1.5, 0.1)


func test_mantle_onto_1_8m_ledge() -> void:
	assert_almost_eq(_mantle_attempt(-8.0, false), 1.8, 0.1)


func test_3_2m_ledge_needs_double_jump() -> void:
	assert_lt(_mantle_attempt(-5.0, false), 0.5, "single jump + mantle can't reach 3.2 m")
	assert_almost_eq(_mantle_attempt(-5.0, true), 3.2, 0.1, "double jump + mantle can")


## Walking up a ramp keeps (almost) the flat-ground horizontal speed; it
## used to lose a slice of speed to the slope every tick.
func test_ramps_are_as_fast_as_flat_ground() -> void:
	_place_open(Vector3(0, 0.05, 16.5))
	var speeds := {}
	var t_flat := -1
	var z_flat := 0.0
	var t_ramp := -1
	var z_ramp := 0.0
	for i in 240:
		_run(1, Vector2(0, 1))
		var z := p.state.position.z
		if t_flat < 0 and z < 15.5:
			t_flat = world.tick
			z_flat = z
		if t_flat >= 0 and not speeds.has("flat") and z < 13.0:
			speeds["flat"] = (z_flat - z) / ((world.tick - t_flat) * Sim.TICK_DT)
		if t_ramp < 0 and z < 10.5:
			t_ramp = world.tick
			z_ramp = z
		if t_ramp >= 0 and not speeds.has("ramp") and z < 6.5:
			speeds["ramp"] = (z_ramp - z) / ((world.tick - t_ramp) * Sim.TICK_DT)
			assert_gt(p.state.position.y, 0.5, "climbed onto the ramp")
	gut.p("horizontal speed m/s: %s" % [speeds])
	assert_true(speeds.has("flat") and speeds.has("ramp"), "walked both stretches")
	if speeds.has("ramp"):
		assert_gt(speeds.ramp, speeds.flat * 0.95, "ramp speed close to flat speed")


## Players block each other: walking into a standing player stops at
## their capsule instead of passing through.
func test_players_cannot_walk_through_each_other() -> void:
	var other := world.add_player(2, SimHarness.loadout(), "other", false)
	var still := SimHarness.CommandScript.new()
	input.yaw = 0.0
	SimHarness.place(p, Vector3(0, 0.05, 16.5), 0.0)
	SimHarness.place(other, Vector3(0, 0.05, 14.0), 0.0)
	for i in 120:  # 2 s walking north (-Z) into the other player
		world.step({1: input.cmd(world.tick, Vector2(0, 1)), 2: still.cmd(world.tick)})
	var gap := Vector2(p.state.position.x - other.state.position.x, p.state.position.z - other.state.position.z).length()
	assert_gt(p.state.position.z, other.state.position.z, "still on the near side")
	assert_gt(gap, 0.75, "kept apart by their capsules (%.2f m)" % gap)
	assert_almost_eq(other.state.position.z, 14.0, 0.05, "the player standing still isn't shoved along")
