class_name WeaponSim
extends RefCounted
## Per-tick weapon state machine (PLAN §2.3): fire modes, reload, switching.
## Produces shot requests; the world resolves hits and damage.

const Action := PlayerCommand.Action
const FireMode := WeaponData.FireMode


class Shot:
	var weapon: WeaponData
	var action_seq: int = 0
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD


static func step(p: SimPlayer, cmd: PlayerCommand, executed: int, match_seed: int) -> Array[Shot]:
	var shots: Array[Shot] = []
	var s := p.state
	if not s.alive or p.loadout.is_empty():
		return shots

	var requested := s.weapon_slot
	if cmd.weapon_slot >= 0 and cmd.weapon_slot < p.loadout.size():
		requested = cmd.weapon_slot
	elif ActionInput.has(executed, Action.SWITCH):
		requested = (s.weapon_slot + 1) % p.loadout.size()
	if requested != s.weapon_slot:
		s.reload[s.weapon_slot] = 0
		s.burst_left[s.weapon_slot] = 0
		s.weapon_slot = requested
		s.switch_ticks = p.loadout[requested].raise_ticks

	var w := s.weapon_slot
	var data := p.loadout[w]
	if s.switch_ticks > 0:
		s.switch_ticks -= 1
	if s.cooldown[w] > 0:
		s.cooldown[w] -= 1
	if s.reload[w] > 0:
		s.reload[w] -= 1
		if s.reload[w] == 0:
			var take := mini(data.mag_size - s.mag[w], s.reserve[w])
			s.mag[w] += take
			s.reserve[w] -= take

	if ActionInput.has(executed, Action.RELOAD):
		_start_reload(s, w, data)

	# Remaining rounds of a burst fire on their own schedule.
	if s.burst_left[w] > 0:
		s.burst_timer[w] -= 1
		if s.burst_timer[w] <= 0:
			if s.mag[w] > 0 and s.reload[w] == 0:
				shots.append(_fire(p, w, data, match_seed))
				s.burst_left[w] -= 1
				s.burst_timer[w] = data.burst_spacing_ticks
			else:
				s.burst_left[w] = 0
		return shots

	var trigger := false
	if data.fire_mode == FireMode.AUTO:
		trigger = cmd.is_held(PlayerCommand.Held.FIRE)
	else:
		trigger = ActionInput.has(executed, Action.FIRE)
	if not trigger:
		return shots

	var can_fire := s.switch_ticks == 0 and s.reload[w] == 0 and s.cooldown[w] == 0 \
			and not s.sprinting and s.move_state != PlayerSimState.Move.MANTLE
	if not can_fire:
		return shots
	if s.mag[w] <= 0:
		_start_reload(s, w, data)
		return shots

	shots.append(_fire(p, w, data, match_seed))
	s.cooldown[w] = data.ticks_between_shots
	if data.fire_mode == FireMode.BURST and data.burst_count > 1:
		s.burst_left[w] = data.burst_count - 1
		s.burst_timer[w] = data.burst_spacing_ticks
	return shots


static func _start_reload(s: PlayerSimState, w: int, data: WeaponData) -> void:
	if s.reload[w] == 0 and s.mag[w] < data.mag_size and s.reserve[w] > 0:
		s.reload[w] = data.reload_ticks
		s.burst_left[w] = 0


static func _fire(p: SimPlayer, w: int, data: WeaponData, match_seed: int) -> Shot:
	var s := p.state
	s.action_seq += 1
	s.mag[w] -= 1
	var shot := Shot.new()
	shot.weapon = data
	shot.action_seq = s.action_seq
	shot.origin = p.eye_position()
	shot.direction = spread_direction(aim_direction(s.yaw, s.pitch), data.spread_degrees,
			Sim.hash_ints([match_seed, p.net_id, p.entity_gen, s.action_seq]))
	return shot


static func aim_direction(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## Deterministic random direction inside a cone of `spread_degrees` around `dir`.
static func spread_direction(dir: Vector3, spread_degrees: float, seed_value: int) -> Vector3:
	if spread_degrees <= 0.0:
		return dir
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var angle := rng.randf() * TAU
	var radius := deg_to_rad(spread_degrees) * sqrt(rng.randf())
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	return (dir + (right * cos(angle) + up * sin(angle)) * tan(radius)).normalized()
