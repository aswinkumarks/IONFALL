class_name PlayerMovement
extends RefCounted
## One tick of player movement (PLAN §2.1, §3.2). Pure function of the player
## state, the command and the static world, so replays are exact.

const Move := PlayerSimState.Move
const Stance := PlayerSimState.Stance
const Held := PlayerCommand.Held

static var _probe_shapes: Dictionary = {}


static func step(p: SimPlayer, cmd: PlayerCommand, executed: int) -> void:
	var s := p.state
	var cfg := p.config
	s.yaw = cmd.yaw_radians()
	s.pitch = cmd.pitch_radians()
	if not s.alive:
		return
	if s.move_state == Move.MANTLE:
		_step_mantle(p)
		return
	if s.is_on_floor():
		var pad_target := JumpPads.target_at(p.get_world_3d().direct_space_state, s.position)
		if pad_target != Vector3.INF:
			_launch(p, pad_target)

	var fwd := Vector3(-sin(s.yaw), 0.0, -cos(s.yaw))
	var right := Vector3(cos(s.yaw), 0.0, -sin(s.yaw))
	var mv := cmd.move_vector()
	var wish := right * mv.x + fwd * mv.y
	var wish_len := wish.length()
	var wish_dir := wish / wish_len if wish_len > 0.001 else Vector3.ZERO
	var crouch_held := cmd.is_held(Held.CROUCH)
	var scoped := WeaponSim.is_scoped(s, cmd)
	var jump_pressed := ActionInput.has(executed, PlayerCommand.Action.JUMP)

	if jump_pressed:
		s.jump_buffer_ticks = cfg.jump_buffer_ticks
	elif s.jump_buffer_ticks > 0:
		s.jump_buffer_ticks -= 1

	if s.is_on_floor():
		s.sprinting = cmd.is_held(Held.SPRINT) and mv.y > 0.5 and not crouch_held and not scoped
	elif mv.y <= 0.5:
		s.sprinting = false

	var hvel := Vector3(s.velocity.x, 0.0, s.velocity.z)
	if s.move_state == Move.GROUND and crouch_held and s.stance == Stance.STAND \
			and hvel.length() >= cfg.slide_min_speed:
		var speed := minf(hvel.length() + cfg.slide_boost, cfg.slide_max_speed)
		s.velocity = hvel.normalized() * speed
		s.move_state = Move.SLIDE
		s.stance = Stance.SLIDE
		s.slide_ticks = cfg.slide_ticks
		s.sprinting = false

	if s.move_state != Move.SLIDE:
		if crouch_held:
			s.stance = Stance.CROUCH
		elif s.stance != Stance.STAND and _fits(p, s.position, cfg.stand_height):
			s.stance = Stance.STAND
	p.apply_stance_shape(s.stance)

	var can_ground_jump := s.is_on_floor() \
			or (s.move_state == Move.AIR and s.ticks_since_floor <= cfg.coyote_ticks)
	if s.jump_buffer_ticks > 0 and can_ground_jump:
		s.velocity.y = cfg.jump_velocity
		s.jump_buffer_ticks = 0
		s.ticks_since_floor = cfg.coyote_ticks + 1
		if s.move_state == Move.SLIDE:
			_end_slide(p, crouch_held)
		s.move_state = Move.AIR
	elif s.move_state == Move.AIR:
		if mv.y > 0.5 and cmd.is_held(Held.JUMP):
			var target: Variant = _find_mantle_target(p, fwd)
			if target != null:
				_start_mantle(p, target)
				return
		if jump_pressed and s.air_jumps_left > 0:
			s.air_jumps_left -= 1
			s.jump_buffer_ticks = 0
			s.velocity.y = cfg.double_jump_velocity
			if wish_len > 0.001:
				var h := Vector3(s.velocity.x, 0.0, s.velocity.z)
				var redirected := wish_dir * maxf(h.length(), cfg.walk_speed * wish_len)
				h = h.lerp(redirected, cfg.double_jump_redirect)
				s.velocity.x = h.x
				s.velocity.z = h.z

	var dt := Sim.TICK_DT
	match s.move_state:
		Move.GROUND:
			s.velocity.y = 0.0
			_apply_friction(s, cfg.friction, cfg.stop_speed, dt)
			var max_speed := cfg.walk_speed
			if s.sprinting:
				max_speed = cfg.sprint_speed
			elif s.stance == Stance.CROUCH:
				max_speed = cfg.crouch_speed
			if scoped:
				max_speed = minf(max_speed, cfg.walk_speed * s.weapon().scope_move_speed)
			_accelerate(s, wish_dir, max_speed * wish_len, cfg.ground_accel, dt)
		Move.SLIDE:
			s.velocity.y = 0.0
			_apply_friction(s, cfg.slide_friction, 0.0, dt)
			var downhill := (Vector3.DOWN * cfg.gravity).slide(s.floor_normal)
			s.velocity += Vector3(downhill.x, 0.0, downhill.z) * dt
			s.slide_ticks -= 1
			var hspeed := Vector2(s.velocity.x, s.velocity.z).length()
			if s.slide_ticks <= 0 or hspeed < cfg.slide_end_speed or not crouch_held:
				_end_slide(p, crouch_held)
				s.move_state = Move.GROUND
		Move.AIR:
			s.velocity.y -= cfg.gravity * dt
			_accelerate(s, wish_dir, minf(cfg.walk_speed * wish_len, cfg.air_wish_speed_cap), cfg.air_accel, dt)

	_move_and_collide(p)


## Thrown by a jump pad towards `target`: airborne, past coyote time (no
## ground jump), with the double jump still available.
static func _launch(p: SimPlayer, target: Vector3) -> void:
	var s := p.state
	if s.move_state == Move.SLIDE:
		_end_slide(p, false)
	s.velocity = JumpPads.launch_velocity(s.position, target, p.config.gravity)
	s.move_state = Move.AIR
	s.ticks_since_floor = p.config.coyote_ticks + 1
	s.jump_buffer_ticks = 0
	s.sprinting = false
	s.air_jumps_left = 1


static func _end_slide(p: SimPlayer, crouch_held: bool) -> void:
	var s := p.state
	s.slide_ticks = 0
	if not crouch_held and _fits(p, s.position, p.config.stand_height):
		s.stance = Stance.STAND
	else:
		s.stance = Stance.CROUCH
	p.apply_stance_shape(s.stance)


static func _apply_friction(s: PlayerSimState, friction: float, stop_speed: float, dt: float) -> void:
	var h := Vector3(s.velocity.x, 0.0, s.velocity.z)
	var speed := h.length()
	if speed < 0.0001:
		s.velocity.x = 0.0
		s.velocity.z = 0.0
		return
	var drop := maxf(speed, stop_speed) * friction * dt
	var scale := maxf(speed - drop, 0.0) / speed
	s.velocity.x *= scale
	s.velocity.z *= scale


## Quake-style acceleration: only adds speed along `dir` up to `wish_speed`.
static func _accelerate(s: PlayerSimState, dir: Vector3, wish_speed: float, accel: float, dt: float) -> void:
	if wish_speed <= 0.0:
		return
	var add := wish_speed - s.velocity.dot(dir)
	if add <= 0.0:
		return
	s.velocity += dir * minf(accel * dt * wish_speed, add)


static func _move_and_collide(p: SimPlayer) -> void:
	var s := p.state
	var cfg := p.config
	var floor_cos := cos(deg_to_rad(cfg.max_floor_angle_deg))
	var was_on_floor := s.is_on_floor()
	var motion := s.velocity * Sim.TICK_DT
	# On the ground, move along the floor plane at full horizontal speed.
	# Walking into a slope otherwise hits it like a wall, and the slide off it
	# trimmed the horizontal speed every tick: ramps were far slower uphill.
	var grounded_move := was_on_floor and s.move_state != Move.AIR
	if grounded_move:
		motion = _along_floor(motion, s.floor_normal)
	for i in 4:
		if motion.length_squared() < 1e-10:
			break
		var col := p.move_and_collide(motion)
		if col == null:
			break
		var n := col.get_normal()
		if grounded_move and n.y >= floor_cos:
			motion = _along_floor(col.get_remainder(), n)  # onto (another) walkable slope
			continue
		motion = col.get_remainder().slide(n)
		if s.velocity.dot(n) < 0.0:
			s.velocity = s.velocity.slide(n)

	var grounded := false
	if s.velocity.y <= 0.01:
		var probe := cfg.snap_length if was_on_floor else 0.05
		var col := p.move_and_collide(Vector3.DOWN * probe, true)
		if col != null and col.get_normal().y >= floor_cos:
			grounded = true
			s.floor_normal = col.get_normal()
			p.global_position += col.get_travel()

	if grounded:
		if s.move_state == Move.AIR:
			s.move_state = Move.GROUND
		s.velocity.y = 0.0
		s.ticks_since_floor = 0
		s.air_jumps_left = 1
	else:
		if s.move_state == Move.GROUND or s.move_state == Move.SLIDE:
			if s.move_state == Move.SLIDE:
				_end_slide(p, false)
			s.move_state = Move.AIR
		s.ticks_since_floor = mini(s.ticks_since_floor + 1, 1000)
		s.floor_normal = Vector3.UP
	s.position = p.global_position


## `motion`'s horizontal part, tilted onto the plane with normal `n`
## (horizontal distance unchanged).
static func _along_floor(motion: Vector3, n: Vector3) -> Vector3:
	if n.y > 0.9999:
		return Vector3(motion.x, 0.0, motion.z)
	return Vector3(motion.x, -(n.x * motion.x + n.z * motion.z) / n.y, motion.z)


static func _find_mantle_target(p: SimPlayer, fwd: Vector3) -> Variant:
	var cfg := p.config
	var space := p.get_world_3d().direct_space_state
	var feet := p.global_position
	var reach := cfg.capsule_radius + cfg.mantle_reach
	var wall := {}
	for h in [cfg.mantle_min_height, 1.0]:
		var from := feet + Vector3(0.0, h, 0.0)
		var hit := _ray(space, from, from + fwd * reach)
		if not hit.is_empty() and absf(hit.normal.y) < 0.3:
			wall = hit
			break
	if wall.is_empty():
		return null
	var over: Vector3 = wall.position + fwd * 0.3
	var top := _ray(space,
			Vector3(over.x, feet.y + cfg.mantle_max_height + 0.3, over.z),
			Vector3(over.x, feet.y + 0.2, over.z))
	if top.is_empty() or top.normal.y < cos(deg_to_rad(cfg.max_floor_angle_deg)):
		return null
	var height: float = top.position.y - feet.y
	if height < 0.25 or height > cfg.mantle_max_height:
		return null
	var target: Vector3 = top.position + Vector3(0.0, 0.02, 0.0)
	if not _fits(p, target, cfg.stand_height):
		return null
	var head := feet + Vector3(0.0, cfg.height_for(p.state.stance), 0.0)
	if not _ray(space, head, Vector3(head.x, target.y + cfg.stand_height, head.z)).is_empty():
		return null
	return target


static func _start_mantle(p: SimPlayer, target: Vector3) -> void:
	var s := p.state
	s.move_state = Move.MANTLE
	s.mantle_tick = 0
	s.mantle_start = s.position
	s.mantle_target = target
	s.velocity = Vector3.ZERO
	s.sprinting = false
	s.jump_buffer_ticks = 0
	s.stance = Stance.STAND
	p.apply_stance_shape(s.stance)


static func _step_mantle(p: SimPlayer) -> void:
	var s := p.state
	var cfg := p.config
	s.mantle_tick += 1
	var t := float(s.mantle_tick) / cfg.mantle_ticks
	var rise := smoothstep(0.0, 1.0, clampf(t / 0.6, 0.0, 1.0))
	var across := clampf((t - 0.4) / 0.6, 0.0, 1.0)
	var pos := Vector3(
			lerpf(s.mantle_start.x, s.mantle_target.x, across),
			lerpf(s.mantle_start.y, s.mantle_target.y, rise),
			lerpf(s.mantle_start.z, s.mantle_target.z, across))
	p.global_position = pos
	s.position = p.global_position
	if s.mantle_tick >= cfg.mantle_ticks:
		s.move_state = Move.GROUND
		s.velocity = Vector3(-sin(s.yaw), 0.0, -cos(s.yaw)) * cfg.mantle_exit_speed
		s.ticks_since_floor = 0
		s.air_jumps_left = 1


## True if a standing/crouched capsule of `height` fits with its feet at `feet`.
static func _fits(p: SimPlayer, feet: Vector3, height: float) -> bool:
	var shape: CapsuleShape3D = _probe_shapes.get(height)
	if shape == null:
		shape = CapsuleShape3D.new()
		shape.radius = p.config.capsule_radius - 0.02
		shape.height = height
		_probe_shapes[height] = shape
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, height * 0.5 + 0.02, 0.0))
	q.collision_mask = Sim.LAYER_WORLD
	return p.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Sim.LAYER_WORLD))
