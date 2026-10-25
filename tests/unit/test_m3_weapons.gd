extends GutTest
## M3 combat (PLAN §2.3): Scatter Gun pellets and shell reload, frag
## grenades, melee, per-player weapon slots and friendly fire.

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action

var world: SimWorld
var shooter: SimPlayer
var target: SimPlayer
var input: SimHarness.CommandScript
var target_input := SimHarness.CommandScript.new()


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	world = SimHarness.make_world()
	add_child_autofree(world)
	await wait_physics_frames(2)
	shooter = world.add_player(1, Loadouts.make(2), "shooter", false)
	target = world.add_player(2, Loadouts.make(0), "target", true)
	input = SimHarness.CommandScript.new()
	input.yaw = PI * 0.5
	_place(Vector3(4, 0.05, 17), Vector3(1.5, 0.05, 17))


func _place(shooter_at: Vector3, target_at: Vector3, target_yaw: float = 0.0) -> void:
	SimHarness.place(shooter, shooter_at, input.yaw)
	SimHarness.place(target, target_at, target_yaw)
	target_input.yaw = target_yaw
	for i in 10:
		world.step({1: input.cmd(world.tick), 2: target_input.cmd(world.tick)})
	world.drain_events()
	target.state.spawn_protection_ticks = 0
	shooter.state.spawn_protection_ticks = 0


func _aim_at(height: float) -> void:
	var aim := target.state.position + Vector3(0, height, 0) - shooter.eye_position()
	input.yaw = atan2(-aim.x, -aim.z)
	input.pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())


func _run(ticks: int, held: int = 0, press: Array = []) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in ticks:
		world.step({1: input.cmd(world.tick, Vector2.ZERO, held, press if i == 0 else []), 2: target_input.cmd(world.tick)})
		events.append_array(world.drain_events())
	return events


func _hits(events: Array[Dictionary]) -> Array[Dictionary]:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "hit" and e.target == 2)


func test_scatter_gun_two_point_blank_shots_kill() -> void:
	_aim_at(1.1)
	var first := _hits(_run(1, 0, [Action.FIRE]))
	assert_eq(first.size(), 1, "pellets on one target make one hit")
	assert_gt(first[0].amount, 100.0, "most of 10 × 12 lands point blank")
	assert_true(target.state.alive)
	_run(Weapons.at(Weapons.SCATTER).ticks_between_shots)
	_run(1, 0, [Action.FIRE])
	assert_false(target.state.alive, "the second shot kills")


func test_scatter_gun_reloads_one_shell_at_a_time() -> void:
	var s := shooter.state
	s.mag[0] = 2
	var reserve := s.reserve[0]
	_run(1, 0, [Action.RELOAD])
	_run(Weapons.at(Weapons.SCATTER).reload_ticks)
	assert_eq(s.mag[0], 3, "one shell per 30 ticks")
	assert_eq(s.reserve[0], reserve, "a loadout weapon's reserve never runs down")
	_run(Weapons.at(Weapons.SCATTER).reload_ticks * 3)
	assert_eq(s.mag[0], 6, "keeps going until full")


func test_slots_hold_weapon_indices() -> void:
	assert_eq(shooter.state.weapons, PackedInt32Array([Weapons.SCATTER, Weapons.PISTOL]))
	shooter.state.set_slot(0, Weapons.RAIL, 4, 8)
	assert_eq(shooter.current_weapon().id, &"rail_sniper")
	assert_eq(shooter.state.copy().weapons, shooter.state.weapons, "slots replay")


func test_grenade_explodes_after_fuse_and_hurts() -> void:
	_place(Vector3(4, 0.05, 17), Vector3(-3, 0.05, 17))
	_aim_at(0.0)
	var events := _run(1, 0, [Action.GRENADE])
	assert_eq(shooter.state.grenades, 1, "2 per life, one thrown")
	assert_eq(world.projectiles.size(), 1)
	events = _run(Weapons.at(Weapons.FRAG).fuse_ticks + 2)
	var boom := events.filter(func(e: Dictionary) -> bool: return e.type == "explosion")
	assert_eq(boom.size(), 1, "explodes once, on the fuse")
	assert_eq(world.projectiles.size(), 0)
	assert_gt(_hits(events).size(), 0, "the splash reaches the target")


func test_melee_front_and_back() -> void:
	_place(Vector3(4, 0.05, 17), Vector3(2.8, 0.05, 17), -PI * 0.5)  # facing the attacker
	_aim_at(1.1)
	var front := _hits(_run(1, 0, [Action.MELEE]))
	assert_eq(front.size(), 1)
	assert_almost_eq(front[0].amount, 70.0, 0.01, "70 from the front")
	assert_eq(shooter.state.melee_cooldown, Weapons.at(Weapons.MELEE).ticks_between_shots)
	target_input.yaw = PI * 0.5  # now facing away
	Health.reset(target.state)
	_run(Weapons.at(Weapons.MELEE).ticks_between_shots)
	_run(1, 0, [Action.MELEE])
	assert_false(target.state.alive, "200 from behind kills")


func test_no_friendly_fire_by_default() -> void:
	world.teams_enabled = true
	shooter.team = 1
	target.team = 1
	_aim_at(1.1)
	assert_eq(_hits(_run(1, 0, [Action.FIRE])).size(), 0, "teammates take no damage")
	world.friendly_fire = true
	_run(Weapons.at(Weapons.SCATTER).ticks_between_shots)
	assert_eq(_hits(_run(1, 0, [Action.FIRE])).size(), 1, "the host can turn it on")


## A slot request on the same tick as a melee or a grenade throw used to be
## dropped (they return early).
func test_slot_request_survives_melee_and_grenade() -> void:
	for action in [Action.MELEE, Action.GRENADE]:
		var c := input.cmd(world.tick, Vector2.ZERO, 0, [action])
		c.weapon_slot = 1 - shooter.state.weapon_slot
		var want := c.weapon_slot
		world.step({1: c, 2: target_input.cmd(world.tick)})
		assert_eq(shooter.state.weapon_slot, want, "switched on the %s tick" % PlayerCommand.Action.keys()[action])
		_run(60)


## Spawns are never picked from a much worse score just for variety, and a
## live grenade nearby rules a spot out.
func test_spawns_avoid_enemy_sight_and_live_grenades() -> void:
	world.remove_player(2)
	var enemy := world.add_player(3, Loadouts.make(0), "enemy", true)
	var spot := TestArenaLayout.spawn_points()[0].origin
	SimHarness.place(enemy, spot + Vector3(0, 0, -6), 0.0)  # in sight, 6 m away
	var picks := {}
	for i in 40:
		picks[world._choose_spawn(1).origin] = true
	assert_false(picks.has(spot), "never the spawn an enemy is standing next to")
	var nade := SimWorld.Projectile.new()
	nade.owner_id = 3
	nade.weapon = Weapons.at(Weapons.FRAG)
	var best := world._choose_spawn(1).origin
	nade.position = best
	world.projectiles.append(nade)
	for i in 40:
		assert_ne(world._choose_spawn(1).origin, best, "not next to a live grenade")
	world.projectiles.clear()


func test_loadout_weapons_never_run_out_and_power_weapons_do() -> void:
	var s := shooter.state
	s.mag[0] = 0
	s.reserve[0] = 0
	assert_true(s.has_reserve(0), "a loadout weapon always reloads")
	_run(1, 0, [Action.RELOAD])
	_run(Weapons.at(Weapons.SCATTER).reload_ticks * 7)
	assert_eq(s.mag[0], Weapons.at(Weapons.SCATTER).mag_size, "full from an empty reserve")
	s.set_slot(0, Weapons.RAIL, 0, 0)
	assert_false(s.has_reserve(0), "the rail's ammo is what it came with")
	_run(1, 0, [Action.RELOAD])
	_run(Weapons.at(Weapons.RAIL).reload_ticks + 5)
	assert_eq(s.mag[0], 0, "no reload from an empty reserve")
	for w: WeaponData in Weapons.ALL:
		if w.is_power_weapon:
			assert_false(w.infinite_reserve, "%s: limited ammo" % w.id)
		elif w.mag_size > 0 and w.id != &"melee" and w.id != &"frag_grenade":
			assert_true(w.infinite_reserve, "%s: infinite reserve" % w.id)
