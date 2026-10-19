class_name Effects
extends Node3D
## Visual effects driven by simulation events: tracers, impacts, rockets and
## explosions. Every event is shown once, keyed by its unique ID, so
## prediction replays (M1b) can never duplicate an effect (PLAN §3.1).

var _seen: Dictionary = {}  ## event id -> tick
var _fading: Array = []  ## [node, age, lifetime, kind]
var _rockets: Dictionary = {}  ## projectile id -> [node, prev_pos, cur_pos]
var _tracer_mat := _unshaded(Color(0.6, 0.95, 1.0))
var _impact_mat := _unshaded(Color(1.0, 0.85, 0.5))
var _rocket_mat := _unshaded(Color(1.0, 0.6, 0.25))
var _explosion_mat: StandardMaterial3D


func _ready() -> void:
	_explosion_mat = _unshaded(Color(1.0, 0.65, 0.3, 0.8))
	_explosion_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


## Returns false if this event was already handled.
func first_time(event: Dictionary) -> bool:
	if _seen.has(event.id):
		return false
	_seen[event.id] = event.tick
	if _seen.size() > 2000:
		var cutoff: int = event.tick - 600
		for id in _seen.keys():
			if _seen[id] < cutoff:
				_seen.erase(id)
	return true


func tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, length)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	mi.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	_fading.append([mi, 0.0, 0.06, "shrink"])


func impact(at: Vector3, big: bool = false) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.12 if big else 0.07
	mesh.height = mesh.radius * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _impact_mat
	add_child(mi)
	mi.global_position = at
	_fading.append([mi, 0.0, 0.15, "shrink"])


func explosion(at: Vector3, radius: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _explosion_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.set_meta("radius", radius)
	_fading.append([mi, 0.0, 0.3, "grow"])
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 6.0
	light.omni_range = radius * 2.5
	add_child(light)
	light.global_position = at
	_fading.append([light, 0.0, 0.3, "light"])


## Rockets follow the simulation's projectile list, interpolated between ticks.
func sync_projectiles(projectiles: Array, alpha: float) -> void:
	var alive := {}
	for proj in projectiles:
		var id: String = proj.id()
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
			"shrink":
				node.scale = Vector3.ONE * (1.0 - t)
			"grow":
				node.scale = Vector3.ONE * (node.get_meta("radius") as float) * lerpf(0.3, 1.0, t)
				node.transparency = t
			"light":
				(node as OmniLight3D).light_energy = 6.0 * (1.0 - t)
		keep.append(f)
	_fading = keep


func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m
