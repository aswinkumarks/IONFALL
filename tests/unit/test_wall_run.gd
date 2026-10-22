extends GutTest
## Wall-run (PLAN §2.1): along a wall at our side with low gravity, a jump
## off it, no second run on the same wall, never into a wall head-on, and
## exact replays.

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action
const Move := PlayerSimState.Move
const FORWARD := Vector2(0, 1)

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


## Sprinting west along the north wall (wall on our right), then a jump.
func _sprint_jump_along_wall() -> void:
	input.yaw = PI * 0.5
	SimHarness.place(p, Vector3(12, 0.05, -19.25), PI * 0.5)
	_run(10)
	_run(40, FORWARD, Held.SPRINT)
	_run(1, FORWARD, Held.SPRINT, [Action.JUMP])


## Ticks until the wall-run starts (-1 if it doesn't within `limit`).
func _until_wallrun(limit: int) -> int:
	for i in limit:
		if p.state.move_state == Move.WALLRUN:
			return i
		_run(1, FORWARD, Held.SPRINT)
	return -1


func test_runs_along_the_wall_with_low_gravity() -> void:
	_sprint_jump_along_wall()
	assert_gte(_until_wallrun(20), 0, "the wall-run starts after a short hop")
	assert_almost_eq(p.state.wall_normal.z, 1.0, 0.05, "on the north wall, facing into the arena")
	var start_x := p.state.position.x
	var ticks := 0
	while p.state.move_state == Move.WALLRUN and ticks < 200:
		_run(1, FORWARD, Held.SPRINT)
		ticks += 1
	assert_gt(ticks, 60, "stays on the wall well beyond a normal jump's airtime")
	assert_lte(ticks, p.config.wallrun_ticks, "but no longer than the wall-run limit")
	assert_gt(start_x - p.state.position.x, 8.0, "covers ground along the wall")


func test_jump_kicks_off_the_wall_and_restores_the_double_jump() -> void:
	_sprint_jump_along_wall()
	assert_gte(_until_wallrun(20), 0)
	_run(10, FORWARD, Held.SPRINT)
	_run(1, FORWARD, Held.SPRINT, [Action.JUMP])
	assert_eq(p.state.move_state, Move.AIR)
	assert_gt(p.state.velocity.z, 3.0, "pushed away from the wall")
	assert_gt(p.state.velocity.y, 4.0, "and up")
	assert_eq(p.state.air_jumps_left, 1, "double jump available again")
	for i in 40:
		_run(1, FORWARD, Held.SPRINT)
		assert_ne(p.state.move_state, Move.WALLRUN, "no second run on the same wall before landing")


func test_letting_go_of_forward_drops_off() -> void:
	_sprint_jump_along_wall()
	assert_gte(_until_wallrun(20), 0)
	_run(1, Vector2.ZERO)
	assert_eq(p.state.move_state, Move.AIR)


func test_no_wallrun_when_running_into_a_wall() -> void:
	input.yaw = 0.0  # facing -Z, straight at the north wall
	SimHarness.place(p, Vector3(12, 0.05, -12), 0.0)
	_run(10)
	_run(30, FORWARD, Held.SPRINT)
	_run(1, FORWARD, Held.SPRINT, [Action.JUMP])
	for i in 40:
		_run(1, FORWARD, Held.SPRINT)
		assert_ne(p.state.move_state, Move.WALLRUN)


func test_wallrun_replays_exactly() -> void:
	_sprint_jump_along_wall()
	var saved := p.state.copy()
	var start_tick := world.tick
	var commands: Array[PlayerCommand] = []
	for i in 80:
		var c := input.cmd(world.tick, FORWARD, Held.SPRINT, [Action.JUMP] if i == 50 else [])
		commands.append(c)
		world.step({1: c})
	var expected := p.state.copy()
	assert_true(expected.move_state == Move.AIR or expected.move_state == Move.WALLRUN)
	p.restore(saved)
	world.tick = start_tick
	for c in commands:
		world.step({1: c})
	assert_eq(p.state.diff(expected), "", "same commands, same wall-run")


func test_owner_snapshot_carries_the_wallrun() -> void:
	_sprint_jump_along_wall()
	assert_gte(_until_wallrun(20), 0)
	var w := Wire.Writer.new()
	Snapshot.write_owner(w, p.state)
	var back := Snapshot.read_owner(Wire.Reader.new(w.data()))
	assert_eq(back.move_state, Move.WALLRUN)
	assert_eq(back.wallrun_ticks, p.state.wallrun_ticks)
	assert_eq(back.wall_normal, p.state.wall_normal)
