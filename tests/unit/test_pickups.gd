extends GutTest
## Pickups (PLAN §2.3): power weapons replace the primary, which drops; a
## dead player's power weapon drops with its ammo and despawns after 20 s;
## a spot's timer starts only when its previous instance is gone; grenades
## +1 up to 2; contention goes to the closest player.

const Action := PlayerCommand.Action
const RAIL_SPOT := Vector3(4, 0, 17)
const GRENADE_SPOT := Vector3(-4, 0, 17)

var world: SimWorld
var a: SimPlayer
var b: SimPlayer
var input_a: SimHarness.CommandScript
var input_b: SimHarness.CommandScript


func before_each() -> void:
	add_child_autofree(SimHarness.make_arena())
	world = SimHarness.make_world()
	world.pickups_enabled = true
	world.configure(7, SimHarness.MOVEMENT, TestArenaLayout.spawn_points(), [
		{"weapon": &"rail_sniper", "position": RAIL_SPOT, "respawn_ticks": 600},
		{"weapon": &"grenade", "position": GRENADE_SPOT, "respawn_ticks": 300},
	])
	add_child_autofree(world)
	await wait_physics_frames(2)
	a = world.add_player(1, Loadouts.make(0), "A", false)
	b = world.add_player(2, Loadouts.make(1), "B", false)
	input_a = SimHarness.CommandScript.new()
	input_b = SimHarness.CommandScript.new()
	SimHarness.place(a, Vector3(10, 0.05, 10), 0.0)
	SimHarness.place(b, Vector3(-10, 0.05, 10), 0.0)
	_run(5)


func _run(ticks: int, press_a: Array = []) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in ticks:
		world.step({1: input_a.cmd(world.tick, Vector2.ZERO, 0, press_a if i == 0 else []), 2: input_b.cmd(world.tick)})
		events.append_array(world.drain_events())
	return events


func _item(weapon: int) -> SimWorld.Item:
	for it in world.items:
		if it.weapon == weapon:
			return it
	return null


func test_power_weapon_replaces_primary_and_it_drops() -> void:
	assert_not_null(_item(Weapons.RAIL), "the rail is on its spot")
	SimHarness.place(a, RAIL_SPOT + Vector3(0, 0.05, 0), 0.0)
	var events := _run(2)
	assert_eq(a.state.weapons[0], Weapons.RAIL, "auto pickup into the primary slot")
	assert_eq(a.state.mag[0], Loadouts.RAIL.mag_size)
	assert_eq(a.state.weapon_slot, 0)
	assert_null(_item(Weapons.RAIL))
	var dropped := _item(Weapons.PULSE)
	assert_not_null(dropped, "the loadout primary drops")
	assert_between(dropped.despawn_tick - world.tick, Balance.PLAYER.drop_despawn_ticks - 2, Balance.PLAYER.drop_despawn_ticks,
			"and despawns in 20 s")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "pickup").size(), 1)
	assert_eq(world.spot_ticks_left(0), 0, "no timer while the rail is held")
	_run(5)
	assert_eq(a.state.weapons[0], Weapons.RAIL, "the dropped primary needs interact")
	_run(1, [Action.INTERACT])
	assert_eq(a.state.weapons[0], Weapons.PULSE, "interact swaps back")
	assert_not_null(_item(Weapons.RAIL), "and the rail drops")


func test_dead_player_drops_power_weapon_then_spot_timer() -> void:
	SimHarness.place(a, RAIL_SPOT + Vector3(0, 0.05, 0), 0.0)
	_run(2)
	SimHarness.place(a, Vector3(10, 0.05, 10), 0.0)
	a.state.mag[0] = 1
	world._kill(a, 2, Loadouts.PULSE, false)
	var drop := _item(Weapons.RAIL)
	assert_not_null(drop, "the rail drops on death")
	assert_eq(drop.mag + drop.reserve, 1 + Loadouts.RAIL.reserve, "with its remaining ammo")
	assert_eq(world.spot_ticks_left(0), 0, "the instance still exists")
	_run(Balance.PLAYER.drop_despawn_ticks + 1)
	assert_null(_item(Weapons.RAIL), "despawned after 20 s")
	assert_gt(world.spot_ticks_left(0), 0, "now the spot's timer runs")
	_run(world.spot_ticks_left(0) + 1)
	assert_not_null(_item(Weapons.RAIL), "and a new one appears")


func test_grenades_cap_at_two() -> void:
	SimHarness.place(a, GRENADE_SPOT + Vector3(0, 0.05, 0), 0.0)
	_run(2)
	assert_not_null(_item(-1), "full: left on the floor")
	a.state.grenades = 1
	_run(1)
	assert_eq(a.state.grenades, 2)
	assert_null(_item(-1))
	assert_gt(world.spot_ticks_left(1), 0)


func test_contention_goes_to_the_closest() -> void:
	SimHarness.place(a, RAIL_SPOT + Vector3(0.9, 0.05, 0), 0.0)
	SimHarness.place(b, RAIL_SPOT + Vector3(-0.3, 0.05, 0), 0.0)
	_run(1)
	assert_eq(b.state.weapons[0], Weapons.RAIL, "B was closer")
	assert_ne(a.state.weapons[0], Weapons.RAIL)
