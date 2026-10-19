class_name SimWorld
extends Node3D
## Authoritative simulation of one match (PLAN §3.2). Owns players and
## projectiles and runs one fixed tick per `step()`.
##
## Per-tick order: commands → movement → weapons → shots → projectiles →
## damage → regen → events. Presentation reads `players`, `projectiles` and
## the events returned by `drain_events()`; it never changes simulation state.

const RESPAWN_TICKS := 180
const SPAWN_PROTECTION_TICKS := 120
const RECENT_DEATH_TICKS := 300
const ENVIRONMENT_CREDIT_TICKS := 300

var tick: int = 0
var match_seed: int = 1
var movement_config: MovementConfig
var players: Dictionary = {}  ## net_id -> SimPlayer
var projectiles: Array[Projectile] = []
var spawn_points: Array[Transform3D] = []
var scores: Dictionary = {}  ## net_id -> int

var _events: Array[Dictionary] = []
var _recent_deaths: Array = []  ## [Vector3, tick]
var _rng := RandomNumberGenerator.new()
var _next_entity_gen: int = 1


class Projectile:
	var owner_id: int = 0
	var owner_gen: int = 0
	var action_seq: int = 0
	var weapon: WeaponData
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var age: int = 0

	func id() -> String:
		return "%d:%d:%d" % [owner_id, owner_gen, action_seq]


func configure(seed_value: int, movement: MovementConfig, spawns: Array[Transform3D]) -> void:
	match_seed = seed_value
	movement_config = movement
	spawn_points = spawns
	_rng.seed = seed_value


func add_player(net_id: int, weapons: Array[WeaponData], player_name: String, bot: bool) -> SimPlayer:
	var p := SimPlayer.new()
	p.name = "Player%d" % net_id
	p.display_name = player_name
	p.is_bot = bot
	add_child(p)
	p.setup(net_id, _next_entity_gen, movement_config, weapons)
	_next_entity_gen += 1
	players[net_id] = p
	scores[net_id] = 0
	_spawn(p)
	return p


func get_player(net_id: int) -> SimPlayer:
	return players.get(net_id)


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


## Advances the simulation one tick. `commands` maps net_id -> PlayerCommand;
## players without a command get a neutral one.
func step(commands: Dictionary) -> void:
	var ids := players.keys()
	ids.sort()
	for id in ids:
		var p: SimPlayer = players[id]
		var cmd: PlayerCommand = commands.get(id)
		if cmd == null:
			cmd = PlayerCommand.neutral_from(p.last_command, tick)
		p.last_command = cmd
		var executed := ActionInput.consume(p.state, cmd)
		if not p.state.alive:
			if tick >= p.state.respawn_tick:
				_spawn(p)
			continue
		for shot in PlayerSimulation.step(p, cmd, executed, match_seed):
			p.state.spawn_protection_ticks = 0
			_resolve_shot(p, shot)
	_step_projectiles()
	for id in ids:
		var s: PlayerSimState = players[id].state
		Health.tick_regen(s)
		if s.spawn_protection_ticks > 0:
			s.spawn_protection_ticks -= 1
	tick += 1


func _resolve_shot(p: SimPlayer, shot: WeaponSim.Shot) -> void:
	var w := shot.weapon
	if w.is_projectile():
		var proj := Projectile.new()
		proj.owner_id = p.net_id
		proj.owner_gen = p.entity_gen
		proj.action_seq = shot.action_seq
		proj.weapon = w
		proj.position = shot.origin
		proj.velocity = shot.direction * w.projectile_speed
		projectiles.append(proj)
		_emit("%d:%d:%d" % [p.net_id, p.entity_gen, shot.action_seq], "fire", {
			"shooter": p.net_id, "weapon": w.id, "origin": shot.origin, "direction": shot.direction,
		})
		return

	var end := shot.origin + shot.direction * w.max_range
	var world_hit := _ray(shot.origin, end)
	var max_dist := w.max_range
	var normal := Vector3.ZERO
	if not world_hit.is_empty():
		max_dist = shot.origin.distance_to(world_hit.position)
		normal = world_hit.normal
	var target: SimPlayer = null
	var best: Hitbox.Hit = null
	for other: SimPlayer in players.values():
		if other == p or not other.state.alive:
			continue
		var hit := Hitbox.intersect(other.state.position, other.state.stance, shot.origin, shot.direction, max_dist)
		if hit != null and (best == null or hit.distance < best.distance):
			best = hit
			target = other
	var hit_dist := best.distance if best != null else max_dist
	_emit("%d:%d:%d" % [p.net_id, p.entity_gen, shot.action_seq], "fire", {
		"shooter": p.net_id, "weapon": w.id, "origin": shot.origin, "direction": shot.direction,
		"end": shot.origin + shot.direction * hit_dist, "hit_player": target != null,
		"hit_world": target == null and not world_hit.is_empty(), "normal": normal,
	})
	if target != null:
		_damage(target, p.net_id, w.damage_at(best.distance), best.part == Hitbox.Part.HEAD, w, shot.action_seq)


func _step_projectiles() -> void:
	var remaining: Array[Projectile] = []
	for proj in projectiles:
		proj.age += 1
		var from := proj.position
		var to := from + proj.velocity * Sim.TICK_DT
		var seg := to - from
		var seg_len := seg.length()
		var dir := seg / seg_len
		var world_hit := _ray(from, to)
		var max_dist := seg_len
		if not world_hit.is_empty():
			max_dist = from.distance_to(world_hit.position)
		var direct: SimPlayer = null
		var best: Hitbox.Hit = null
		for other: SimPlayer in players.values():
			if other.net_id == proj.owner_id or not other.state.alive:
				continue
			var hit := Hitbox.intersect(other.state.position, other.state.stance, from, dir, max_dist)
			if hit != null and (best == null or hit.distance < best.distance):
				best = hit
				direct = other
		if direct != null:
			_explode(proj, from + dir * best.distance, direct)
		elif not world_hit.is_empty():
			_explode(proj, world_hit.position + world_hit.normal * 0.05, null)
		elif proj.age >= proj.weapon.projectile_lifetime_ticks:
			_explode(proj, to, null)
		else:
			proj.position = to
			remaining.append(proj)
	projectiles = remaining


func _explode(proj: Projectile, at: Vector3, direct: SimPlayer) -> void:
	var w := proj.weapon
	_emit("x:" + proj.id(), "explosion", {"position": at, "owner": proj.owner_id, "weapon": w.id})
	if direct != null:
		_damage(direct, proj.owner_id, w.direct_damage, false, w, proj.action_seq)
	var ids := players.keys()
	ids.sort()
	for id in ids:
		var p: SimPlayer = players[id]
		if p == direct or not p.state.alive:
			continue
		var c := Hitbox.center(p.state.position, p.state.stance)
		var d := at.distance_to(c)
		if d >= w.splash_radius or not _ray(at, c).is_empty():
			continue
		var amount := w.splash_damage * (1.0 - d / w.splash_radius)
		if p.net_id == proj.owner_id:
			amount *= w.self_damage_multiplier
		_damage(p, proj.owner_id, amount, false, w, proj.action_seq)


func _damage(target: SimPlayer, attacker_id: int, amount: float, headshot: bool, w: WeaponData, action_seq: int) -> void:
	var s := target.state
	var r := Health.apply(s, amount, headshot, w.headshot_multiplier, w.precision)
	if r.blocked or (r.shield_damage <= 0.0 and r.health_damage <= 0.0 and not r.killed):
		return
	_emit("h:%d:%d:%d:%d" % [attacker_id, action_seq, target.net_id, tick], "hit", {
		"attacker": attacker_id, "target": target.net_id, "amount": r.shield_damage + r.health_damage,
		"headshot": headshot, "shield_broken": r.shield_broken, "killed": r.killed,
	})
	if r.killed:
		_kill(target, attacker_id, w)


func _kill(victim: SimPlayer, attacker_id: int, w: WeaponData) -> void:
	var s := victim.state
	s.alive = false
	s.move_state = PlayerSimState.Move.DEAD
	s.velocity = Vector3.ZERO
	s.respawn_tick = tick + RESPAWN_TICKS
	_recent_deaths.append([s.position, tick])
	# Death attribution (PLAN §2.4): your own explosive is always a suicide.
	var suicide := attacker_id == victim.net_id
	if suicide:
		scores[victim.net_id] -= 1
	elif scores.has(attacker_id):
		scores[attacker_id] += 1
	_emit("d:%d:%d" % [victim.net_id, s.life_gen], "death", {
		"victim": victim.net_id, "killer": attacker_id, "weapon": w.id, "suicide": suicide,
		"position": s.position,
	})


func _spawn(p: SimPlayer) -> void:
	var t := _choose_spawn(p.net_id)
	var s := p.state
	s.position = t.origin
	s.velocity = Vector3.ZERO
	s.yaw = t.basis.get_euler().y
	s.pitch = 0.0
	s.move_state = PlayerSimState.Move.AIR
	s.stance = PlayerSimState.Stance.STAND
	s.sprinting = false
	s.ticks_since_floor = 0
	s.jump_buffer_ticks = 0
	s.air_jumps_left = 1
	s.slide_ticks = 0
	s.alive = true
	s.respawn_tick = 0
	s.spawn_protection_ticks = SPAWN_PROTECTION_TICKS
	s.life_gen += 1
	s.discontinuity_gen += 1
	s.pending_presses = PackedByteArray([0, 0, 0, 0, 0, 0, 0])
	Health.reset(s)
	s.init_weapons(p.loadout)
	p.apply_stance_shape(s.stance)
	p.global_position = s.position
	_emit("s:%d:%d" % [p.net_id, s.life_gen], "spawn", {"player": p.net_id, "position": s.position, "yaw": s.yaw})


## Server-side spawn scoring (PLAN §2.5): far from enemies, out of their sight,
## away from recent deaths, never occupied. Picks randomly among the top 3.
func _choose_spawn(for_id: int) -> Transform3D:
	if spawn_points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	_recent_deaths = _recent_deaths.filter(func(d: Array) -> bool: return tick - d[1] <= RECENT_DEATH_TICKS)
	var scored: Array = []
	for i in spawn_points.size():
		var pos := spawn_points[i].origin
		var nearest := 50.0
		var visible := 0
		var occupied := false
		for other: SimPlayer in players.values():
			if other.net_id == for_id or not other.state.alive:
				continue
			var d := pos.distance_to(other.state.position)
			nearest = minf(nearest, d)
			occupied = occupied or d < 2.0
			if _ray(pos + Vector3(0.0, 1.6, 0.0), other.eye_position()).is_empty():
				visible += 1
		var recent := 0
		for d in _recent_deaths:
			if pos.distance_to(d[0]) < 8.0:
				recent += 1
		var score := nearest - visible * 15.0 - recent * 10.0 - (100.0 if occupied else 0.0)
		scored.append([score, i])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var pick: int = scored[_rng.randi_range(0, mini(3, scored.size()) - 1)][1]
	return spawn_points[pick]


func _emit(id: String, type: String, data: Dictionary) -> void:
	data["id"] = id
	data["type"] = type
	data["tick"] = tick
	_events.append(data)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, Sim.LAYER_WORLD))
