extends GutTest
## Scoping (aim held, PLAN §2.3): tighter spread, slower movement and no
## sprint with a scoped weapon that's up; the rail sniper is only accurate
## scoped.

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action

var world: SimWorld
var input: SimHarness.CommandScript


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	world = SimHarness.make_world()
	add_child_autofree(world)
	await wait_physics_frames(2)
	input = SimHarness.CommandScript.new()


func _player(primary: int) -> SimPlayer:
	var loadout: Array[WeaponData] = [Weapons.at(primary), Weapons.at(Weapons.PISTOL)]
	var p := world.add_player(1, loadout, "scoper", false)
	SimHarness.place(p, Vector3(4, 0.05, 17), 0.0)
	for i in 10:
		world.step({1: input.cmd(world.tick)})
	return p


## The widest angle (degrees) between the aim and `shots` single-ray shots,
## firing a fresh shot each time.
func _widest_spread(p: SimPlayer, held: int, shots: int) -> float:
	var widest := 0.0
	var aim := WeaponSim.aim_direction(p.state.yaw, p.state.pitch)
	var c := input.cmd(world.tick, Vector2.ZERO, held | Held.FIRE)
	for i in shots:
		var w := p.state.weapon_slot
		p.state.cooldown[w] = 0
		p.state.mag[w] = 10
		p.state.recoil = Vector2.ZERO  # spread only: test_recoil covers the kick
		for shot in WeaponSim.step(p, c, 1 << Action.FIRE, 99):
			widest = maxf(widest, rad_to_deg(aim.angle_to(shot.direction)))
	return widest


func test_scoped_pulse_rifle_spread_is_tighter() -> void:
	var p := _player(Weapons.PULSE)
	var data := Weapons.at(Weapons.PULSE)
	var hip := _widest_spread(p, 0, 200)
	var scoped := _widest_spread(p, Held.AIM, 200)
	assert_lte(scoped, data.spread_degrees * data.scope_spread + 0.001, "within the scoped cone")
	assert_gt(hip, data.spread_degrees * data.scope_spread + 0.05, "hip fire uses the wider cone")


func test_rail_sniper_is_exact_only_scoped() -> void:
	var p := _player(Weapons.RAIL)
	assert_gt(_widest_spread(p, 0, 50), 0.5, "no-scope shots spread")
	assert_almost_eq(_widest_spread(p, Held.AIM, 50), 0.0, 0.001, "scoped shots go where aimed")


func test_scoped_movement_is_slower_and_never_sprints() -> void:
	var p := _player(Weapons.PULSE)
	for i in 90:
		world.step({1: input.cmd(world.tick, Vector2(0, 1), Held.SPRINT | Held.AIM)})
	var speed := Vector2(p.state.velocity.x, p.state.velocity.z).length()
	assert_false(p.state.sprinting, "aiming blocks sprint")
	assert_almost_eq(speed, p.config.walk_speed * Weapons.at(Weapons.PULSE).scope_move_speed, 0.2)


func test_no_scope_while_reloading_or_with_melee_only_weapons() -> void:
	var p := _player(Weapons.PULSE)
	assert_true(WeaponSim.can_scope(p.state))
	p.state.reload[p.state.weapon_slot] = 10
	assert_false(WeaponSim.can_scope(p.state), "reloading")
	p.state.reload[p.state.weapon_slot] = 0
	p.state.alive = false
	assert_false(WeaponSim.can_scope(p.state), "dead")
	for d: WeaponData in [Weapons.at(Weapons.MELEE), Weapons.at(Weapons.FRAG)]:
		assert_eq(d.scope_zoom, 1.0, "%s has no scope" % d.id)
