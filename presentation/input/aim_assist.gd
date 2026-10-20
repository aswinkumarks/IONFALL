class_name AimAssist
extends RefCounted
## Touch aim assist (PLAN §3.11). Presentation only: it changes the look
## input a touch player produces, never the simulation.
## - Candidate (refreshed at 10 Hz): the enemy nearest the crosshair within a
##   6° cone and the weapon's range, weighted by distance.
## - Visibility is rechecked with one ray whenever assist applies, so a
##   cached candidate never pulls through a wall.
## - Slowdown: look sensitivity × 0.6 while the crosshair is over the target.
## - Magnetism: while firing, follow at most 25% of the target's angular
##   velocity. No snapping.
## - Auto-fire (option): automatic and burst weapons fire 7 ticks after the
##   crosshair lands on a visible target; never the sniper, launcher or
##   grenades.

const CONE_DEGREES := 6.0
const SLOWDOWN := 0.6
const MAGNETISM := 0.25
const AUTO_FIRE_TICKS := 7
const REFRESH_SECONDS := 0.1
const BODY_RADIUS := 0.35  ## metres around the chest that count as "over"

var slowdown: float = 1.0  ## multiply touch look sensitivity by this
var wants_fire: bool = false  ## auto-fire is holding the trigger

var _target: int = -1
var _refresh: float = 0.0
var _last_angles := Vector2.INF
var _on_target: float = 0.0


## `targets`: id -> enemy chest position (as rendered). Returns the look
## delta (yaw, pitch) magnetism adds this frame.
func update(delta: float, eye: Transform3D, weapon: WeaponData, firing: bool, auto_fire: bool, targets: Dictionary,
		space: PhysicsDirectSpaceState3D) -> Vector2:
	slowdown = 1.0
	wants_fire = false
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SECONDS
		_target = _pick(eye, weapon, targets)
	if _target < 0 or not targets.has(_target) or weapon == null:
		_reset()
		return Vector2.ZERO
	var chest: Vector3 = targets[_target]
	var to := chest - eye.origin
	var dist := to.length()
	var forward := -eye.basis.z
	if rad_to_deg(forward.angle_to(to)) > CONE_DEGREES * 1.5 or dist > _range(weapon):
		_reset()
		return Vector2.ZERO
	# Visible right now?
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye.origin, chest, Sim.LAYER_WORLD))
	if not hit.is_empty():
		_reset()
		return Vector2.ZERO
	var over := forward.angle_to(to) < atan2(BODY_RADIUS, maxf(dist, 0.5))
	if over:
		slowdown = SLOWDOWN
		_on_target += delta
	else:
		_on_target = 0.0
	var auto_ok := weapon.fire_mode == WeaponData.FireMode.AUTO or weapon.fire_mode == WeaponData.FireMode.BURST
	wants_fire = auto_fire and auto_ok and over and _on_target >= AUTO_FIRE_TICKS / float(Sim.TICK_RATE)
	# Magnetism: a share of the target's angular motion, while firing.
	var angles := Vector2(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))
	var pull := Vector2.ZERO
	if firing and _last_angles != Vector2.INF:
		pull = Vector2(angle_difference(_last_angles.x, angles.x), angles.y - _last_angles.y) * MAGNETISM
	_last_angles = angles
	return pull


func _reset() -> void:
	_on_target = 0.0
	_last_angles = Vector2.INF


func _pick(eye: Transform3D, weapon: WeaponData, targets: Dictionary) -> int:
	if weapon == null:
		return -1
	var forward := -eye.basis.z
	var best := -1
	var best_score := INF
	for id: int in targets:
		var to: Vector3 = (targets[id] as Vector3) - eye.origin
		var dist := to.length()
		var angle := rad_to_deg(forward.angle_to(to))
		if angle > CONE_DEGREES or dist > _range(weapon):
			continue
		var score := angle * (1.0 + dist / 30.0)
		if score < best_score:
			best_score = score
			best = id
	return best


## Effective range: where damage stops falling off (pellets: full damage).
static func _range(weapon: WeaponData) -> float:
	return minf(weapon.max_range, weapon.min_damage_range if weapon.pellets <= 1 else weapon.full_damage_range * 2.0)
