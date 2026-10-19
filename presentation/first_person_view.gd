class_name FirstPersonView
extends Node3D
## Local player's camera and weapon viewmodel. The camera's rotation comes
## straight from the input's live look angles every render frame; its position
## is interpolated between simulation ticks (PLAN §3.3.4).

const WEAPON_COLORS := {
	&"pulse_rifle": Color(0.75, 0.78, 0.82),
	&"arc_launcher": Color(0.95, 0.55, 0.2),
	&"mag_pistol": Color(0.35, 0.4, 0.48),
}

var camera := Camera3D.new()
var _viewmodel := Node3D.new()
var _gun := MeshInstance3D.new()
var _gun_material := StandardMaterial3D.new()
var _muzzle := Node3D.new()
var _flash := MeshInstance3D.new()
var _eye_height: float = 1.6
var _kick: float = 0.0
var _flash_time: float = 0.0
var _last_yaw: float = 0.0
var _last_pitch: float = 0.0
var _sway := Vector2.ZERO


func _ready() -> void:
	# Vertical FOV (Godot keeps height): 68° ≈ 100° horizontal at 16:9.
	camera.fov = 68.0
	camera.near = 0.05
	add_child(camera)
	camera.add_child(_viewmodel)
	var box := BoxMesh.new()
	box.size = Vector3(0.045, 0.055, 0.3)
	_gun.mesh = box
	_gun_material.roughness = 0.4
	_gun_material.metallic = 0.3
	_gun.material_override = _gun_material
	_gun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewmodel.add_child(_gun)
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(0.047, 0.01, 0.2)
	strip.mesh = strip_mesh
	var strip_mat := StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.albedo_color = Color(0.35, 0.9, 1.0)
	strip.material_override = strip_mat
	strip.position = Vector3(0.0, 0.031, 0.0)
	_viewmodel.add_child(strip)
	_muzzle.position = Vector3(0.0, 0.0, -0.17)
	_viewmodel.add_child(_muzzle)
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.035
	flash_mesh.height = 0.07
	_flash.mesh = flash_mesh
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(0.7, 0.95, 1.0)
	_flash.material_override = flash_mat
	_flash.visible = false
	_muzzle.add_child(_flash)


func muzzle_position() -> Vector3:
	return _muzzle.global_position


func kick(strength: float = 1.0) -> void:
	_kick = minf(_kick + 0.6 * strength, 1.5)
	_flash_time = 0.04


func update_view(feet: Vector3, eye_height: float, yaw: float, pitch: float, s: PlayerSimState, weapon: WeaponData, delta: float) -> void:
	_eye_height = lerpf(_eye_height, eye_height, minf(1.0, delta * 14.0))
	global_position = feet + Vector3(0.0, _eye_height, 0.0)
	camera.rotation = Vector3(pitch, yaw, 0.0)

	# Sway from look speed, recoil kick and reload/switch dips.
	var look_delta := Vector2(angle_difference(_last_yaw, yaw), pitch - _last_pitch)
	_last_yaw = yaw
	_last_pitch = pitch
	_sway = _sway.lerp(look_delta * 3.0, minf(1.0, delta * 10.0))
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	var dip := 0.0
	if s.switch_ticks > 0:
		dip = 0.25
	elif s.reload[s.weapon_slot] > 0:
		dip = 0.12
	elif s.sprinting:
		dip = 0.08
	_viewmodel.position = Vector3(0.17 - _sway.x * 0.15, -0.16 - dip + _sway.y * 0.15, -0.52 + _kick * 0.04)
	_viewmodel.rotation = Vector3(_kick * 0.08, 0.0, 0.0)
	if weapon != null:
		_gun_material.albedo_color = WEAPON_COLORS.get(weapon.id, Color.WHITE)
	_flash_time -= delta
	_flash.visible = _flash_time > 0.0
	_viewmodel.visible = s.alive


## Death cam (PLAN §2.6): from where we died, looking at the killer.
func death_cam(from: Vector3, target: Vector3, delta: float) -> void:
	global_position = from
	var to := target - global_position
	if to.length_squared() > 0.01:
		var yaw := atan2(-to.x, -to.z)
		var pitch := atan2(to.y, Vector2(to.x, to.z).length())
		camera.rotation = Vector3(lerp_angle(camera.rotation.x, pitch, minf(1.0, delta * 6.0)),
				lerp_angle(camera.rotation.y, yaw, minf(1.0, delta * 6.0)), 0.0)
	_viewmodel.visible = false
