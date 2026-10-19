class_name PlayerVisual
extends Node3D
## Third-person stand-in for another player (greybox): capsule body, visor and
## nameplate. Interpolated between the previous and current simulation ticks.

var _body: MeshInstance3D
var _visor: MeshInstance3D
var _label: Label3D
var _material := StandardMaterial3D.new()
var _height: float = 1.8


func setup(display_name: String, is_bot: bool, color: Color) -> void:
	_material.albedo_color = color
	_material.roughness = 0.5
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 0.0
	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	_body.mesh = capsule
	_body.material_override = _material
	add_child(_body)
	_visor = MeshInstance3D.new()
	var visor := BoxMesh.new()
	visor.size = Vector3(0.5, 0.14, 0.12)
	_visor.mesh = visor
	var visor_mat := StandardMaterial3D.new()
	visor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visor_mat.albedo_color = Color(0.35, 0.9, 1.0)
	_visor.material_override = visor_mat
	add_child(_visor)
	_label = Label3D.new()
	_label.text = ("[BOT] " if is_bot else "") + display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 8
	_label.no_depth_test = false
	add_child(_label)


## `prev`/`cur` are the states at the last two ticks; `alpha` is the fraction
## between them (render frames run faster than the 60 Hz simulation).
func update_from(prev: PlayerSimState, cur: PlayerSimState, alpha: float, time: float) -> void:
	visible = cur.alive
	if not cur.alive:
		return
	# Never interpolate across a respawn or teleport (PLAN §3.3.4).
	var from := prev if prev != null and prev.discontinuity_gen == cur.discontinuity_gen else cur
	position = from.position.lerp(cur.position, alpha)
	rotation.y = lerp_angle(from.yaw, cur.yaw, alpha)
	var target_h := 1.8 if cur.stance == PlayerSimState.Stance.STAND else 1.2
	_height = lerpf(_height, target_h, 0.3)
	_body.scale = Vector3(1.0, _height / 1.8, 1.0)
	_body.position.y = _height * 0.5
	_visor.position = Vector3(0.0, _height - 0.25, -0.33)
	_label.position.y = _height + 0.45
	var shimmer := 0.0
	if cur.spawn_protection_ticks > 0:
		shimmer = 0.6 + 0.6 * sin(time * 18.0)
	_material.emission_energy_multiplier = shimmer
