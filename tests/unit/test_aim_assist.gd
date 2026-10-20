extends GutTest
## Touch aim assist (PLAN §3.11): slowdown over a visible target, magnetism
## of at most 25% of its angular velocity while firing, auto-fire after 7
## ticks for automatic weapons only, and nothing through walls.

const DT := 1.0 / 60.0

var space: PhysicsDirectSpaceState3D
var eye := Transform3D.IDENTITY  ## at the origin, looking down -Z


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	await wait_physics_frames(1)
	space = root.get_world_3d().direct_space_state


func _wall() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Sim.LAYER_WORLD
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(4, 4, 0.2)
	body.add_child(shape)
	body.position = Vector3(0, 0, -5)
	add_child_autofree(body)
	await wait_physics_frames(2)
	space = body.get_world_3d().direct_space_state


func test_slowdown_and_auto_fire() -> void:
	var aa := AimAssist.new()
	var targets := {7: Vector3(0.05, 0, -10)}
	aa.update(DT, eye, Loadouts.PULSE, false, true, targets, space)
	assert_eq(aa.slowdown, AimAssist.SLOWDOWN, "crosshair over the target")
	for i in AimAssist.AUTO_FIRE_TICKS:
		aa.update(DT, eye, Loadouts.PULSE, false, true, targets, space)
	assert_true(aa.wants_fire, "auto-fire after 7 ticks on target")
	aa.update(DT, eye, Loadouts.RAIL, false, true, targets, space)
	assert_false(aa.wants_fire, "never the sniper")
	var off := {7: Vector3(5, 0, -10)}  # ~27° away
	aa._refresh = 0.0
	aa.update(DT, eye, Loadouts.PULSE, false, true, off, space)
	assert_eq(aa.slowdown, 1.0, "outside the cone: no assist")


func test_magnetism_follows_a_quarter() -> void:
	var aa := AimAssist.new()
	aa.update(DT, eye, Loadouts.PULSE, true, false, {1: Vector3(0, 0, -10)}, space)
	var pull := aa.update(DT, eye, Loadouts.PULSE, true, false, {1: Vector3(0.1, 0, -10)}, space)
	var target_turn := atan2(-0.1, 10.0)
	assert_almost_eq(pull.x, target_turn * AimAssist.MAGNETISM, 1e-4, "25% of the target's angular motion")
	var idle := aa.update(DT, eye, Loadouts.PULSE, false, false, {1: Vector3(0.2, 0, -10)}, space)
	assert_eq(idle, Vector2.ZERO, "no magnetism without firing")


func test_no_assist_through_walls() -> void:
	await _wall()
	var aa := AimAssist.new()
	aa.update(DT, eye, Loadouts.PULSE, true, true, {1: Vector3(0, 0, -10)}, space)
	assert_eq(aa.slowdown, 1.0)
	assert_false(aa.wants_fire)
