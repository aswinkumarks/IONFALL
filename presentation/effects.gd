class_name Effects
extends Node3D
## Visual effects driven by simulation events: tracers, impacts, rockets and
## explosions. Every event is shown once, keyed by its unique ID, so
## prediction replays (M1b) can never duplicate an effect (PLAN §3.1).

var _seen: Dictionary = {}  ## event id -> local time first seen (ms)
var _fading: Array = []  ## [node, age, lifetime, kind]
var _rockets: Dictionary = {}  ## projectile id -> [node, prev_pos, cur_pos]
var _tracer_mat := _glow(Color(0.45, 0.9, 1.0), 5.0)
var _trail_mat := _glow(Color(0.35, 0.85, 1.0), 2.0, true)
var _rocket_mat := _glow(Color(1.0, 0.6, 0.25), 6.0)
var _explosion_mat := _glow(Color(1.0, 0.6, 0.28), 4.0, true)
var _ring_mat := _glow(Color(1.0, 0.75, 0.45), 3.0, true)
var _flash_mat: StandardMaterial3D
var _bolt_mesh := BoxMesh.new()
var _ring_mesh := TorusMesh.new()
var _sphere := SphereMesh.new()
var _quad := QuadMesh.new()


func _ready() -> void:
	_bolt_mesh.size = Vector3(0.03, 0.03, 2.2)
	_ring_mesh.inner_radius = 0.9
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 16
	_sphere.rings = 8
	_quad.size = Vector2(1, 1)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.albedo_texture = FirstPersonView._flash_texture()


## Forget handled event ids: a new session (reconnect) reuses them.
func reset_seen() -> void:
	_seen.clear()


## Returns false if this event was already handled.
func first_time(event: Dictionary) -> bool:
	if _seen.has(event.id):
		return false
	var now := Time.get_ticks_msec()
	_seen[event.id] = now
	if _seen.size() > 2000:
		# Server copies of an event arrive within a second of the local one.
		var cutoff := now - 10000
		for id in _seen.keys():
			if _seen[id] < cutoff:
				_seen.erase(id)
	return true


## A bolt that flies from `from` to `to` at 320 m/s, leaving a faint beam.
func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(0.012, 0.012, length)
	beam.mesh = beam_mesh
	beam.material_override = _trail_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	beam.global_position = (from + to) * 0.5
	beam.look_at(to, up)
	_fading.append([beam, 0.0, 0.12, "thin"])
	var bolt := MeshInstance3D.new()
	bolt.mesh = _bolt_mesh
	bolt.material_override = _tracer_mat
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bolt)
	bolt.global_position = from
	bolt.look_at(to, up)
	bolt.set_meta("from", from)
	bolt.set_meta("to", to)
	_fading.append([bolt, 0.0, maxf(length / 320.0, 0.02), "fly"])


## Sparks and a flash; player hits are bigger and shield-coloured.
func impact(at: Vector3, big: bool = false) -> void:
	var color := Color(0.45, 0.9, 1.0) if big else Color(1.0, 0.82, 0.5)
	_spark_flash(at, 0.5 if big else 0.32, color, 0.09)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 14 if big else 9
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var spark := BoxMesh.new()
	spark.size = Vector3(0.015, 0.015, 0.09)
	spark.material = _glow(color, 5.0)
	p.mesh = spark
	p.particle_flag_align_y = true
	add_child(p)
	p.global_position = at
	p.restart()
	_fading.append([p, 0.0, 0.6, "none"])


func _spark_flash(at: Vector3, size: float, color: Color, life: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = _flash_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.set_meta("size", size)
	mi.scale = Vector3.ONE * size
	var mat := _flash_mat.duplicate() as StandardMaterial3D
	mat.albedo_color = color
	mi.material_override = mat
	_fading.append([mi, 0.0, life, "pop"])


func explosion(at: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	mi.material_override = _explosion_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.set_meta("radius", radius * 0.8)
	_fading.append([mi, 0.0, 0.35, "grow"])
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = at
	ring.set_meta("radius", radius * 1.4)
	_fading.append([ring, 0.0, 0.4, "ring"])
	_spark_flash(at, radius * 1.2, Color(1.0, 0.7, 0.4), 0.15)
	var debris := CPUParticles3D.new()
	debris.one_shot = true
	debris.amount = 24
	debris.lifetime = 0.8
	debris.explosiveness = 1.0
	debris.spread = 180.0
	debris.initial_velocity_min = 4.0
	debris.initial_velocity_max = 11.0
	debris.gravity = Vector3(0, -14, 0)
	var spark := BoxMesh.new()
	spark.size = Vector3(0.03, 0.03, 0.18)
	spark.material = _glow(Color(1.0, 0.65, 0.3), 5.0)
	debris.mesh = spark
	debris.particle_flag_align_y = true
	add_child(debris)
	debris.global_position = at
	debris.restart()
	_fading.append([debris, 0.0, 1.0, "none"])
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 6.0
	light.omni_range = radius * 2.5
	add_child(light)
	light.global_position = at
	_fading.append([light, 0.0, 0.35, "light"])


## A player's body breaks up into glowing fragments that rise and fade.
func derez(feet: Vector3, color: Color) -> void:
	var at := feet + Vector3(0.0, 0.9, 0.0)
	_spark_flash(at, 1.6, color, 0.2)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.9
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.85, 0.3)
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var frag := BoxMesh.new()
	frag.size = Vector3(0.07, 0.07, 0.07)
	frag.material = _glow(color, 3.0)
	p.mesh = frag
	add_child(p)
	p.global_position = at
	p.restart()
	_fading.append([p, 0.0, 1.2, "none"])
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = _glow(color, 2.5, true)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = feet + Vector3(0.0, 0.05, 0.0)
	ring.set_meta("radius", 1.4)
	_fading.append([ring, 0.0, 0.5, "ring"])


## Rockets follow the simulation's projectile list, interpolated between ticks.
## Accepts SimWorld.Projectile objects (host) or snapshot dictionaries
## {id, position, velocity} already placed at render time (client, alpha 1).
func sync_projectiles(projectiles: Array, alpha: float) -> void:
	var alive := {}
	for proj in projectiles:
		var id: String = proj.id if proj is Dictionary else proj.id()
		alive[id] = true
		var entry: Array = _rockets.get(id, [])
		if entry.is_empty():
			var mesh := CapsuleMesh.new()
			mesh.radius = 0.08
			mesh.height = 0.45
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = _rocket_mat
			add_child(mi)
			var trail := CPUParticles3D.new()
			trail.amount = 24
			trail.lifetime = 0.35
			trail.local_coords = false
			trail.spread = 10.0
			trail.direction = Vector3.DOWN
			trail.initial_velocity_min = 0.5
			trail.initial_velocity_max = 1.5
			trail.gravity = Vector3.ZERO
			trail.scale_amount_min = 0.6
			trail.scale_amount_max = 1.0
			var puff := SphereMesh.new()
			puff.radius = 0.07
			puff.height = 0.14
			puff.radial_segments = 6
			puff.rings = 3
			puff.material = _glow(Color(1.0, 0.55, 0.25), 2.5)
			trail.mesh = puff
			mi.add_child(trail)
			entry = [mi, proj.position, proj.position]
			_rockets[id] = entry
		elif entry[2] != proj.position:
			entry[1] = entry[2]
			entry[2] = proj.position
		var node: MeshInstance3D = entry[0]
		node.global_position = (entry[1] as Vector3).lerp(entry[2], alpha)
		var vel: Vector3 = proj.velocity
		if vel.length_squared() > 0.01:
			node.look_at(node.global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT)
			node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	for id in _rockets.keys():
		if not alive.has(id):
			(_rockets[id][0] as Node).queue_free()
			_rockets.erase(id)


func _process(delta: float) -> void:
	var keep: Array = []
	for f in _fading:
		f[1] += delta
		var t: float = f[1] / f[2]
		var node: Node3D = f[0]
		if t >= 1.0:
			node.queue_free()
			continue
		match f[3]:
			"thin":
				node.scale = Vector3(1.0 - t, 1.0 - t, 1.0)
			"fly":
				var a: Vector3 = node.get_meta("from")
				var b: Vector3 = node.get_meta("to")
				node.global_position = a.lerp(b, t)
			"pop":
				node.scale = Vector3.ONE * (node.get_meta("size") as float) * (1.0 + t * 0.6)
				node.transparency = t
			"grow":
				node.scale = Vector3.ONE * (node.get_meta("radius") as float) * lerpf(0.25, 1.0, sqrt(t))
				node.transparency = t
			"ring":
				node.scale = Vector3.ONE * (node.get_meta("radius") as float) * lerpf(0.2, 1.0, sqrt(t))
				node.transparency = t
			"light":
				(node as OmniLight3D).light_energy = 6.0 * (1.0 - t)
		keep.append(f)
	_fading = keep


## Emissive material: bright enough to bloom; `soft` makes it additive
## and see-through.
static func _glow(color: Color, energy: float, soft: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color * minf(energy, 1.0), 1.0)
	if soft:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(color, 0.8)
	m.albedo_color = m.albedo_color * Color(energy, energy, energy, 1.0)
	return m
