class_name JumpPads
extends RefCounted
## Jump pads (PLAN §2.1): a pad is a trigger zone on the floor that throws a
## grounded player on a fixed arc to its landing point. A map lists its pads
## as {position (pad centre on the floor), target (landing point on the
## floor)}; the gameplay scene turns each into an Area3D on LAYER_PAD, so
## the server, client-side prediction and replays all see the same zones.

const RADIUS := 1.0
const HEIGHT := 0.6
## Peak of the arc above the higher of the take-off and landing heights.
const APEX := 2.5


## The trigger zone for `pad`, for the map's gameplay scene.
static func make_area(pad: Dictionary) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = Sim.LAYER_PAD
	area.collision_mask = 0
	area.monitoring = false
	area.position = pad.position
	area.set_meta("target", pad.target)
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = HEIGHT * 0.5
	area.add_child(cs)
	return area


## The landing point of the pad under `feet`, or Vector3.INF.
static func target_at(space: PhysicsDirectSpaceState3D, feet: Vector3) -> Vector3:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = feet + Vector3(0.0, 0.05, 0.0)
	q.collision_mask = Sim.LAYER_PAD
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hits := space.intersect_point(q, 1)
	if hits.is_empty():
		return Vector3.INF
	return (hits[0].collider as Node).get_meta("target")


## Initial velocity that carries a body from `from` to `to` under `gravity`,
## peaking APEX above the higher of the two.
static func launch_velocity(from: Vector3, to: Vector3, gravity: float) -> Vector3:
	var top := maxf(from.y, to.y) + APEX
	var vy := sqrt(2.0 * gravity * (top - from.y))
	var t := vy / gravity + sqrt(2.0 * (top - to.y) / gravity)
	return Vector3((to.x - from.x) / t, vy, (to.z - from.z) / t)
