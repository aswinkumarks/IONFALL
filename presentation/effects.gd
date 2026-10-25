class_name Effects
extends Node3D
## Visual effects driven by simulation events: tracers, muzzle flashes,
## impacts, rockets, explosions, spawns, pickups and deaths. Every event is
## shown once, keyed by its unique ID, so prediction replays (M1b) can never
## duplicate an effect (PLAN §3.1).
##
## Particles are GPU particles with shared process materials and meshes, so
## a burst never compiles a new shader. Their counts scale with the effects
## density setting, and all live particles stay within MAX_PARTICLES (PLAN
## §3.10: ≤ 2,000 live).

const MAX_PARTICLES := 2000
## Live effect nodes (about one draw call each) at full effects density;
## cosmetic effects are skipped beyond it (§3.10: ≤ 250 draw calls with 16
## players in a fight, m4.md). Tracers lose their beam beyond it and are
## skipped beyond twice it; rockets and explosions always show.
const MAX_EFFECT_NODES := 60

## Live particles (for the debug overlay and the budget).
var live_particles: int = 0

var _seen: Dictionary = {}  ## event id -> local time first seen (ms)
var _fading: Array = []  ## [node, age, lifetime, kind]
var _uncapped: bool = false  ## during warm_up: every kind must be drawn
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
var _column := CylinderMesh.new()
var _beam_mesh := BoxMesh.new()
## Particle kinds: name -> [ParticleProcessMaterial, mesh]; meshes for a
## colour are cached per colour.
var _kinds: Dictionary = {}
var _meshes: Dictionary = {}  ## "kind/color" -> Mesh
var _flash_mats: Dictionary = {}  ## color -> StandardMaterial3D
## Idle nodes for reuse: pool key -> Array. Effects fire many times a second
## in a fight; creating and freeing nodes (and particle buffers) for each was
## a measurable main-thread cost on the Mi 11X (M4).
var _pool: Dictionary = {}


func _ready() -> void:
	_bolt_mesh.size = Vector3(0.03, 0.03, 2.2)
	_beam_mesh.size = Vector3(1, 1, 1)
	_ring_mesh.inner_radius = 0.9
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 4
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 16
	_sphere.rings = 8
	_quad.size = Vector2(1, 1)
	_column.top_radius = 0.45
	_column.bottom_radius = 0.45
	_column.height = 1.0
	_column.radial_segments = 16
	_column.rings = 1
	_column.cap_top = false
	_column.cap_bottom = false
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_flash_mat.albedo_texture = FirstPersonView._flash_texture()
	# [velocity min, max, gravity y, spread, scale min, max, align to velocity]
	_kinds.sparks = _particle_process(2.0, 6.0, -12.0, 180.0, 0.5, 1.0, true)
	_kinds.debris = _particle_process(4.0, 11.0, -14.0, 180.0, 0.6, 1.0, true)
	_kinds.derez = _particle_process(0.8, 2.6, 1.5, 35.0, 0.6, 1.2, false)
	(_kinds.derez as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(_kinds.derez as ParticleProcessMaterial).emission_box_extents = Vector3(0.3, 0.85, 0.3)
	_kinds.rise = _particle_process(1.5, 3.5, 0.0, 8.0, 0.5, 1.0, true)
	(_kinds.rise as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	(_kinds.rise as ParticleProcessMaterial).emission_ring_axis = Vector3.UP
	(_kinds.rise as ParticleProcessMaterial).emission_ring_radius = 0.5
	(_kinds.rise as ParticleProcessMaterial).emission_ring_inner_radius = 0.4
	(_kinds.rise as ParticleProcessMaterial).emission_ring_height = 0.05
	_kinds.trail = _particle_process(0.5, 1.5, 0.0, 10.0, 0.6, 1.0, false)
	(_kinds.trail as ParticleProcessMaterial).direction = Vector3.DOWN


## Shader warm-up (Warmup): every kind of effect once at `at`, so their
## pipelines compile behind the loading cover instead of mid-fight.
func warm_up(at: Vector3) -> void:
	var side := Vector3(1.5, 0.0, 0.0)
	_uncapped = true
	tracer(at - side, at + side)
	tracer(at - side, at + side + Vector3.UP, true)
	muzzle_flash(at)
	impact(at, false)
	impact(at + Vector3.UP * 0.5, true)
	explosion(at, 1.0)
	derez(at - Vector3.UP, Color(0.35, 0.9, 1.0))
	spawn_in(at - Vector3.UP, Color(1.0, 0.6, 0.25))
	pickup_burst(at, Color(0.45, 1.0, 0.55))
	_uncapped = false
	for node: Node3D in [_rocket_node(), _grenade_node()]:
		node.global_position = at
		_fading.append([node, 0.0, 0.3, "none"])


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
## The Rail Sniper leaves a thicker beam that lingers.
func tracer(from: Vector3, to: Vector3, rail: bool = false) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	# Tracers matter for gameplay, so they get twice the cosmetic budget; when
	# effects are already crowded only the bolt is drawn, not the faint beam.
	if _crowded(2.0):
		return
	if not _crowded():
		var beam := _mesh_node()
		beam.mesh = _beam_mesh
		beam.material_override = _trail_mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.global_position = (from + to) * 0.5
		beam.look_at(to, up)
		var width := 0.05 if rail else 0.012
		beam.scale = Vector3(width, width, length)
		beam.set_meta("width", width)
		_fading.append([beam, 0.0, 0.6 if rail else 0.12, "thin"])
	var bolt := _mesh_node()
	bolt.mesh = _bolt_mesh
	bolt.material_override = _tracer_mat
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.global_position = from
	bolt.look_at(to, up)
	bolt.set_meta("from", from)
	bolt.set_meta("to", to)
	_fading.append([bolt, 0.0, maxf(length / 320.0, 0.02), "fly"])


## A third-person muzzle flash.
func muzzle_flash(at: Vector3, color: Color = Color(0.7, 0.95, 1.0)) -> void:
	if _crowded():
		return
	_spark_flash(at, 0.35, color, 0.05)


## Sparks and a flash; player hits are bigger and shield-coloured.
func impact(at: Vector3, big: bool = false) -> void:
	if _crowded():
		return
	var color := Color(0.45, 0.9, 1.0) if big else Color(1.0, 0.82, 0.5)
	_spark_flash(at, 0.5 if big else 0.32, color, 0.09)
	_burst(at, "sparks", color, 14 if big else 9, 0.35)


func explosion(at: Vector3, radius: float) -> void:
	var mi := _mesh_node()
	mi.mesh = _sphere
	mi.material_override = _explosion_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = at
	mi.set_meta("radius", radius * 0.8)
	_fading.append([mi, 0.0, 0.35, "grow"])
	var ring := _mesh_node()
	ring.mesh = _ring_mesh
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.global_position = at
	ring.set_meta("radius", radius * 1.4)
	_fading.append([ring, 0.0, 0.4, "ring"])
	_spark_flash(at, radius * 1.2, Color(1.0, 0.7, 0.4), 0.15)
	_burst(at, "debris", Color(1.0, 0.65, 0.3), 24, 0.8)
	if Settings.video("lights") != true:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = _explosion_energy()
	light.omni_range = radius * 2.5
	light.shadow_enabled = false
	add_child(light)
	light.global_position = at
	_fading.append([light, 0.0, 0.35, "light"])


## A player's body breaks up into glowing fragments that rise and fade.
func derez(feet: Vector3, color: Color) -> void:
	if _crowded():
		return
	var at := feet + Vector3(0.0, 0.9, 0.0)
	_spark_flash(at, 1.6, color, 0.2)
	_burst(at, "derez", color, 28, 0.9, 0.85)
	_ring(feet + Vector3(0.0, 0.05, 0.0), color, 1.4, 0.5)


## Another player materialises: a column of light, a ring and rising motes.
func spawn_in(feet: Vector3, color: Color) -> void:
	if _crowded():
		return
	var col := _mesh_node()
	col.mesh = _column
	col.material_override = _soft_glow(color, 2.0)
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	col.global_position = feet + Vector3(0.0, 1.2, 0.0)
	_fading.append([col, 0.0, 0.5, "column"])
	_ring(feet + Vector3(0.0, 0.05, 0.0), color, 1.2, 0.45)
	_burst(feet, "rise", color, 16, 0.6, 0.6)


## A pickup was taken: a small ring and sparks in the item's colour.
func pickup_burst(at: Vector3, color: Color) -> void:
	if _crowded():
		return
	_spark_flash(at, 0.8, color, 0.15)
	_ring(at, color, 0.8, 0.35)
	_burst(at, "sparks", color, 10, 0.4)


func _ring(at: Vector3, color: Color, radius: float, life: float) -> void:
	var ring := _mesh_node()
	ring.mesh = _ring_mesh
	ring.material_override = _soft_glow(color, 2.5)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.global_position = at
	ring.set_meta("radius", radius)
	_fading.append([ring, 0.0, life, "ring"])


func _spark_flash(at: Vector3, size: float, color: Color, life: float) -> void:
	if _reduce_flashes():  # accessibility: smaller and dimmer (additive blend)
		size *= 0.55
		color = Color(color * 0.5, color.a)
	var mi := _mesh_node()
	mi.mesh = _quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.global_position = at
	mi.set_meta("size", size)
	mi.scale = Vector3.ONE * size
	if not _flash_mats.has(color):
		var mat := _flash_mat.duplicate() as StandardMaterial3D
		mat.albedo_color = color
		_flash_mats[color] = mat
	mi.material_override = _flash_mats[color]
	_fading.append([mi, 0.0, life, "pop"])


static func _reduce_flashes() -> bool:
	return Settings.get_value("accessibility", "reduce_flashes") == true


static func _explosion_energy() -> float:
	return 2.0 if _reduce_flashes() else 6.0


## True when the live effect nodes reach the density-scaled budget.
func _crowded(budget_scale: float = 1.0) -> bool:
	return not _uncapped and _fading.size() >= roundi(
			MAX_EFFECT_NODES * budget_scale * clampf(float(Settings.video("effects")), 0.0, 1.0))


## A MeshInstance3D from the pool, visible and reset; the caller sets its
## mesh, material and transform.
func _mesh_node() -> MeshInstance3D:
	var mi: MeshInstance3D = _take("mesh")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.set_meta("pool", "mesh")
		add_child(mi)
	mi.transform = Transform3D.IDENTITY
	mi.transparency = 0.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = true
	return mi


func _take(key: String) -> Node3D:
	var idle: Array = _pool.get(key, [])
	return idle.pop_back() if not idle.is_empty() else null


## Returns a finished effect node to its pool (or frees it).
func _release(node: Node3D) -> void:
	live_particles -= int(node.get_meta("particles", 0))
	if not node.has_meta("pool"):
		node.queue_free()
		return
	node.visible = false
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	var key: String = node.get_meta("pool")
	if not _pool.has(key):
		_pool[key] = []
	(_pool[key] as Array).append(node)


## A one-shot GPU particle burst of `kind` (see _ready), `amount` scaled by
## the effects density and limited by MAX_PARTICLES.
func _burst(at: Vector3, kind: String, color: Color, amount: int, lifetime: float,
		explosiveness: float = 1.0) -> void:
	var n := roundi(amount * clampf(float(Settings.video("effects")), 0.0, 1.0))
	n = mini(n, MAX_PARTICLES - live_particles)
	if n <= 0:
		return
	var key := "p/%s/%s/%d/%.2f/%.2f" % [kind, color.to_html(), n, lifetime, explosiveness]
	var p: GPUParticles3D = _take(key)
	if p == null:
		p = GPUParticles3D.new()
		p.one_shot = true
		p.amount = n
		p.lifetime = lifetime
		p.explosiveness = explosiveness
		p.process_material = _kinds[kind]
		p.draw_pass_1 = _particle_mesh(kind, color)
		p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Y_TO_VELOCITY \
				if (_kinds[kind] as ParticleProcessMaterial).particle_flag_align_y else GPUParticles3D.TRANSFORM_ALIGN_DISABLED
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
		p.set_meta("pool", key)
		p.set_meta("particles", n)
		add_child(p)
	p.visible = true
	p.global_position = at
	p.restart()
	live_particles += n
	_fading.append([p, 0.0, lifetime + 0.1, "none"])


func _particle_mesh(kind: String, color: Color) -> Mesh:
	var key := "%s/%s" % [kind, color.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var mesh: PrimitiveMesh
	match kind:
		"sparks":
			mesh = BoxMesh.new()
			(mesh as BoxMesh).size = Vector3(0.015, 0.09, 0.015)
			mesh.material = _glow(color, 5.0)
		"debris":
			mesh = BoxMesh.new()
			(mesh as BoxMesh).size = Vector3(0.03, 0.18, 0.03)
			mesh.material = _glow(color, 5.0)
		"rise":
			mesh = BoxMesh.new()
			(mesh as BoxMesh).size = Vector3(0.025, 0.2, 0.025)
			mesh.material = _glow(color, 3.0)
		"trail":
			mesh = SphereMesh.new()
			(mesh as SphereMesh).radius = 0.07
			(mesh as SphereMesh).height = 0.14
			(mesh as SphereMesh).radial_segments = 6
			(mesh as SphereMesh).rings = 3
			mesh.material = _glow(color, 2.5)
		_:
			mesh = BoxMesh.new()
			(mesh as BoxMesh).size = Vector3(0.07, 0.07, 0.07)
			mesh.material = _glow(color, 3.0)
	_meshes[key] = mesh
	return mesh


static func _particle_process(v_min: float, v_max: float, gravity: float, spread: float, s_min: float, s_max: float,
		align: bool) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = spread
	m.initial_velocity_min = v_min
	m.initial_velocity_max = v_max
	m.gravity = Vector3(0.0, gravity, 0.0)
	m.scale_min = s_min
	m.scale_max = s_max
	m.particle_flag_align_y = align
	return m


## A frag grenade: the grenade model with a blinking orange light.
func _grenade_node() -> MeshInstance3D:
	var root := MeshInstance3D.new()
	add_child(root)
	root.add_child(WeaponModels.grenade(0.11))
	if Settings.video("lights") != true:
		return root
	var blink := OmniLight3D.new()
	blink.light_color = Color(1.0, 0.45, 0.15)
	blink.omni_range = 1.6
	blink.light_energy = 1.2
	blink.shadow_enabled = false
	root.add_child(blink)
	var tw := blink.create_tween().set_loops()
	tw.tween_property(blink, "light_energy", 0.1, 0.25)
	tw.tween_property(blink, "light_energy", 1.4, 0.05)
	return root


func _rocket_node() -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.45
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _rocket_mat
	add_child(mi)
	var trail := GPUParticles3D.new()
	trail.amount = maxi(roundi(24 * clampf(float(Settings.video("effects")), 0.25, 1.0)), 4)
	trail.lifetime = 0.35
	trail.local_coords = false
	trail.process_material = _kinds.trail
	trail.draw_pass_1 = _particle_mesh("trail", Color(1.0, 0.55, 0.25))
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	mi.add_child(trail)
	live_particles += trail.amount
	mi.set_meta("particles", trail.amount)
	return mi


## Rockets follow the simulation's projectile list, interpolated between ticks.
## Accepts SimWorld.Projectile objects (host) or snapshot dictionaries
## {id, position, velocity} already placed at render time (client, alpha 1).
func sync_projectiles(projectiles: Array, alpha: float) -> void:
	var alive := {}
	for proj in projectiles:
		var id: String = proj.id if proj is Dictionary else proj.id()
		alive[id] = true
		var entry: Array = _rockets.get(id, [])
		var weapon: StringName = proj.get("weapon", &"") if proj is Dictionary else proj.weapon.id
		if entry.is_empty():
			entry = [_grenade_node() if weapon == &"frag_grenade" else _rocket_node(), proj.position, proj.position]
			_rockets[id] = entry
		elif entry[2] != proj.position:
			entry[1] = entry[2]
			entry[2] = proj.position
		var node: MeshInstance3D = entry[0]
		node.global_position = (entry[1] as Vector3).lerp(entry[2], alpha)
		var vel: Vector3 = proj.velocity
		if weapon == &"frag_grenade":
			node.rotation += Vector3(vel.length() * 0.02, 0.0, vel.length() * 0.013)
		elif vel.length_squared() > 0.01:
			node.look_at(node.global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT)
			node.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	for id in _rockets.keys():
		if not alive.has(id):
			var node: Node = _rockets[id][0]
			live_particles -= int(node.get_meta("particles", 0))
			node.queue_free()
			_rockets.erase(id)


func _process(delta: float) -> void:
	Diagnostics.live_particles = live_particles
	var keep: Array = []
	for f in _fading:
		f[1] += delta
		var t: float = f[1] / f[2]
		var node: Node3D = f[0]
		if t >= 1.0:
			_release(node)
			continue
		match f[3]:
			"thin":
				var w: float = node.get_meta("width")
				node.scale = Vector3(w * (1.0 - t), w * (1.0 - t), node.scale.z)
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
			"column":
				node.scale = Vector3(1.0 - t * 0.7, 2.4 * (0.3 + sqrt(t)), 1.0 - t * 0.7)
				node.transparency = t
			"light":
				(node as OmniLight3D).light_energy = _explosion_energy() * (1.0 - t)
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


var _soft_cache: Dictionary = {}


func _soft_glow(color: Color, energy: float) -> StandardMaterial3D:
	var key := "%s/%.1f" % [color.to_html(), energy]
	if not _soft_cache.has(key):
		_soft_cache[key] = _glow(color, energy, true)
	return _soft_cache[key]
