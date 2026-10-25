extends GutTest
## Recoil (PLAN §2.3): shots kick the aim up and a little sideways, held fire
## climbs to the weapon's cap, the aim settles back after the last shot, and
## the next shot goes along the kicked aim. Deterministic: same seed, same
## kicks.

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
	var p := world.add_player(1, loadout, "shooter", false)
	SimHarness.place(p, Vector3(4, 0.05, 17), 0.0)
	for i in 30:
		world.step({1: input.cmd(world.tick)})
	return p


## Holds the trigger for `ticks` (mag kept topped up).
func _hold_fire(p: SimPlayer, ticks: int) -> void:
	for i in ticks:
		p.state.mag[p.state.weapon_slot] = 30
		world.step({1: input.cmd(world.tick, Vector2.ZERO, Held.FIRE)})


func _idle(ticks: int) -> void:
	for i in ticks:
		world.step({1: input.cmd(world.tick)})


func test_held_fire_climbs_to_the_cap_and_settles_back() -> void:
	var p := _player(Weapons.PULSE)
	var data := Weapons.at(Weapons.PULSE)
	_hold_fire(p, data.ticks_between_shots * 3)
	var early := p.state.recoil.y
	assert_gt(early, 0.0, "the aim kicks up")
	_hold_fire(p, 180)
	assert_gt(p.state.recoil.y, early, "held fire keeps climbing")
	assert_lte(p.state.recoil.length(), deg_to_rad(data.recoil_max_degrees) + 1e-5, "up to the cap")
	_idle(120)
	assert_eq(p.state.recoil, Vector2.ZERO, "settled after the burst")
	# One shot: held for the delay, then settling.
	var c := input.cmd(world.tick, Vector2.ZERO, Held.FIRE)
	assert_eq(WeaponSim.step(p, c, 1 << Action.FIRE, 7).size(), 1)
	assert_eq(p.state.recoil_hold, data.recoil_recovery_delay_ticks)
	var kicked := p.state.recoil
	_idle(data.recoil_recovery_delay_ticks)
	assert_eq(p.state.recoil, kicked, "held for a moment after the shot")
	_idle(1)
	assert_lt(p.state.recoil.length(), kicked.length(), "then settling")
	_idle(120)
	assert_eq(p.state.recoil, Vector2.ZERO, "then settles back")


func test_shots_go_along_the_kicked_aim() -> void:
	var p := _player(Weapons.RAIL)  # scoped rail: no spread
	p.state.recoil = Vector2(0.0, deg_to_rad(3.0))
	p.state.recoil_hold = 5  # not settling this tick
	var c := input.cmd(world.tick, Vector2.ZERO, Held.AIM | Held.FIRE)
	var shots := WeaponSim.step(p, c, 1 << Action.FIRE, 7)
	assert_eq(shots.size(), 1)
	var kicked := WeaponSim.aim_direction(p.state.yaw, p.state.pitch + deg_to_rad(3.0))
	assert_almost_eq(shots[0].direction.angle_to(kicked), 0.0, 1e-4)
	var data := Weapons.at(Weapons.RAIL)
	assert_almost_eq(p.state.recoil.y, deg_to_rad(3.0 + data.recoil_kick_degrees * data.recoil_scoped), 0.002,
			"scoped: a smaller kick")


func test_every_gun_kicks_and_melee_does_not() -> void:
	for w: WeaponData in Weapons.ALL:
		if w.id == &"melee" or w.id == &"frag_grenade":
			assert_eq(w.recoil_kick_degrees, 0.0, "%s: no kick" % w.id)
		else:
			assert_gt(w.recoil_kick_degrees, 0.0, "%s kicks" % w.id)
			assert_gt(w.recoil_max_degrees, w.recoil_kick_degrees, "%s: the cap is above one kick" % w.id)
	var heavy := Weapons.at(Weapons.RAIL).recoil_kick_degrees
	assert_gt(heavy, Weapons.at(Weapons.PULSE).recoil_kick_degrees * 5.0, "a heavy shot kicks far harder")


func test_the_owner_snapshot_carries_recoil() -> void:
	var s := PlayerSimState.new()
	s.init_weapons(SimHarness.loadout())
	s.recoil = Vector2(-0.01, 0.05)
	s.recoil_hold = 4
	var w := Wire.Writer.new()
	Snapshot.write_owner(w, s)
	var back := Snapshot.read_owner(Wire.Reader.new(w.data()))
	assert_eq(back.recoil, s.recoil)
	assert_eq(back.recoil_hold, 4)
