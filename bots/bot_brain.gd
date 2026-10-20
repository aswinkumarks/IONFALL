class_name BotBrain
extends RefCounted
## Server-side bot (PLAN §2.7): produces the same PlayerCommand stream a
## human does, so bots use the same movement, weapons, validation and
## replication. Utility goals (attack / chase / retreat to regenerate /
## grab a power weapon or grenades / roam), path following with traversal links, human-like aim (reaction
## delay, turn-rate limit, tracking error; no wallhacks, no perfect aim) and
## stuck recovery. Perception runs at 10 Hz, re-pathing at most 2 Hz,
## staggered across bots.

enum Goal { ROAM, ATTACK, CHASE, RETREAT, PICKUP }

const Held := PlayerCommand.Held
const Action := PlayerCommand.Action
const T := BotNavigation.Traversal

## Normal difficulty.
const REACTION_TICKS := 15
const MAX_TURN := 0.1  ## rad per tick (~340°/s)
const AIM_ERROR := 0.035  ## rad of tracking error (~2°)
const AIM_SPEED_ERROR := 0.006  ## extra rad per m/s of target lateral speed
const VIEW_RANGE := 60.0
const VIEW_COS := 0.45  ## ~127° field of view
const CLOSE_AWARENESS := 6.0  ## seen at any angle this close
const PERCEPTION_INTERVAL := 6
const REPATH_INTERVAL := 30
const CHASE_MEMORY_TICKS := 300
const STUCK_CHECK_TICKS := 90
## Splash weapons are kept for this range band (too close hurts the bot).
const SPLASH_RANGE := Vector2(6.0, 30.0)
const GRENADE_RANGE := Vector2(7.0, 18.0)
const GRENADE_CHANCE := 0.2  ## per new sighting in range
const MELEE_RANGE := 1.8
## Out of combat, bots fetch power weapons and grenades this close.
const POWER_FETCH_RANGE := 35.0
const GRENADE_FETCH_RANGE := 15.0
const SLOT_PRIMARY := 0
const SLOT_SIDEARM := 1

var goal: int = Goal.ROAM
var target_id: int = 0
var stuck_teleports: int = 0

var _world: SimWorld
var _nav: BotNavigation
var _id: int = 0
var _rng := RandomNumberGenerator.new()
var _presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
var _yaw: float = 0.0
var _pitch: float = 0.0
var _disc: int = -1
var _visible: bool = false
var _seen_since: int = 0
var _last_seen_pos := Vector3.ZERO
var _last_seen_tick: int = -100000
var _retreat_until: int = 0
var _path: Array = []
var _path_i: int = 0
var _path_goal := Vector3.INF
var _last_repath: int = -100000
var _strafe: float = 1.0
var _strafe_until: int = 0
var _slot: int = SLOT_PRIMARY
var _throw_at: int = 0  ## tick to throw a grenade at the current target
var _noise_phase := Vector4.ZERO
var _progress_pos := Vector3.ZERO
var _progress_tick: int = 0
var _stuck_stage: int = 0
var _sidestep_until: int = 0
var _traversal: int = T.NONE
var _traversal_jumps: int = 0
var _destination := Vector3.INF  ## explicit roam target (objectives, pickups)


## Roam towards `pos` instead of random points (until reached).
func go_to(pos: Vector3) -> void:
	_destination = pos
	_path = []
	_last_repath = -100000


func _init(world: SimWorld, nav: BotNavigation, id: int, seed_value: int) -> void:
	_world = world
	_nav = nav
	_id = id
	_rng.seed = seed_value
	_noise_phase = Vector4(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)


## Damage tells a bot where its attacker is, even out of sight.
func on_event(e: Dictionary) -> void:
	if e.type == "hit" and e.target == _id and e.attacker != _id:
		var attacker: SimPlayer = _world.players.get(e.attacker)
		if attacker != null and not _visible:
			_last_seen_pos = attacker.state.position
			_last_seen_tick = _world.tick
			target_id = e.attacker


func command_for(tick: int, p: SimPlayer) -> PlayerCommand:
	var s := p.state
	if s.discontinuity_gen != _disc:  # spawned or teleported
		_disc = s.discontinuity_gen
		_yaw = s.yaw
		_pitch = 0.0
		_path = []
		_slot = SLOT_PRIMARY
		goal = Goal.ROAM
		target_id = 0
		_visible = false
		_progress_pos = s.position
		_progress_tick = tick
	var c := PlayerCommand.new()
	c.tick = tick
	if not s.alive or _nav == null or not _nav.ready_for_queries:
		c.set_look(_yaw, _pitch)
		c.presses = _presses.duplicate()
		return c
	if (tick + _id) % PERCEPTION_INTERVAL == 0:
		_perceive(tick, p)
		_choose_goal(tick, p)
	var held := 0
	var move := Vector3.ZERO
	var look_at := Vector3.INF
	var target: SimPlayer = _world.players.get(target_id)
	match goal:
		Goal.ATTACK:
			move = _attack_move(tick, p, target)
			look_at = _aim_point(target, p)
		Goal.CHASE:
			move = _follow(tick, p, _last_seen_pos)
			held |= Held.SPRINT if move.length() > 0.5 else 0
		Goal.RETREAT, Goal.PICKUP:
			move = _follow(tick, p, _path_goal)
			held |= Held.SPRINT if move.length() > 0.5 else 0
		_:
			if _destination != Vector3.INF:
				move = _follow(tick, p, _destination)
				if move == Vector3.ZERO and not _path.is_empty() and _path_i >= _path.size():
					_destination = Vector3.INF  # arrived
			else:
				if _path_goal == Vector3.INF or _path.is_empty() or _path_i >= _path.size():
					_path_goal = _nav.random_point()
					_last_repath = -100000
				move = _follow(tick, p, _path_goal)
			held |= Held.SPRINT if move.length() > 0.5 else 0
	move = _stuck_recovery(tick, p, move)
	held |= _traversal_inputs(p, move)
	# Look: at the target while fighting, along the way otherwise.
	var want_yaw := _yaw
	var want_pitch := 0.0
	if look_at != Vector3.INF:
		var to := look_at - p.eye_position()
		want_yaw = atan2(-to.x, -to.z)
		want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	elif move.length_squared() > 0.01:
		want_yaw = atan2(-move.x, -move.z)
	_yaw += clampf(wrapf(want_yaw - _yaw, -PI, PI), -MAX_TURN, MAX_TURN)
	_yaw = wrapf(_yaw, -PI, PI)
	_pitch += clampf(want_pitch - _pitch, -MAX_TURN, MAX_TURN)
	if goal == Goal.ATTACK and target != null:
		held = (held & ~Held.SPRINT) | _trigger(tick, p, target, want_yaw, want_pitch)
	else:
		_manage_weapons_out_of_combat(p)
	c.set_look(_yaw, _pitch)
	c.set_move(_local(move))
	c.held = held
	c.weapon_slot = _slot if _slot != s.weapon_slot else -1
	c.presses = _presses.duplicate()
	return c


# --- Perception & goals ---

func _perceive(tick: int, p: SimPlayer) -> void:
	var eye := p.eye_position()
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var best := 0
	var best_d := INF
	for id in _world.players:
		if id == _id:
			continue
		var o: SimPlayer = _world.players[id]
		if not o.state.alive or (_world.teams_enabled and o.team == p.team):
			continue
		var chest := o.state.position + Vector3(0.0, 1.2, 0.0)
		var to := chest - eye
		var d := to.length()
		if d > VIEW_RANGE:
			continue
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		if d > CLOSE_AWARENESS and flat.dot(forward) < VIEW_COS and id != target_id:
			continue
		var space := p.get_world_3d().direct_space_state
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, chest, Sim.LAYER_WORLD)).is_empty():
			continue
		if d < best_d:
			best_d = d
			best = id
	var was_visible := _visible
	_visible = best != 0
	if _visible:
		if not was_visible or best != target_id:
			_seen_since = tick
			_strafe_until = 0
			# Splash primaries only at a safe range; the sidearm up close.
			var primary := p.state.weapon(SLOT_PRIMARY)
			_slot = SLOT_PRIMARY
			if primary.is_projectile() and (best_d < SPLASH_RANGE.x or best_d > SPLASH_RANGE.y):
				_slot = SLOT_SIDEARM
			if p.state.grenades > 0 and best_d >= GRENADE_RANGE.x and best_d <= GRENADE_RANGE.y \
					and _rng.randf() < GRENADE_CHANCE:
				_throw_at = tick + REACTION_TICKS + 10
		target_id = best
		_last_seen_pos = _world.players[best].state.position
		_last_seen_tick = tick


func _choose_goal(tick: int, p: SimPlayer) -> void:
	var s := p.state
	if goal == Goal.RETREAT and tick < _retreat_until and s.shield < 60.0:
		return
	var target: SimPlayer = _world.players.get(target_id)
	if _visible and target != null:
		var losing := s.shield <= 0.0 and s.health < 45.0 and target.state.shield + target.state.health > s.health + 20.0
		if losing and goal != Goal.RETREAT:
			goal = Goal.RETREAT
			_retreat_until = tick + 360
			_path_goal = _retreat_point(p, target)
			_path = []
			_last_repath = -100000
			return
		goal = Goal.ATTACK
	elif tick - _last_seen_tick < CHASE_MEMORY_TICKS and target_id != 0:
		goal = Goal.CHASE
	else:
		target_id = 0
		var item := _wanted_item(p)
		if item != Vector3.INF:
			if goal != Goal.PICKUP or _path_goal.distance_to(item) > 0.5:
				_path_goal = item
				_path = []  # repath now: _follow keeps a path whose goal hasn't moved
				_last_repath = -100000
			goal = Goal.PICKUP
			return
		if goal != Goal.ROAM:
			_path_goal = Vector3.INF
		goal = Goal.ROAM


## The nearest power weapon (holding none) or grenade pickup (short of
## grenades) in fetching range, or INF.
func _wanted_item(p: SimPlayer) -> Vector3:
	var s := p.state
	var best := Vector3.INF
	var best_d := INF
	for it: SimWorld.Item in _world.items:
		var d := it.position.distance_to(s.position)
		var want := false
		if it.weapon < 0:
			want = s.grenades < PlayerSimState.GRENADES_PER_LIFE and d < GRENADE_FETCH_RANGE
		else:
			want = Weapons.at(it.weapon).is_power_weapon and not s.weapon(0).is_power_weapon and d < POWER_FETCH_RANGE
		if want and d < best_d:
			best_d = d
			best = it.position
	return best


func _retreat_point(p: SimPlayer, threat: SimPlayer) -> Vector3:
	var best := p.state.position
	var best_d := -1.0
	for i in 6:
		var candidate := _nav.random_point()
		var d := candidate.distance_to(threat.state.position) - candidate.distance_to(p.state.position) * 0.5
		if d > best_d:
			best_d = d
			best = candidate
	return best


# --- Movement ---

func _attack_move(tick: int, p: SimPlayer, target: SimPlayer) -> Vector3:
	if target == null:
		return Vector3.ZERO
	var to := target.state.position - p.state.position
	to.y = 0.0
	var d := to.length()
	if d > 25.0:
		return _follow(tick, p, target.state.position)
	if tick >= _strafe_until:
		_strafe = -_strafe if _rng.randf() < 0.7 else _strafe
		_strafe_until = tick + _rng.randi_range(30, 80)
	var dir := to / maxf(d, 0.01)
	var side := Vector3(-dir.z, 0.0, dir.x) * _strafe
	var approach := 0.0
	if d > 18.0:
		approach = 0.7
	elif d < 7.0:
		approach = -0.6
	if _rng.randf() < 0.008:
		_press(Action.JUMP)
	return (side + dir * approach).limit_length(1.0)


## Steers along a navmesh path to `goal_pos`; returns a world-space
## direction (length ≤ 1). Re-paths at most every REPATH_INTERVAL ticks.
func _follow(tick: int, p: SimPlayer, goal_pos: Vector3) -> Vector3:
	var pos := p.state.position
	var moved_goal := _path_goal == Vector3.INF or _path_goal.distance_to(goal_pos) > 2.0
	if (moved_goal or _path.is_empty()) and tick - _last_repath >= REPATH_INTERVAL:
		_path_goal = goal_pos
		_path = _nav.path(pos, goal_pos)
		_path_i = 1 if _path.size() > 1 else 0
		_last_repath = tick
	if _path.is_empty() or _path_i >= _path.size():
		return Vector3.ZERO
	var next: Vector3 = _path[_path_i][0]
	var flat := Vector3(next.x - pos.x, 0.0, next.z - pos.z)
	# The navmesh floats ~0.5 m above the floor: compare heights loosely.
	if flat.length() < 0.6 and absf(next.y - 0.5 - pos.y) < 1.2:
		_path_i += 1
		_traversal = T.NONE
		_traversal_jumps = 0
		if _path_i >= _path.size():
			return Vector3.ZERO
		next = _path[_path_i][0]
		flat = Vector3(next.x - pos.x, 0.0, next.z - pos.z)
	# Entering a link segment: the previous point's traversal applies.
	var link: int = _path[_path_i - 1][1] if _path_i > 0 else T.NONE
	if link != _traversal:
		_traversal = link
		_traversal_jumps = 0
	return flat.normalized()


## Jumps for traversal links: jump + hold for mantles, a second jump near the
## apex for tall ledges. Mantling itself is the normal movement code.
func _traversal_inputs(p: SimPlayer, move: Vector3) -> int:
	if _traversal == T.NONE or _traversal == T.DROP or move.length_squared() < 0.01:
		return 0
	var s := p.state
	var on_floor := s.move_state != PlayerSimState.Move.AIR and s.move_state != PlayerSimState.Move.MANTLE
	if on_floor and _traversal_jumps == 0:
		_press(Action.JUMP)
		_traversal_jumps = 1
	elif _traversal == T.DOUBLE_JUMP_MANTLE and _traversal_jumps == 1 and not on_floor and s.velocity.y < 1.5:
		_press(Action.JUMP)
		_traversal_jumps = 2
	return Held.JUMP


## No progress for 90 ticks → jump, then sidestep, then re-path, then
## teleport to the nearest navmesh point (last resort, logged).
func _stuck_recovery(tick: int, p: SimPlayer, move: Vector3) -> Vector3:
	if tick < _sidestep_until:
		return Vector3(-move.z, 0.0, move.x) if move.length_squared() > 0.01 else Vector3.RIGHT
	if move.length_squared() < 0.01 or goal == Goal.ATTACK:
		_progress_pos = p.state.position
		_progress_tick = tick
		_stuck_stage = 0
		return move
	if tick - _progress_tick < STUCK_CHECK_TICKS:
		return move
	if p.state.position.distance_to(_progress_pos) > 1.0:
		_stuck_stage = 0
	else:
		_stuck_stage += 1
		match _stuck_stage:
			1:
				_press(Action.JUMP)
			2:
				_sidestep_until = tick + 30
			3:
				_path = []
				_path_goal = _nav.random_point() if goal == Goal.ROAM else _path_goal
				_last_repath = -100000
			_:
				var spot := _nav.closest_point(p.state.position + Vector3(0.0, 1.0, 0.0))
				_world.teleport(p, spot + Vector3(0.0, 0.1, 0.0))
				stuck_teleports += 1
				print("BOT %d stuck at %s: teleported to %s" % [_id, p.state.position, spot])
				_stuck_stage = 0
				_path = []
	_progress_pos = p.state.position
	_progress_tick = tick
	return move


# --- Aim & weapons ---

## Chest, or the feet for splash weapons, plus smooth tracking error that
## grows with the target's sideways speed.
func _aim_point(target: SimPlayer, p: SimPlayer) -> Vector3:
	if target == null:
		return Vector3.INF
	var ts := target.state
	var splash := p.state.weapon(_slot) != null and p.state.weapon(_slot).is_projectile()
	var base := ts.position + Vector3(0.0, 0.3 if splash else 1.2, 0.0)
	var to := base - p.eye_position()
	var d := maxf(to.length(), 1.0)
	var lateral := (ts.velocity - ts.velocity.project(to.normalized())).length()
	var amplitude := AIM_ERROR + AIM_SPEED_ERROR * lateral
	var t := float(_world.tick) * 0.05
	var err_yaw := amplitude * (sin(t * 1.3 + _noise_phase.x) * 0.7 + sin(t * 3.1 + _noise_phase.y) * 0.3)
	var err_pitch := amplitude * 0.6 * (sin(t * 1.7 + _noise_phase.z) * 0.7 + sin(t * 2.9 + _noise_phase.w) * 0.3)
	var right := to.cross(Vector3.UP).normalized()
	return base + right * tan(err_yaw) * d + Vector3.UP * tan(err_pitch) * d


func _trigger(tick: int, p: SimPlayer, target: SimPlayer, want_yaw: float, want_pitch: float) -> int:
	var s := p.state
	if tick - _seen_since < REACTION_TICKS or not _visible:
		return 0
	var w := s.weapon_slot
	var d := p.state.position.distance_to(target.state.position)
	if d < MELEE_RANGE and s.melee_cooldown == 0:
		_press(Action.MELEE)
		return 0
	if _throw_at > 0 and tick >= _throw_at:
		_throw_at = 0
		if s.grenades > 0 and d >= GRENADE_RANGE.x:
			_press(Action.GRENADE)
			return 0
	if w != _slot or s.switch_ticks > 0:
		return 0
	# Out of ammo: sidearm is faster than reloading the primary.
	if s.mag[w] <= 0:
		if w == SLOT_PRIMARY and s.mag[SLOT_SIDEARM] > 0:
			_slot = SLOT_SIDEARM
		elif w == SLOT_SIDEARM and (s.mag[SLOT_PRIMARY] > 0 or s.reserve[SLOT_PRIMARY] > 0):
			_slot = SLOT_PRIMARY
		elif s.reload[w] == 0:
			_press(Action.RELOAD)
		return 0
	var aim_error := absf(wrapf(want_yaw - _yaw, -PI, PI)) + absf(want_pitch - _pitch)
	if aim_error > atan2(0.45, d) + 0.03:
		return 0
	var data := s.weapon(w)
	if data.fire_mode == WeaponData.FireMode.AUTO:
		return Held.FIRE
	if s.cooldown[w] == 0 and s.reload[w] == 0:
		_press(Action.FIRE)
	return 0


func _manage_weapons_out_of_combat(p: SimPlayer) -> void:
	var s := p.state
	_slot = SLOT_PRIMARY
	var w := s.weapon_slot
	if w == SLOT_PRIMARY and s.reload[w] == 0 and s.mag[w] * 2 < s.weapon(w).mag_size \
			and s.reserve[w] > 0:
		_press(Action.RELOAD)


# --- Helpers ---

func _press(action: int) -> void:
	_presses[action] = (_presses[action] + 1) & 0xFF


## World direction → move vector relative to the view (x right, y forward).
func _local(dir: Vector3) -> Vector2:
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	return Vector2(dir.dot(right), dir.dot(forward)).limit_length(1.0)
