extends GutTest
## PLAN §3.2 / M1a exit criterion: same build, same platform → replay must
## reproduce PlayerSimState exactly on every tick.

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action
const TICKS := 600


## A scripted session: walk, sprint, slide, jumps, mantle onto the 1.5 m
## ledge, fire the Pulse Rifle, switch and fire the Arc Launcher away from
## walls (no self-damage, so the movement+weapon path alone is replayable).
func _commands() -> Array[PlayerCommand]:
	var input := SimHarness.CommandScript.new()
	var out: Array[PlayerCommand] = []
	for t in TICKS:
		var move := Vector2.ZERO
		var held := 0
		var press: Array = []
		input.pitch = 0.0
		if t < 60:
			input.yaw = 0.0  # face -Z: mantle onto the 1.5 m ledge
			move = Vector2(0, 1)
			if t >= 20:
				held = Held.JUMP
			if t == 20:
				press = [Action.JUMP]
		elif t < 100:
			input.yaw = PI  # face +Z: drop back to the open floor
			move = Vector2(0, 1)
		elif t < 160:
			input.yaw = -PI * 0.5  # face +X: sprint east
			move = Vector2(0, 1)
			held = Held.SPRINT
		elif t < 190:
			input.yaw = -PI * 0.5
			move = Vector2(0, 1)
			held = Held.SPRINT | Held.CROUCH  # slide
		elif t < 240:
			input.yaw = -PI * 0.5 + (t - 190) * 0.01
			move = Vector2(0.5, 1)
			if t == 200 or t == 215:
				press = [Action.JUMP]  # jump + double jump
		elif t < 320:
			input.yaw = 0.3 * sin(t * 0.05)
			move = Vector2(0, 1)
			held = Held.FIRE | (Held.JUMP if t % 40 < 20 else 0)
			if t % 40 == 0:
				press = [Action.JUMP]
		elif t < 330:
			press = [Action.SWITCH] if t == 320 else []
		elif t < 420:
			input.yaw = PI
			input.pitch = 0.4
			if t % 70 == 0:
				press = [Action.FIRE]
			move = Vector2(-0.7, 0.3)
		else:
			input.yaw = PI + (t - 420) * 0.02
			move = Vector2(sin(t * 0.1), cos(t * 0.07))
			held = Held.CROUCH if t % 90 < 30 else 0
			if t % 50 == 0:
				press = [Action.JUMP, Action.RELOAD]
		out.append(input.cmd(t, move, held, press))
	return out


func _new_player(seed_value: int) -> Array:
	var world := SimHarness.make_world(seed_value)
	add_child_autofree(world)
	var p := world.add_player(1, SimHarness.loadout(), "replay", false)
	SimHarness.place(p, Vector3(-11, 0.05, 15.5), 0.0)
	return [world, p]


func _record(world: SimWorld, p: SimPlayer, commands: Array[PlayerCommand]) -> Array[PlayerSimState]:
	var states: Array[PlayerSimState] = []
	for c in commands:
		world.step({1: c})
		states.append(p.state.copy())
	return states


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	await wait_physics_frames(2)


func test_two_runs_are_identical_every_tick() -> void:
	var commands := _commands()
	var a: Array = _new_player(11)
	var b: Array = _new_player(11)
	var run_a := _record(a[0], a[1], commands)
	var run_b := _record(b[0], b[1], commands)
	var first_diff := ""
	for t in TICKS:
		var d := run_a[t].diff(run_b[t])
		if d != "":
			first_diff = "tick %d: %s" % [t, d]
			break
	assert_eq(first_diff, "", "runs diverged")
	assert_gt(run_a[TICKS - 1].action_seq, 10, "the script fired weapons")
	assert_ne(run_a[TICKS - 1].position, run_a[0].position, "the script moved")


func test_restore_and_replay_matches_recording() -> void:
	var commands := _commands()
	var run: Array = _new_player(11)
	var recorded := _record(run[0], run[1], commands)
	var replayer: SimPlayer = run[1]
	const FROM := 300
	replayer.restore(recorded[FROM])
	var first_diff := ""
	for t in range(FROM + 1, TICKS):
		var executed := ActionInput.consume(replayer.state, commands[t])
		PlayerSimulation.step(replayer, commands[t], executed, (run[0] as SimWorld).match_seed)
		Health.tick_regen(replayer.state)
		var d := replayer.state.diff(recorded[t])
		if d != "":
			first_diff = "tick %d: %s" % [t, d]
			break
	assert_eq(first_diff, "", "prediction replay diverged from the authoritative run")


func test_script_exercised_key_states() -> void:
	var run: Array = _new_player(11)
	var seen := {}
	for s in _record(run[0], run[1], _commands()):
		seen[s.move_state] = true
	assert_true(seen.has(PlayerSimState.Move.SLIDE), "slid")
	assert_true(seen.has(PlayerSimState.Move.AIR), "jumped")
	assert_true(seen.has(PlayerSimState.Move.MANTLE), "mantled")
