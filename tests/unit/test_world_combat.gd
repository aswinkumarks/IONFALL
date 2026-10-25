extends GutTest
## Shots, damage, death and respawn through the full SimWorld tick.

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action

var world: SimWorld
var shooter: SimPlayer
var target: SimPlayer
var input: SimHarness.CommandScript


func before_each() -> void:
	_aim = Vector2.INF
	add_child_autofree(SimHarness.make_arena())
	world = SimHarness.make_world()
	add_child_autofree(world)
	await wait_physics_frames(2)
	shooter = world.add_player(1, SimHarness.loadout(), "shooter", false)
	target = world.add_player(2, SimHarness.loadout(), "target", true)
	input = SimHarness.CommandScript.new()
	# Open floor on the south side: shooter faces -X towards the target 10 m away.
	input.yaw = PI * 0.5
	SimHarness.place(shooter, Vector3(4, 0.05, 17), input.yaw)
	SimHarness.place(target, Vector3(-6, 0.05, 17), 0.0)
	for i in 10:
		world.step({1: input.cmd(world.tick)})
	world.drain_events()


var _aim := Vector2.INF  ## (yaw, pitch) at the target; INF: aim left to the test


func _aim_at(part_height: float) -> void:
	var eye := shooter.eye_position()
	var aim := target.state.position + Vector3(0, part_height, 0) - eye
	_aim = Vector2(atan2(-aim.x, -aim.z), atan2(aim.y, Vector2(aim.x, aim.z).length()))
	input.yaw = _aim.x
	input.pitch = _aim.y


func _fire_ticks(ticks: int, held: int = Held.FIRE, press: Array = []) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in ticks:
		# Held on target against the recoil, as a player pulls down.
		if _aim != Vector2.INF:
			input.yaw = _aim.x - shooter.state.recoil.x
			input.pitch = _aim.y - shooter.state.recoil.y
		world.step({1: input.cmd(world.tick, Vector2.ZERO, held, press if i == 0 else [])})
		events.append_array(world.drain_events())
	return events


func _of_type(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_pulse_rifle_body_shots_kill_in_12() -> void:
	_aim_at(1.2)
	var events := _fire_ticks(66 + 1)
	var hits := _of_type(events, "hit")
	assert_eq(hits.size(), 12, "12 body hits")
	assert_true(hits[-1].killed, "the 12th shot kills")
	assert_false(target.state.alive)
	assert_eq(world.scores[1], 1)


func test_headshots_after_shield_break_kill_faster() -> void:
	_aim_at(1.2)
	_fire_ticks(31)  # 6 shots: shield broken
	assert_eq(target.state.shield, 0.0)
	_aim_at(1.62)
	var events := _fire_ticks(24)
	assert_false(target.state.alive, "4 headshots finish 92 health")
	assert_true(_of_type(events, "hit")[-1].headshot)


func test_respawn_after_180_ticks_with_new_generations() -> void:
	_aim_at(1.2)
	_fire_ticks(67)
	var gen := target.state.life_gen
	var disc := target.state.discontinuity_gen
	_fire_ticks(Balance.MODES.ffa_respawn_ticks - 1, 0)
	assert_false(target.state.alive)
	var events := _fire_ticks(1, 0)
	assert_true(target.state.alive)
	assert_eq(target.state.life_gen, gen + 1)
	assert_eq(target.state.discontinuity_gen, disc + 1)
	assert_eq(target.state.health, 100.0)
	assert_eq(target.state.spawn_protection_ticks, Balance.PLAYER.spawn_protection_ticks - 1)
	assert_eq(_of_type(events, "spawn").size(), 1)


func test_rocket_direct_hit_kills() -> void:
	_fire_ticks(1, 0, [Action.SWITCH])
	_fire_ticks(40, 0)  # raise the launcher
	_aim_at(1.2)
	_fire_ticks(30, 0, [Action.FIRE])
	assert_false(target.state.alive, "200 direct damage")
	assert_eq(_of_type(world.drain_events(), "explosion").size(), 0, "event already drained above")


func test_rocket_self_damage_and_suicide_score() -> void:
	_fire_ticks(1, 0, [Action.SWITCH])
	_fire_ticks(40, 0)
	input.pitch = -1.2  # at own feet
	_fire_ticks(5, 0, [Action.FIRE])
	assert_lt(shooter.state.shield, 100.0, "self splash at 50%")
	assert_true(shooter.state.alive, "one rocket at own feet doesn't kill")
	_fire_ticks(60, 0)  # launcher cooldown (60 ticks between shots)
	shooter.state.shield = 0.0
	shooter.state.health = 10.0
	shooter.state.health_delay_ticks = 1000
	_fire_ticks(10, 0, [Action.FIRE])
	assert_false(shooter.state.alive)
	assert_eq(world.scores[1], -1, "own explosive = suicide")


func test_firing_cancels_spawn_protection() -> void:
	shooter.state.spawn_protection_ticks = 100
	_fire_ticks(1)
	assert_eq(shooter.state.spawn_protection_ticks, 0)


func test_cannot_fire_while_sprinting() -> void:
	_aim_at(1.2)
	var events := _fire_ticks(30, Held.FIRE | Held.SPRINT)
	assert_true(_of_type(events, "fire").is_empty() or not shooter.state.sprinting,
			"no shots while sprinting (sprint needs forward input)")
	var events2: Array[Dictionary] = []
	for i in 30:
		world.step({1: input.cmd(world.tick, Vector2(0, 1), Held.FIRE | Held.SPRINT)})
		events2.append_array(world.drain_events())
	assert_true(shooter.state.sprinting)
	assert_eq(_of_type(events2, "fire").size(), 0)


func test_tap_fires_one_shot_with_automatic_weapon() -> void:
	_aim_at(1.2)
	var events := _fire_ticks(1, 0, [Action.FIRE])  # press without holding
	events.append_array(_fire_ticks(20, 0))
	assert_eq(_of_type(events, "fire").size(), 1, "a tap fires exactly one shot")
