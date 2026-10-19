class_name PartsRig
extends CharacterRig
## Rigid-parts body: 12 boxes on pivots (12 draws per character plus their
## shadows), procedurally swung by movement speed. The PLAN §4 alternative
## to SkinnedRig.

const STRIDE := 1.6  ## metres per full leg cycle

static var _meshes: Dictionary = {}

var _material := StandardMaterial3D.new()
var _visor_material := StandardMaterial3D.new()
var _root: Node3D
var _pivots: Dictionary = {}  ## name -> Node3D
var _phase: float = 0.0
var _swing: float = 0.0


static func _box(size: Vector3) -> BoxMesh:
	if not _meshes.has(size):
		var m := BoxMesh.new()
		m.size = size
		_meshes[size] = m
	return _meshes[size]


func setup(color: Color) -> void:
	_material.albedo_color = color
	_material.roughness = 0.55
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 0.0
	_visor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_visor_material.albedo_color = Color(0.35, 0.9, 1.0)
	_root = Node3D.new()
	add_child(_root)
	var hips := _pivot("hips", _root, Vector3(0, 0.95, 0))
	_part(hips, Vector3(0.38, 0.18, 0.24), Vector3(0, 0.0, 0))
	var chest := _pivot("chest", hips, Vector3(0, 0.1, 0))
	_part(chest, Vector3(0.46, 0.5, 0.28), Vector3(0, 0.25, 0))
	var neck := _pivot("neck", chest, Vector3(0, 0.52, 0))
	_part(neck, Vector3(0.26, 0.26, 0.26), Vector3(0, 0.14, 0))
	_part(neck, Vector3(0.22, 0.07, 0.04), Vector3(0, 0.16, -0.14), _visor_material)
	for side in [-1.0, 1.0]:
		var tag := "l" if side < 0 else "r"
		var shoulder := _pivot(tag + "_shoulder", chest, Vector3(side * 0.31, 0.45, 0))
		_part(shoulder, Vector3(0.13, 0.32, 0.13), Vector3(0, -0.15, 0))
		var elbow := _pivot(tag + "_elbow", shoulder, Vector3(0, -0.31, 0))
		_part(elbow, Vector3(0.11, 0.3, 0.11), Vector3(0, -0.14, 0))
		var hip := _pivot(tag + "_hip", hips, Vector3(side * 0.11, -0.06, 0))
		_part(hip, Vector3(0.16, 0.44, 0.16), Vector3(0, -0.21, 0))
		var knee := _pivot(tag + "_knee", hip, Vector3(0, -0.43, 0))
		_part(knee, Vector3(0.14, 0.44, 0.16), Vector3(0, -0.22, 0))


func _pivot(pivot_name: String, parent: Node3D, offset: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = offset
	parent.add_child(p)
	_pivots[pivot_name] = p
	return p


func _part(parent: Node3D, size: Vector3, offset: Vector3, mat: Material = null) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _box(size)
	m.position = offset
	m.material_override = mat if mat != null else _material
	parent.add_child(m)


func animate(state: PlayerSimState, delta: float, height: float) -> void:
	_root.scale.y = height / 1.8
	var flat := Vector3(state.velocity.x, 0.0, state.velocity.z)
	var speed := flat.length()
	var airborne := state.move_state == PlayerSimState.Move.AIR
	var target := 0.0 if airborne else clampf(speed / 6.0, 0.0, 1.0)
	_swing = lerpf(_swing, target, minf(delta * 8.0, 1.0))
	var backwards := flat.rotated(Vector3.UP, -state.yaw).z > 0.1
	_phase = fmod(_phase + (speed / STRIDE) * TAU * delta * (-1.0 if backwards else 1.0), TAU)
	var s := sin(_phase) * 0.9 * _swing
	var tuck := 0.6 if airborne else 0.0
	_pivots.l_hip.rotation.x = s + tuck
	_pivots.r_hip.rotation.x = -s + tuck * 0.4
	_pivots.l_knee.rotation.x = -maxf(-s, 0.0) * 1.2 - tuck
	_pivots.r_knee.rotation.x = -maxf(s, 0.0) * 1.2 - tuck * 0.8
	_pivots.l_shoulder.rotation.x = -s * 0.8
	_pivots.r_shoulder.rotation.x = s * 0.8
	_pivots.l_elbow.rotation.x = 0.3 + 0.4 * _swing
	_pivots.r_elbow.rotation.x = 0.3 + 0.4 * _swing
	_pivots.chest.rotation.x = -0.12 * _swing
	_pivots.neck.rotation.x = clampf(state.pitch, -0.6, 0.6) * 0.5
	_pivots.hips.position.y = 0.95 + absf(sin(_phase)) * 0.04 * _swing


func set_glow(amount: float) -> void:
	_material.emission_energy_multiplier = amount
