class_name SimWorld
extends Node3D
## Authoritative simulation of one match (PLAN §3.2). Owns players and
## projectiles and runs one fixed tick per `step()`.
##
## Per-tick order: commands → movement → weapons → shots → projectiles →
## damage → regen → events. Presentation reads `players`, `projectiles` and
## the events returned by `drain_events()`; it never changes simulation state.

## Balance values (respawn delays, spawn protection, assists, melee cone,
## pickups, CTF) come from Balance (data/player.tres, data/modes.tres).

## Spawns this close to the best score are picked at random (PLAN §2.5).
const SPAWN_SCORE_MARGIN := 6.0
const RECENT_DEATH_TICKS := 300
const ENVIRONMENT_CREDIT_TICKS := 300
## Falling below this height is an environmental death.
const KILL_Y := -30.0

var tick: int = 0
var match_seed: int = 1
var movement_config: MovementConfig
var players: Dictionary = {}  ## net_id -> SimPlayer
var projectiles: Array[Projectile] = []
var spawn_points: Array[Transform3D] = []
var scores: Dictionary = {}  ## net_id -> int
## TDM (PLAN §2.4): team scores; kills score for the killer's team.
var team_scores := PackedInt32Array([0, 0])
var respawn_ticks: int = Balance.MODES.ffa_respawn_ticks
## Players block each other (PLAN §2.2): overlapping living players are
## pushed apart every tick (_separate_players).
var player_collision: bool = true
## Off outside the PLAYING phase (PLAN §3.4: no damage in countdown/lobby).
var damage_enabled: bool = true
## Lag compensation (PLAN §3.3.4). Off in offline play.
var lag_compensation: bool = false
## TDM (PLAN §2.4): SimPlayer.team matters; friendly fire is a host setting.
var teams_enabled: bool = false
var friendly_fire: bool = false
var history: Dictionary = {}  ## net_id -> HitboxHistory
## The same history and hitbox tests in native code (native/, PLAN §3.17)
## when the extension is loaded; null otherwise (always on the web). It gives
## the same hits (tests/unit/test_hitbox_native.gd), so either can run.
var native_rewind: RefCounted = ClassDB.instantiate(&"HitboxRewindNative") if ClassDB.class_exists(&"HitboxRewindNative") else null

## Pickups (PLAN §2.3), run by the server only (clients learn the result
## from snapshots). Spots: {weapon (StringName, &"grenade"), position,
## respawn_ticks}; `spot_respawn[i]` is the tick its next instance appears,
## 0 while one exists (on the floor, held or dropped).
var pickups_enabled: bool = false
var pickup_spots: Array = []
var spot_respawn := PackedInt32Array()
var items: Array[Item] = []
var _held_spot: Dictionary = {}  ## net_id -> spot of the power weapon it holds
var _next_item_id: int = 1

## Capture the flag (PLAN §2.4), server only like pickups. One flag per team
## at its base; kills then score for the killer only, captures for the team.
var flags: Array[Flag] = []
## TDM: a kill also scores for the killer's team. Off in CTF and co-op.
var kills_score_for_team: bool = true

var _events: Array[Dictionary] = []
var _recent_deaths: Array = []  ## [Vector3, tick]
var _damage_log: Dictionary = {}  ## victim id -> Array of [attacker id, amount, tick]
var _rng := RandomNumberGenerator.new()
var _next_entity_gen: int = 1


## A weapon or grenade on the floor.
class Item:
	var id: int = 0
	var spot: int = -1  ## the spot it came from, or -1
	var weapon: int = -1  ## Weapons.ALL index; -1 = grenade
	var position := Vector3.ZERO
	var mag: int = 0
	var reserve: int = 0
	var despawn_tick: int = 0  ## 0 = stays until taken (spot items)


## A team's flag: at its base, carried, or dropped (returns on its own at
## `return_tick`).
class Flag:
	var team: int = 0
	var base := Vector3.ZERO
	var position := Vector3.ZERO
	var carrier: int = 0  ## net id, 0 = none
	var return_tick: int = 0  ## dropped: when it goes home by itself; 0 = at base or carried

	func at_base() -> bool:
		return carrier == 0 and return_tick == 0


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


## The players one shot can hit (_targets), shared by all its pellets.
class Targets:
	var shooter: SimPlayer
	var list: Array[SimPlayer] = []
	var rewind: float = -1.0  ## view tick, or -1 for "now"
	## native_rewind's inputs, in `list` order: ids and life_gens when
	## rewinding, else the current feet and stances.
	var ids := PackedInt32Array()
	var life_gens := PackedInt32Array()
	var feet := PackedVector3Array()
	var stances := PackedInt32Array()


func configure(seed_value: int, movement: MovementConfig, spawns: Array[Transform3D], spots: Array = []) -> void:
	match_seed = seed_value
	movement_config = movement
	spawn_points = spawns
	pickup_spots = spots
	_rng.seed = seed_value
	_reset_pickups()


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


## Client-side prediction body: same entity, no local spawn. Its state comes
## from the server's owner snapshot (PLAN §3.2 reconciliation).
func add_predicted_player(net_id: int, entity_gen: int, weapons: Array[WeaponData]) -> SimPlayer:
	var p := SimPlayer.new()
	p.name = "Predicted%d" % net_id
	add_child(p)
	p.setup(net_id, entity_gen, movement_config, weapons)
	players[net_id] = p
	scores[net_id] = 0
	return p


## New match on the same map: scores reset, everyone respawns (PLAN §3.4).
func reset_match(seed_value: int) -> void:
	match_seed = seed_value
	_rng.seed = seed_value
	projectiles.clear()
	_recent_deaths.clear()
	team_scores = PackedInt32Array([0, 0])
	_reset_pickups()
	for f in flags:
		_flag_home(f)
	var ids := players.keys()
	ids.sort()
	for id in ids:
		scores[id] = 0
		_spawn(players[id])


## Spawns `p` again now (its team changed, PLAN §2.5).
func respawn(p: SimPlayer) -> void:
	_spawn(p)


func remove_player(net_id: int) -> void:
	var p: SimPlayer = players.get(net_id)
	if p == null:
		return
	if p.state.alive:
		_drop_power_weapon(p)
	_drop_flag(p)
	players.erase(net_id)
	scores.erase(net_id)
	history.erase(net_id)
	if native_rewind != null:
		native_rewind.remove(net_id)
	p.queue_free()


func get_player(net_id: int) -> SimPlayer:
	return players.get(net_id)


## Moves a player instantly (bot stuck recovery, PLAN §2.7). Counts as a
## discontinuity, so nobody interpolates across it.
func teleport(p: SimPlayer, position: Vector3) -> void:
	p.state.position = position
	p.state.velocity = Vector3.ZERO
	p.state.discontinuity_gen += 1
	p.global_position = position


func drain_events() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out


## Advances the simulation one tick. `commands` maps net_id -> PlayerCommand;
## players without a command get a neutral one.
## `stalled`: ids of players whose command hasn't arrived yet. They skip
## movement and actions this tick (the server waits for the real command
## instead of guessing, so the owner's prediction stays exact).
func step(commands: Dictionary, stalled: Dictionary = {}) -> void:
	var ids := players.keys()
	ids.sort()
	var interacting := {}
	for id in ids:
		var p: SimPlayer = players[id]
		if stalled.has(id) and p.state.alive:
			continue
		var cmd: PlayerCommand = commands.get(id)
		if cmd == null:
			cmd = PlayerCommand.neutral_from(p.last_command, tick)
		p.last_command = cmd
		var executed := ActionInput.consume(p.state, cmd)
		if ActionInput.has(executed, PlayerCommand.Action.INTERACT):
			interacting[id] = true
		if not p.state.alive:
			if tick >= p.state.respawn_tick:
				_spawn(p)
			continue
		for shot in PlayerSimulation.step(p, cmd, executed, match_seed):
			p.state.spawn_protection_ticks = 0
			_resolve_shot(p, shot)
	if player_collision:
		_separate_players(ids)
	_step_projectiles()
	if pickups_enabled:
		_step_pickups(ids, interacting)
	if not flags.is_empty():
		_step_flags(ids)
	for id in ids:
		var fallen: SimPlayer = players[id]
		if fallen.state.alive and fallen.state.position.y < KILL_Y:
			_kill(fallen, 0, null, false)
	for id in ids:
		var s: PlayerSimState = players[id].state
		Health.tick_regen(s)
		if s.spawn_protection_ticks > 0:
			s.spawn_protection_ticks -= 1
		if lag_compensation and native_rewind != null:
			native_rewind.record(id, tick, s.position, s.stance, s.alive, s.life_gen, s.discontinuity_gen)
		elif lag_compensation:
			if not history.has(id):
				history[id] = HitboxHistory.new()
			history[id].record(tick, s)
	tick += 1


## Player collision: two living players closer than their radii (and
## overlapping in height) are pushed apart horizontally, mostly the one
## moving into the other (half each when neither is), through
## the world collision, and lose the velocity that pushed them together, so
## walking into someone stops you. In id order, twice, so a crowd settles.
## Clients don't predict it (they don't simulate other players): bumping
## someone gives a small, smoothed correction.
func _separate_players(ids: Array) -> void:
	for sweep in 2:
		for i in ids.size():
			var a: SimPlayer = players[ids[i]]
			if not _blocks(a):
				continue
			for j in range(i + 1, ids.size()):
				var b: SimPlayer = players[ids[j]]
				if not _blocks(b):
					continue
				var sa := a.state
				var sb := b.state
				var min_dist := a.config.capsule_radius + b.config.capsule_radius
				var d := Vector3(sb.position.x - sa.position.x, 0.0, sb.position.z - sa.position.z)
				var dist := d.length()
				if dist >= min_dist:
					continue
				if sa.position.y >= sb.position.y + b.config.height_for(sb.stance) - 0.1 \
						or sb.position.y >= sa.position.y + a.config.height_for(sa.stance) - 0.1:
					continue  # one is on top of the other
				var n := d / dist if dist > 0.0001 else Vector3.RIGHT
				# Whoever moves into the other takes the push: walking into a
				# player standing still doesn't shove them along.
				var va := maxf(sa.velocity.dot(n), 0.0)
				var vb := maxf(-sb.velocity.dot(n), 0.0)
				var share_a := va / (va + vb) if va + vb > 0.01 else 0.5
				var overlap := min_dist - dist
				_shove(a, -n * overlap * share_a)
				_shove(b, n * overlap * (1.0 - share_a))
				sa.velocity -= n * va
				sb.velocity += n * vb


## Client prediction of player collision: push our player `p` out of
## another player standing at `other` (a render state), all of the push on
## us, and drop our velocity into them. Matches the server when the other
## player isn't moving into us (it then puts the whole push on the mover).
static func push_out_of(p: SimPlayer, other: PlayerSimState) -> void:
	var s := p.state
	if not s.alive or not other.alive or s.move_state == PlayerSimState.Move.MANTLE:
		return
	var min_dist := p.config.capsule_radius * 2.0
	var d := Vector3(s.position.x - other.position.x, 0.0, s.position.z - other.position.z)
	var dist := d.length()
	if dist >= min_dist or dist < 0.0001:
		return
	if s.position.y >= other.position.y + p.config.height_for(other.stance) - 0.1 \
			or other.position.y >= s.position.y + p.config.height_for(s.stance) - 0.1:
		return
	var n := d / dist
	p.global_position = s.position
	p.move_and_collide(n * (min_dist - dist))
	s.position = p.global_position
	var into := -s.velocity.dot(n)
	if into > 0.0:
		s.velocity += n * into


func _blocks(p: SimPlayer) -> bool:
	return p.state.alive and p.state.move_state != PlayerSimState.Move.MANTLE


func _shove(p: SimPlayer, motion: Vector3) -> void:
	p.global_position = p.state.position
	p.move_and_collide(motion)
	p.state.position = p.global_position


func _resolve_shot(p: SimPlayer, shot: WeaponSim.Shot) -> void:
	var w := shot.weapon
	var action_id := "%d:%d:%d" % [p.net_id, p.entity_gen, shot.action_seq]
	if w.is_projectile():
		var proj := Projectile.new()
		proj.owner_id = p.net_id
		proj.owner_gen = p.entity_gen
		proj.action_seq = shot.action_seq
		proj.weapon = w
		proj.position = shot.origin
		proj.velocity = shot.direction * w.projectile_speed
		projectiles.append(proj)
		_emit(action_id, "fire", {
			"shooter": p.net_id, "weapon": w.id, "origin": shot.origin, "direction": shot.direction,
		})
		return
	if w.id == &"melee":
		_resolve_melee(p, shot, action_id)
		return
	# Hitscan: every pellet traced; damage summed per target (one hit each).
	var dealt := {}  ## target -> [amount, headshot]
	var first: Array = []
	var targets := _targets(p)
	for dir: Vector3 in (shot.pellets if not shot.pellets.is_empty() else [shot.direction]):
		var t := _trace(targets, shot.origin, dir, w.max_range)
		if first.is_empty():
			first = t
		if t[0] != null:
			var hit: Hitbox.Hit = t[1]
			var entry: Array = dealt.get(t[0], [0.0, false])
			entry[0] += w.damage_at(hit.distance)
			entry[1] = entry[1] or hit.part == Hitbox.Part.HEAD
			dealt[t[0]] = entry
	_emit(action_id, "fire", {
		"shooter": p.net_id, "weapon": w.id, "origin": shot.origin, "direction": shot.direction,
		"end": first[2], "hit_player": first[0] != null,
		"hit_world": first[0] == null and first[3], "normal": first[4],
	})
	var hit_players := dealt.keys()
	hit_players.sort_custom(func(a: SimPlayer, b: SimPlayer) -> bool: return a.net_id < b.net_id)
	for target: SimPlayer in hit_players:
		_damage(target, p.net_id, dealt[target][0], dealt[target][1], w, shot.action_seq)


## The players `p`'s shot can hit, worked out once for all its pellets.
func _targets(p: SimPlayer) -> Targets:
	var t := Targets.new()
	t.shooter = p
	t.rewind = _rewind_tick(p)
	for other: SimPlayer in players.values():
		if other != p and other.state.alive and _can_hurt(p.net_id, other):
			t.list.append(other)
	if native_rewind != null:
		for other in t.list:
			if t.rewind < 0.0:
				t.feet.append(other.state.position)
				t.stances.append(other.state.stance)
			else:
				t.ids.append(other.net_id)
				t.life_gens.append(other.state.life_gen)
	return t


## One ray against the world and the (rewound) `targets`:
## [target or null, Hitbox.Hit, end point, hit the world, world normal].
func _trace(targets: Targets, origin: Vector3, dir: Vector3, max_range: float) -> Array:
	var world_hit := _ray(origin, origin + dir * max_range)
	var max_dist := max_range
	var normal := Vector3.ZERO
	if not world_hit.is_empty():
		max_dist = origin.distance_to(world_hit.position)
		normal = world_hit.normal
	var target: SimPlayer = null
	var best: Hitbox.Hit = null
	if native_rewind != null:
		# [index into targets.list, distance, part] or [].
		var r: PackedFloat64Array
		if targets.rewind < 0.0:
			r = native_rewind.trace_poses(targets.feet, targets.stances, origin, dir, max_dist)
		else:
			r = native_rewind.trace(targets.ids, targets.life_gens, targets.rewind, origin, dir, max_dist)
		if not r.is_empty():
			target = targets.list[int(r[0])]
			best = Hitbox.Hit.new()
			best.distance = r[1]
			best.part = int(r[2])
	else:
		for other in targets.list:
			var pose := _pose(targets.shooter, other)
			if pose.is_empty():
				continue
			var hit := Hitbox.intersect(pose[0], pose[1], origin, dir, max_dist)
			if hit != null and (best == null or hit.distance < best.distance):
				best = hit
				target = other
	var dist := best.distance if best != null else max_dist
	return [target, best, origin + dir * dist, not world_hit.is_empty(), normal]


## Where `other` was as `shooter` saw it: [feet, stance], rewound for lag
## compensation; [] if it wasn't there (or was a previous life) then.
func _pose(shooter: SimPlayer, other: SimPlayer) -> Array:
	var rewind := _rewind_tick(shooter)
	if rewind < 0.0:
		return [other.state.position, other.state.stance]
	if native_rewind != null:
		var n: Array = native_rewind.sample(other.net_id, rewind)
		return [] if n.is_empty() or n[2] != other.state.life_gen else [n[0], n[1]]
	var pose := (history[other.net_id] as HitboxHistory).sample(rewind) if history.has(other.net_id) else null
	if pose == null or pose.life_gen != other.state.life_gen:
		return []
	return [pose.position, pose.stance]


## Melee (PLAN §2.3): the nearest visible enemy within reach in front of the
## eye; 70 damage, or the weapon's direct damage (200) from behind.
func _resolve_melee(p: SimPlayer, shot: WeaponSim.Shot, action_id: String) -> void:
	var w := shot.weapon
	var target: SimPlayer = null
	var best_d := INF
	for other: SimPlayer in players.values():
		if other == p or not other.state.alive or not _can_hurt(p.net_id, other):
			continue
		var pose := _pose(p, other)
		if pose.is_empty():
			continue
		var c := Hitbox.center(pose[0], pose[1])
		var to := c - shot.origin
		var d := to.length()
		if d > w.max_range + 0.4 or to.normalized().dot(shot.direction) < cos(deg_to_rad(Balance.PLAYER.melee_cone_degrees)):
			continue
		if not _ray(shot.origin, c).is_empty():
			continue
		if d < best_d:
			best_d = d
			target = other
	# A "fire" event without an end point; presentation plays a swing.
	_emit(action_id, "fire", {"shooter": p.net_id, "weapon": w.id, "origin": shot.origin, "direction": shot.direction})
	if target == null:
		return
	var facing := WeaponSim.aim_direction(target.state.yaw, 0.0)
	var from_behind := facing.dot((target.state.position - p.state.position).normalized()) > cos(deg_to_rad(Balance.PLAYER.backstab_degrees))
	_damage(target, p.net_id, w.direct_damage if from_behind else w.damage, false, w, shot.action_seq)


## Friendly fire (PLAN §2.3): teammates can't hurt each other unless the host
## turned it on. Players always hurt themselves (explosives).
func _can_hurt(attacker_id: int, target: SimPlayer) -> bool:
	if friendly_fire or attacker_id == target.net_id or not teams_enabled:
		return true
	var a: SimPlayer = players.get(attacker_id)
	return a == null or a.team != target.team


## The (already validated) view tick to rewind targets to, or -1 for "now".
## The current tick hasn't been recorded yet, so the newest pose is tick - 1.
func _rewind_tick(p: SimPlayer) -> float:
	if not lag_compensation or p.last_command == null or p.last_command.view_tick <= 0.0:
		return -1.0
	return clampf(p.last_command.view_tick, float(tick - HitboxHistory.MAX_REWIND_TICKS), float(tick - 1))


func _step_projectiles() -> void:
	var remaining: Array[Projectile] = []
	for proj in projectiles:
		proj.age += 1
		var w := proj.weapon
		if w.fuse_ticks > 0:
			if _step_thrown(proj):
				remaining.append(proj)
			continue
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
			if other.net_id == proj.owner_id or not other.state.alive or not _can_hurt(proj.owner_id, other):
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


## Grenades: gravity, bounces off the world, explode when the fuse runs out.
## Returns false once exploded.
func _step_thrown(proj: Projectile) -> bool:
	var w := proj.weapon
	if proj.age >= w.fuse_ticks:
		_explode(proj, proj.position, null)
		return false
	proj.velocity.y -= w.gravity * Sim.TICK_DT
	var to := proj.position + proj.velocity * Sim.TICK_DT
	var hit := _ray(proj.position, to)
	if hit.is_empty():
		proj.position = to
		return true
	var n: Vector3 = hit.normal
	proj.position = hit.position + n * 0.05
	proj.velocity = proj.velocity.bounce(n) * w.bounce
	if n.y > 0.7 and proj.velocity.length() < 1.0:
		proj.velocity = Vector3.ZERO  # at rest on the floor
	return true


func _explode(proj: Projectile, at: Vector3, direct: SimPlayer) -> void:
	var w := proj.weapon
	_emit("x:" + proj.id(), "explosion", {"position": at, "owner": proj.owner_id, "weapon": w.id})
	if direct != null:
		_damage(direct, proj.owner_id, w.direct_damage, false, w, proj.action_seq)
	var ids := players.keys()
	ids.sort()
	for id in ids:
		var p: SimPlayer = players[id]
		if p == direct or not p.state.alive or not _can_hurt(proj.owner_id, p):
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
	if not damage_enabled:
		return
	var s := target.state
	var r := Health.apply(s, amount, headshot, w.headshot_multiplier, w.precision)
	if r.blocked or (r.shield_damage <= 0.0 and r.health_damage <= 0.0 and not r.killed):
		return
	_emit("h:%d:%d:%d:%d" % [attacker_id, action_seq, target.net_id, tick], "hit", {
		"attacker": attacker_id, "target": target.net_id, "amount": r.shield_damage + r.health_damage,
		"headshot": headshot, "shield_broken": r.shield_broken, "killed": r.killed,
	})
	if attacker_id != target.net_id:
		var dmg_log: Array = _damage_log.get(target.net_id, [])
		dmg_log.append([attacker_id, r.shield_damage + r.health_damage, tick])
		_damage_log[target.net_id] = dmg_log
	if r.killed:
		_kill(target, attacker_id, w, headshot)


## `attacker_id` 0 = the environment (falls, hazards); `w` is null then.
func _kill(victim: SimPlayer, attacker_id: int, w: WeaponData, headshot: bool) -> void:
	var s := victim.state
	_drop_power_weapon(victim)
	_drop_flag(victim)
	s.alive = false
	s.move_state = PlayerSimState.Move.DEAD
	s.velocity = Vector3.ZERO
	s.respawn_tick = tick + respawn_ticks
	_recent_deaths.append([s.position, tick])
	# Death attribution (PLAN §2.4): 1. an enemy's weapon → that enemy;
	# 2. your own explosive → suicide; 3. environment → the last enemy who
	# damaged you within 5 s; 4. otherwise suicide.
	var dmg_log: Array = _damage_log.get(victim.net_id, []).filter(
			func(e: Array) -> bool: return tick - e[2] <= maxi(Balance.PLAYER.assist_ticks, ENVIRONMENT_CREDIT_TICKS))
	_damage_log.erase(victim.net_id)
	var killer := attacker_id
	if killer == 0:
		for i in range(dmg_log.size() - 1, -1, -1):
			if tick - dmg_log[i][2] <= ENVIRONMENT_CREDIT_TICKS and players.has(dmg_log[i][0]):
				killer = dmg_log[i][0]
				break
	var suicide := killer == 0 or killer == victim.net_id
	var killer_p: SimPlayer = players.get(killer)
	var team_kill := teams_enabled and not suicide and killer_p != null and killer_p.team == victim.team
	if suicide:
		scores[victim.net_id] -= 1  # personal only; the team score is unchanged
	elif team_kill:
		scores[killer] -= 1
		if kills_score_for_team:
			team_scores[killer_p.team] -= 1
	elif scores.has(killer):
		scores[killer] += 1
		if teams_enabled and kills_score_for_team and killer_p != null:
			team_scores[killer_p.team] += 1
	var assists: Array[int] = []
	var dealt := {}
	for e in dmg_log:
		if tick - e[2] <= Balance.PLAYER.assist_ticks and e[0] != killer:
			dealt[e[0]] = dealt.get(e[0], 0.0) + e[1]
	for id in dealt:
		if dealt[id] >= Balance.PLAYER.assist_damage and assists.size() < Balance.PLAYER.max_assists:
			assists.append(id)
	assists.sort()
	_emit("d:%d:%d" % [victim.net_id, s.life_gen], "death", {
		"victim": victim.net_id, "killer": killer if not suicide else victim.net_id,
		"weapon": w.id if w != null else &"", "suicide": suicide, "headshot": headshot,
		"environment": attacker_id == 0, "assists": assists, "position": s.position, "team_kill": team_kill,
	})


# --- Pickups ---

const PICKUP_HEIGHT := 1.8


func _reset_pickups() -> void:
	items.clear()
	_held_spot.clear()
	spot_respawn.resize(pickup_spots.size())
	spot_respawn.fill(0)
	for i in pickup_spots.size():
		_spawn_item(i)


func _spawn_item(spot: int) -> void:
	var def: Dictionary = pickup_spots[spot]
	var w := Weapons.by_id(def.weapon) if def.weapon != &"grenade" else null
	_add_item(spot, Weapons.index_of(def.weapon) if w != null else -1, def.position,
			w.mag_size if w != null else 0, w.reserve if w != null else 0, 0)
	spot_respawn[spot] = 0


func _add_item(spot: int, weapon: int, position: Vector3, mag: int, reserve: int, despawn: int) -> Item:
	var it := Item.new()
	it.id = _next_item_id
	_next_item_id = (_next_item_id % 65535) + 1
	it.spot = spot
	it.weapon = weapon
	it.position = position
	it.mag = mag
	it.reserve = reserve
	it.despawn_tick = despawn
	items.append(it)
	return it


## The item's instance is gone: its spot's timer starts.
func _instance_gone(spot: int) -> void:
	if spot >= 0:
		spot_respawn[spot] = tick + int(pickup_spots[spot].respawn_ticks)


func _step_pickups(ids: Array, interacting: Dictionary) -> void:
	for i in pickup_spots.size():
		if spot_respawn[i] > 0 and tick >= spot_respawn[i]:
			_spawn_item(i)
	var kept: Array[Item] = []
	for it in items:
		if it.despawn_tick > 0 and tick >= it.despawn_tick:
			_instance_gone(it.spot)
		else:
			kept.append(it)
	items = kept
	# Contention: each item goes to the closest player who can take it (ties:
	# lowest id), in item order.
	for it: Item in items.duplicate():
		var best: SimPlayer = null
		var best_d := INF
		for id in ids:
			var p: SimPlayer = players[id]
			if not p.state.alive:
				continue
			var d := p.state.position - it.position
			var flat := Vector2(d.x, d.z).length()
			if flat > Balance.PLAYER.pickup_radius or absf(d.y) > PICKUP_HEIGHT:
				continue
			if _wants(p, it, interacting.has(id)) and flat < best_d:
				best_d = flat
				best = p
		if best != null:
			_take(best, it)


## Whether `p` takes `it` now: grenades below the cap; ammo for a weapon it
## carries; a power weapon if it holds none; anything else on interact.
func _wants(p: SimPlayer, it: Item, interact: bool) -> bool:
	var s := p.state
	if it.weapon < 0:
		return s.grenades < Balance.PLAYER.grenades_per_life
	var slot := s.weapons.find(it.weapon)
	if slot >= 0:
		var w := Weapons.at(it.weapon)
		return not w.infinite_reserve and s.reserve[slot] < w.reserve
	return interact or not needs_interact(s, it.weapon)


## Picking up `weapon` would swap out the primary by choice (interact):
## anything but a power weapon while holding none, or ammo for a carried one.
static func needs_interact(s: PlayerSimState, weapon: int) -> bool:
	if weapon < 0 or s.weapons.find(weapon) >= 0:
		return false
	return not (Weapons.at(weapon).is_power_weapon and not s.weapon(0).is_power_weapon)


func _take(p: SimPlayer, it: Item) -> void:
	var s := p.state
	items.erase(it)
	_emit("p:%d:%d" % [it.id, tick], "pickup", {"player": p.net_id, "weapon": Weapons.at(it.weapon).id if it.weapon >= 0 else &"grenade",
			"position": it.position})
	if it.weapon < 0:
		s.grenades += 1
		_instance_gone(it.spot)
		return
	var w := Weapons.at(it.weapon)
	var slot := s.weapons.find(it.weapon)
	if slot >= 0:
		s.reserve[slot] = mini(s.reserve[slot] + it.mag + it.reserve, w.reserve)
		_instance_gone(it.spot)
		return
	# Swap the primary: the old one drops (and despawns in 20 s).
	_drop_slot(p, 0)
	s.set_slot(0, it.weapon, it.mag, it.reserve)
	s.weapon_slot = 0
	s.switch_ticks = w.raise_ticks
	if w.is_power_weapon:
		s.spawn_protection_ticks = 0
		_held_spot[p.net_id] = it.spot


## Puts `p`'s slot `slot` weapon on the floor at its feet with its ammo.
func _drop_slot(p: SimPlayer, slot: int) -> void:
	var s := p.state
	var spot: int = _held_spot.get(p.net_id, -1) if slot == 0 else -1
	if slot == 0:
		_held_spot.erase(p.net_id)
	var floor_hit := _ray(s.position + Vector3.UP * 0.5, s.position + Vector3.DOWN * 20.0)
	var at: Vector3 = floor_hit.position if not floor_hit.is_empty() else s.position
	_add_item(spot, s.weapons[slot], at, s.mag[slot], s.reserve[slot], tick + Balance.PLAYER.drop_despawn_ticks)


## Death or leaving: a held power weapon drops with its remaining ammo.
func _drop_power_weapon(p: SimPlayer) -> void:
	var held := p.state.weapon(0)
	if held != null and held.is_power_weapon:
		_drop_slot(p, 0)


# --- Capture the flag (PLAN §2.4) ---

const FLAG_RADIUS := 1.2  ## touching a flag: as close as a pickup


## Puts team 0's flag at `bases[0]` and team 1's at `bases[1]`; [] for none.
func configure_flags(bases: Array) -> void:
	flags.clear()
	for i in mini(bases.size(), 2):
		var f := Flag.new()
		f.team = i
		f.base = bases[i]
		_flag_home(f)
		flags.append(f)


func _flag_home(f: Flag) -> void:
	f.position = f.base
	f.carrier = 0
	f.return_tick = 0


## The flag `p` carries, or null.
func flag_of(p_id: int) -> Flag:
	for f in flags:
		if f.carrier == p_id:
			return f
	return null


## Touch rules, in flag order: the enemy takes a flag at its base or on the
## ground; its own team returns it from the ground; a carrier at its own base
## captures while its own flag is home.
func _step_flags(ids: Array) -> void:
	for f in flags:
		if f.carrier != 0:
			var c: SimPlayer = players.get(f.carrier)
			if c == null:
				_flag_home(f)
				continue
			if not c.state.alive:
				_drop_flag(c)
				continue
			f.position = c.state.position
			var home := flags[c.team] if c.team < flags.size() else null
			if home != null and home.at_base() and _touching(c, home.base):
				team_scores[c.team] += 1
				scores[c.net_id] += Balance.MODES.capture_points
				_flag_home(f)
				_emit("fc:%d:%d" % [f.team, tick], "flag", {"action": "capture", "team": f.team, "player": c.net_id,
						"position": c.state.position})
			continue
		if f.return_tick > 0 and tick >= f.return_tick:
			_flag_home(f)
			_emit("fr:%d:%d" % [f.team, tick], "flag", {"action": "return", "team": f.team, "player": 0, "position": f.base})
			continue
		for id in ids:
			var p: SimPlayer = players[id]
			if not p.state.alive or not _touching(p, f.position):
				continue
			if p.team == f.team:
				if not f.at_base():
					_flag_home(f)
					scores[id] += Balance.MODES.return_points
					_emit("fr:%d:%d" % [f.team, tick], "flag", {"action": "return", "team": f.team, "player": id,
							"position": f.base})
					break
			elif flag_of(id) == null:
				f.carrier = id
				f.return_tick = 0
				p.state.spawn_protection_ticks = 0
				_emit("ft:%d:%d" % [f.team, tick], "flag", {"action": "take", "team": f.team, "player": id,
						"position": f.position})
				break


func _touching(p: SimPlayer, at: Vector3) -> bool:
	var d := p.state.position - at
	return Vector2(d.x, d.z).length() <= FLAG_RADIUS and absf(d.y) <= PICKUP_HEIGHT


## Death or leaving: a carried flag falls where the carrier was.
func _drop_flag(p: SimPlayer) -> void:
	var f := flag_of(p.net_id)
	if f == null:
		return
	var floor_hit := _ray(p.state.position + Vector3.UP * 0.5, p.state.position + Vector3.DOWN * 20.0)
	f.carrier = 0
	f.position = floor_hit.position if not floor_hit.is_empty() else f.base
	f.return_tick = tick + Balance.MODES.flag_return_ticks
	_emit("fd:%d:%d" % [f.team, tick], "flag", {"action": "drop", "team": f.team, "player": p.net_id, "position": f.position})


## Ticks until spot `i`'s next instance (0 while one exists).
func spot_ticks_left(i: int) -> int:
	return maxi(spot_respawn[i] - tick, 0) if spot_respawn[i] > 0 else 0


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
	s.spawn_protection_ticks = Balance.PLAYER.spawn_protection_ticks
	s.life_gen += 1
	s.discontinuity_gen += 1
	s.pending_presses = PackedByteArray([0, 0, 0, 0, 0, 0, 0])
	Health.reset(s)
	_damage_log.erase(p.net_id)
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
	var me: SimPlayer = players.get(for_id)
	for i in spawn_points.size():
		var pos := spawn_points[i].origin
		var nearest := 50.0
		var visible := 0
		var close_visible := 0  ## enemies in sight within 20 m: an almost certain spawn kill
		var occupied := false
		for other: SimPlayer in players.values():
			if other.net_id == for_id or not other.state.alive:
				continue
			var d := pos.distance_to(other.state.position)
			occupied = occupied or d < 2.0
			if teams_enabled and me != null and other.team == me.team:
				continue  # teammates: see _team_spawn_bonus
			nearest = minf(nearest, d)
			if _ray(pos + Vector3(0.0, 1.6, 0.0), other.eye_position()).is_empty():
				visible += 1
				close_visible += 1 if d < 20.0 else 0
		var recent := 0
		for d in _recent_deaths:
			if pos.distance_to(d[0]) < 8.0:
				recent += 1
		# Grenades and rockets in flight near the spot.
		var danger := 0
		for proj in projectiles:
			if proj.owner_id != for_id and pos.distance_to(proj.position) < 8.0:
				danger += 1
		var score := nearest - visible * 15.0 - close_visible * 20.0 - recent * 10.0 - danger * 25.0 \
				- (100.0 if occupied else 0.0)
		if teams_enabled and me != null:
			score += _team_spawn_bonus(me, pos)
		scored.append([score, i])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	# Random among the best few, but only those nearly as good as the best:
	# a much worse third choice (in an enemy's sight) caused spawn kills.
	var pool := 1
	while pool < mini(3, scored.size()) and scored[pool][0] >= scored[0][0] - SPAWN_SCORE_MARGIN:
		pool += 1
	var pick: int = scored[_rng.randi_range(0, pool - 1)][1]
	return spawn_points[pick]


## TDM spawn scoring (PLAN §2.5): near teammates, away from the enemy half.
func _team_spawn_bonus(p: SimPlayer, pos: Vector3) -> float:
	var bonus := 0.0
	for other: SimPlayer in players.values():
		if other != p and other.team == p.team and other.state.alive and pos.distance_to(other.state.position) < 15.0:
			bonus += 4.0
	if signf(pos.x) == -GameMode.team_side(p.team) and absf(pos.x) > 4.0:
		bonus -= 30.0
	return bonus


func _emit(id: String, type: String, data: Dictionary) -> void:
	data["id"] = id
	data["type"] = type
	data["tick"] = tick
	_events.append(data)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, Sim.LAYER_WORLD))
