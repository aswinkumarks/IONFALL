class_name WeaponSim
extends RefCounted
## Per-tick weapon state machine (PLAN §2.3): fire modes, reload, switching,
## grenade throws and melee. Produces shot requests; the world resolves hits
## and damage.

const Action := PlayerCommand.Action
const FireMode := WeaponData.FireMode


## Grenades leave a little above the aim line.
const THROW_LIFT := 0.12


class Shot:
	var weapon: WeaponData
	var action_seq: int = 0
	var origin := Vector3.ZERO
	var direction := Vector3.FORWARD
	## Pellet weapons: every pellet's direction (`direction` is the first).
	var pellets: Array[Vector3] = []


static func step(p: SimPlayer, cmd: PlayerCommand, executed: int, match_seed: int) -> Array[Shot]:
	var shots: Array[Shot] = []
	var s := p.state
	if not s.alive or s.weapons.is_empty():
		return shots
	if s.throw_cooldown > 0:
		s.throw_cooldown -= 1
	if s.melee_cooldown > 0:
		s.melee_cooldown -= 1
	_settle_recoil(s)
	var busy := s.sprinting or s.move_state == PlayerSimState.Move.MANTLE

	# Switching first: a slot request lives in one command only, and the
	# melee and grenade early returns below used to drop it.
	var requested := s.weapon_slot
	if cmd.weapon_slot >= 0 and cmd.weapon_slot < s.weapons.size():
		requested = cmd.weapon_slot
	elif ActionInput.has(executed, Action.SWITCH):
		requested = (s.weapon_slot + 1) % s.weapons.size()
	if requested != s.weapon_slot:
		s.reload[s.weapon_slot] = 0
		s.burst_left[s.weapon_slot] = 0
		s.weapon_slot = requested
		s.switch_ticks = s.weapon(requested).raise_ticks

	# Melee and grenades work with any weapon up (not while mantling).
	if ActionInput.has(executed, Action.MELEE) and s.melee_cooldown == 0 and s.move_state != PlayerSimState.Move.MANTLE:
		var melee := Weapons.at(Weapons.MELEE)
		s.melee_cooldown = melee.ticks_between_shots
		shots.append(_shot(p, melee, aim_direction(s.aim_yaw(), s.aim_pitch())))
		return shots
	if ActionInput.has(executed, Action.GRENADE) and s.grenades > 0 and s.throw_cooldown == 0 \
			and s.move_state != PlayerSimState.Move.MANTLE:
		s.grenades -= 1
		s.throw_cooldown = Balance.PLAYER.throw_cooldown_ticks
		var aim := aim_direction(s.aim_yaw(), s.aim_pitch())
		shots.append(_shot(p, Weapons.at(Weapons.FRAG), (aim + Vector3.UP * THROW_LIFT).normalized()))
		return shots

	var w := s.weapon_slot
	var data := s.weapon()
	if s.switch_ticks > 0:
		s.switch_ticks -= 1
	if s.cooldown[w] > 0:
		s.cooldown[w] -= 1
	if s.reload[w] > 0:
		s.reload[w] -= 1
		if s.reload[w] == 0:
			var take := data.mag_size - s.mag[w]
			if not data.infinite_reserve:
				take = mini(take, s.reserve[w])
			if data.reload_per_round:
				take = mini(take, 1)
			s.mag[w] += take
			if not data.infinite_reserve:
				s.reserve[w] -= take
			if data.reload_per_round:
				_start_reload(s, w, data)  # next shell

	if ActionInput.has(executed, Action.RELOAD):
		_start_reload(s, w, data)

	# Remaining rounds of a burst fire on their own schedule.
	if s.burst_left[w] > 0:
		s.burst_timer[w] -= 1
		if s.burst_timer[w] <= 0:
			if s.mag[w] > 0 and s.reload[w] == 0:
				shots.append(_fire(p, w, data, match_seed, is_scoped(s, cmd)))
				s.burst_left[w] -= 1
				s.burst_timer[w] = data.burst_spacing_ticks
			else:
				s.burst_left[w] = 0
		return shots

	# A fresh press always fires (a tap can start and end within one tick);
	# automatic weapons also keep firing while the trigger is held.
	var trigger := ActionInput.has(executed, Action.FIRE)
	if data.fire_mode == FireMode.AUTO:
		trigger = trigger or cmd.is_held(PlayerCommand.Held.FIRE)
	if not trigger:
		return shots

	# Shells: a loaded round can interrupt the reload.
	if data.reload_per_round and s.reload[w] > 0 and s.mag[w] > 0:
		s.reload[w] = 0
	var can_fire := s.switch_ticks == 0 and s.reload[w] == 0 and s.cooldown[w] == 0 and not busy
	if not can_fire:
		return shots
	if s.mag[w] <= 0:
		_start_reload(s, w, data)
		return shots

	shots.append(_fire(p, w, data, match_seed, is_scoped(s, cmd)))
	s.cooldown[w] = data.ticks_between_shots
	if data.fire_mode == FireMode.BURST and data.burst_count > 1:
		s.burst_left[w] = data.burst_count - 1
		s.burst_timer[w] = data.burst_spacing_ticks
	return shots


static func _start_reload(s: PlayerSimState, w: int, data: WeaponData) -> void:
	if s.reload[w] == 0 and s.mag[w] < data.mag_size and (data.infinite_reserve or s.reserve[w] > 0):
		s.reload[w] = data.reload_ticks
		s.burst_left[w] = 0


## Scoped (PLAN §2.3): aim held with a scoped weapon that's up and not
## reloading. Tighter spread, slower movement, no sprint.
static func is_scoped(s: PlayerSimState, cmd: PlayerCommand) -> bool:
	return cmd.is_held(PlayerCommand.Held.AIM) and can_scope(s)


## Whether aiming would scope right now (also used by the view).
static func can_scope(s: PlayerSimState) -> bool:
	var data := s.weapon()
	return s.alive and data != null and data.scope_zoom > 1.0 and s.switch_ticks == 0 \
			and s.reload[s.weapon_slot] == 0 and s.move_state != PlayerSimState.Move.MANTLE


static func _fire(p: SimPlayer, w: int, data: WeaponData, match_seed: int, scoped: bool = false) -> Shot:
	var s := p.state
	s.mag[w] -= 1
	var aim := aim_direction(s.aim_yaw(), s.aim_pitch())
	var shot := _shot(p, data, aim)
	_kick(s, data, Sim.hash_ints([match_seed, p.net_id, p.entity_gen, s.action_seq, 0x7EC0]), scoped)
	var spread := data.spread_degrees * (data.scope_spread if scoped else 1.0)
	for i in maxi(data.pellets, 1):
		var seed_value := Sim.hash_ints([match_seed, p.net_id, p.entity_gen, s.action_seq, i])
		if data.pellets <= 1:
			seed_value = Sim.hash_ints([match_seed, p.net_id, p.entity_gen, s.action_seq])
		shot.pellets.append(spread_direction(aim, spread, seed_value))
	shot.direction = shot.pellets[0]
	return shot


## Recoil: the held weapon's settle back towards the look direction, once
## the hold after the last shot is over.
static func _settle_recoil(s: PlayerSimState) -> void:
	if s.recoil_hold > 0:
		s.recoil_hold -= 1
		return
	var data := s.weapon()
	if data != null and s.recoil != Vector2.ZERO:
		s.recoil = s.recoil.move_toward(Vector2.ZERO, deg_to_rad(data.recoil_recovery_degrees_per_second) / Sim.TICK_RATE)


## Recoil: one shot's kick, up and to a side chosen by `seed_value`.
static func _kick(s: PlayerSimState, data: WeaponData, seed_value: int, scoped: bool) -> void:
	if data.recoil_kick_degrees <= 0.0 and data.recoil_side_degrees <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var scale := data.recoil_scoped if scoped else 1.0
	var kick := Vector2(rng.randf_range(-1.0, 1.0) * data.recoil_side_degrees, data.recoil_kick_degrees)
	s.recoil = (s.recoil + kick * deg_to_rad(1.0) * scale).limit_length(deg_to_rad(data.recoil_max_degrees))
	s.recoil_hold = data.recoil_recovery_delay_ticks


## A new action from the eye along `direction`.
static func _shot(p: SimPlayer, data: WeaponData, direction: Vector3) -> Shot:
	p.state.action_seq += 1
	var shot := Shot.new()
	shot.weapon = data
	shot.action_seq = p.state.action_seq
	shot.origin = p.eye_position()
	shot.direction = direction
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
