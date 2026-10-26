class_name JumpPadVisuals
extends Node3D
## Jump pads on the floor (JumpPads): a glowing violet disc with rings
## rising off it and an arrow towards the landing point; the disc flares
## when it throws someone. Presentation only, built from the gameplay
## scene's jump_pads().

const COLOR := Color(0.6, 0.45, 1.0)
const BASE_COLOR := Color(0.22, 0.14, 0.45)
const RINGS := 3
const RISE_TIME := 1.2
const RISE_HEIGHT := 1.6

var _pads: Array[Dictionary] = []  ## {position, root, disc material, rings, flare}
var _time: float = 0.0


func build(pads: Array) -> void:
	for pad: Dictionary in pads:
		_pads.append(_make(pad))
	RenderLayers.mark_dynamic(self)


## A player took off at `at`: flare the pad there.
func launched(at: Vector3) -> void:
	for pad in _pads:
		if Vector2(at.x - pad.position.x, at.z - pad.position.z).length() < JumpPads.RADIUS + 0.6:
			pad.flare = 1.0


func _process(delta: float) -> void:
	_time += delta
	for pad in _pads:
		pad.flare = maxf(pad.flare - delta * 2.5, 0.0)
		(pad.disc as StandardMaterial3D).emission_energy_multiplier = 0.5 + 0.25 * sin(_time * 4.0) + pad.flare * 5.0
		for i in RINGS:
			var t := fmod(_time / RISE_TIME + float(i) / RINGS, 1.0)
			var ring: MeshInstance3D = pad.rings[i]
			ring.position.y = 0.08 + t * RISE_HEIGHT
			ring.scale = Vector3.ONE * lerpf(1.0, 0.55, t)
			(ring.material_override as StandardMaterial3D).albedo_color.a = (1.0 - t) * 0.7


func _make(pad: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.position = pad.position
	add_child(root)
	var disc_mat := _material(1.0, 0.5, BASE_COLOR)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = JumpPads.RADIUS * 0.9
	cyl.bottom_radius = JumpPads.RADIUS * 0.9
	cyl.height = 0.04
	cyl.radial_segments = 24
	disc.mesh = cyl
	disc.material_override = disc_mat
	disc.position.y = 0.02
	_no_shadow(disc)
	root.add_child(disc)
	var rim := MeshInstance3D.new()
	rim.mesh = _torus(JumpPads.RADIUS - 0.08, JumpPads.RADIUS)
	rim.material_override = _material(1.0, 2.5)
	rim.scale = Vector3(1, 0.4, 1)
	rim.position.y = 0.05
	_no_shadow(rim)
	root.add_child(rim)
	# An arrow on the disc pointing at the landing point.
	var dir: Vector3 = ((pad.target - pad.position) * Vector3(1, 0, 1)).normalized()
	var arrow := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.7, 0.6, 0.03)
	arrow.mesh = prism
	arrow.material_override = _material(1.0, 3.0, Color(0.92, 0.88, 1.0))
	arrow.basis = Basis.looking_at(Vector3.DOWN, dir)  # flat, tip towards `dir`
	arrow.position = Vector3(0, 0.06, 0) + dir * 0.1
	_no_shadow(arrow)
	root.add_child(arrow)
	var rings: Array[MeshInstance3D] = []
	for i in RINGS:
		var ring := MeshInstance3D.new()
		ring.mesh = _torus(JumpPads.RADIUS * 0.75, JumpPads.RADIUS * 0.82)
		var mat := _material(0.7, 2.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = mat
		_no_shadow(ring)
		root.add_child(ring)
		rings.append(ring)
	if Settings.video("lights") == true:
		var light := OmniLight3D.new()
		light.light_color = COLOR
		light.light_energy = 1.2
		light.omni_range = 3.0
		light.position.y = 0.5
		root.add_child(light)
	return {"position": pad.position, "root": root, "disc": disc_mat, "rings": rings, "flare": 0.0}


static func _material(alpha: float, energy: float, color: Color = COLOR) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func _torus(inner: float, outer: float) -> TorusMesh:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 32
	torus.ring_segments = 6
	return torus


static func _no_shadow(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
