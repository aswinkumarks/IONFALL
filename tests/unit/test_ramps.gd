extends GutTest
## Every ramp on every map can be climbed however a player gets onto it:
## walking on, jumping on from the front (jump held, as players do), jumping
## on from the side, and jumping while already on it. Ramps are the tilted
## boxes in each map's collision.

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action
const TICKS := 300  ## 5 s: plenty for 8 m of ramp

var world: SimWorld
var input: SimHarness.CommandScript


## [low end, high end, right, half width] of each ramp's top surface.
func _ramps(gameplay: Node) -> Array:
	var out := []
	for cs: CollisionShape3D in gameplay.find_children("*", "CollisionShape3D", true, false):
		var box := cs.shape as BoxShape3D
		if box == null:
			continue
		var t := cs.global_transform
		var up := t.basis.y.normalized()
		var tilt := rad_to_deg(acos(clampf(absf(up.y), 0.0, 1.0)))
		if tilt < 10.0 or tilt > 40.0:
			continue
		var top := t.origin + up * signf(up.y) * box.size.y * 0.5
		# The slope runs along whichever horizontal box axis tilts.
		var slope_x := absf(t.basis.x.normalized().y) > absf(t.basis.z.normalized().y)
		var along := (t.basis.x.normalized() * box.size.x if slope_x else t.basis.z.normalized() * box.size.z) * 0.5
		var across := t.basis.z.normalized() if slope_x else t.basis.x.normalized()
		var a := top + along
		var b := top - along
		out.append([a if a.y < b.y else b, b if a.y < b.y else a, across, (box.size.z if slope_x else box.size.x) * 0.5])
	return out


## A player fits at `from` and can walk straight to `to` (knee height).
func _reachable(from: Vector3, to: Vector3) -> bool:
	var space := world.get_world_3d().direct_space_state
	var body := CapsuleShape3D.new()
	body.radius = 0.4
	body.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = body
	q.collision_mask = Sim.LAYER_WORLD
	q.transform = Transform3D(Basis(), from + Vector3.UP * 0.95)
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var a := from + Vector3.UP * 0.3
	var b := Vector3(to.x, a.y, to.z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, Sim.LAYER_WORLD))
	return hit.is_empty() or a.distance_to(hit.position) >= a.distance_to(b) - 0.15


static func _yaw_towards(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _run(p: SimPlayer, ticks: int, move: Vector2, held: int, press_at: Dictionary = {}) -> void:
	for i in ticks:
		var press: Array = press_at.get(i, [])
		world.step({p.net_id: input.cmd(world.tick, move, held, press)})


## Climbs from `start` facing `face`; `script` runs first (jumps, turns).
func _climbed(p: SimPlayer, ramp: Array, start: Vector3, face: Vector3, script: Callable) -> bool:
	SimHarness.place(p, start, _yaw_towards(face))
	input.yaw = _yaw_towards(face)
	_run(p, 2, Vector2.ZERO, 0)
	script.call(p)
	var up: Vector3 = (ramp[1] - ramp[0]) * Vector3(1, 0, 1)
	input.yaw = _yaw_towards(up)
	for i in TICKS:
		world.step({p.net_id: input.cmd(world.tick, Vector2(0, 1), 0)})
		if p.state.position.y > (ramp[1] as Vector3).y - 0.4:
			return true
	return false


func test_every_ramp_can_be_climbed() -> void:
	for id: String in Maps.PLAYABLE:
		var gameplay: Node3D = Maps.gameplay(id)
		add_child_autofree(gameplay)
		world = SimWorld.new()
		world.configure(7, SimHarness.MOVEMENT, gameplay.spawn_points())
		add_child_autofree(world)
		await wait_physics_frames(2)
		input = SimHarness.CommandScript.new()
		var p := world.add_player(1, SimHarness.loadout(), "climber", false)
		var ramps := _ramps(gameplay)
		assert_gt(ramps.size(), 0, "%s has ramps" % id)
		var checked := 0
		for r: Array in ramps:
			var low: Vector3 = r[0]
			var high: Vector3 = r[1]
			var up: Vector3 = ((high - low) * Vector3(1, 0, 1)).normalized()
			var right: Vector3 = r[2]
			var mid := low.lerp(high, 0.25)  # about 1 m up: within a jump from the floor
			var name := "%s ramp %s→%s" % [id, low.snapped(Vector3.ONE * 0.1), high.snapped(Vector3.ONE * 0.1)]
			if low.y < 0.3:  # its foot is on the floor
				if _reachable(low - up * 2.0, low):
					checked += 1
					assert_true(_climbed(p, r, low - up * 2.0 + Vector3.UP * 0.05, up, func(_p: SimPlayer) -> void: pass),
							"%s: walk on" % name)
				if _reachable(low - up * 3.5, low):
					checked += 1
					assert_true(_climbed(p, r, low - up * 3.5 + Vector3.UP * 0.05, up, func(q: SimPlayer) -> void:
						_run(q, 30, Vector2(0, 1), Held.SPRINT | Held.JUMP, {12: [Action.JUMP]})), "%s: jump on from the front" % name)
				for side in [-1.0, 1.0]:
					# Up along the edge, and jumping on at an angle.
					var hug: Vector3 = low + right * side * ((r[3] as float) - 0.45)
					if _reachable(hug - up * 2.0, hug):
						checked += 1
						assert_true(_climbed(p, r, hug - up * 2.0 + Vector3.UP * 0.05, up, func(_p: SimPlayer) -> void: pass),
								"%s: walk up the edge (%+d)" % [name, side])
					var slant: Vector3 = (up - right * side * 0.7).normalized()
					var from_slant: Vector3 = low.lerp(high, 0.15) - slant * 3.0
					from_slant.y = low.y + 0.05
					if _reachable(from_slant, low.lerp(high, 0.15)):
						checked += 1
						assert_true(_climbed(p, r, from_slant, slant, func(q: SimPlayer) -> void:
							_run(q, 30, Vector2(0, 1), Held.SPRINT | Held.JUMP, {10: [Action.JUMP]})),
								"%s: jump on at an angle (%+d)" % [name, side])
				for side in [-1.0, 1.0]:
					var edge: Vector3 = mid + right * side * (r[3] as float)
					var from: Vector3 = mid + right * side * ((r[3] as float) + 1.2)
					from.y = low.y + 0.05
					if not _reachable(from, edge):
						continue
					checked += 1
					assert_true(_climbed(p, r, from, -right * side, func(q: SimPlayer) -> void:
						_run(q, 40, Vector2(0, 1), Held.JUMP, {3: [Action.JUMP]})), "%s: jump on from the side (%+d)" % [name, side])
			assert_true(_climbed(p, r, low.lerp(high, 0.2) + Vector3.UP * 0.1, up, func(q: SimPlayer) -> void:
				_run(q, 40, Vector2(0, 1), Held.JUMP, {10: [Action.JUMP]})), "%s: jump while on it" % name)
		gut.p("%s: %d ramps, %d approaches from the floor" % [id, ramps.size(), checked])
		gameplay.queue_free()
		world.queue_free()
		await wait_physics_frames(2)
