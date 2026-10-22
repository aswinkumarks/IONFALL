class_name FirstPersonView
extends Node3D
## Local player's camera and weapon viewmodel. The camera's rotation comes
## straight from the input's live look angles every render frame; its position
## is interpolated between simulation ticks (PLAN §3.3.4).
##
## Feel (presentation only, never affects aim): weapon sway from look speed,
## walk bob, sprint pose, crouch/slide tilt, jump lift and landing dip,
## spring recoil, reload and switch animations, muzzle flash with a short
## light, and camera FOV kicks for sprint and slide. "Reduce screen shake"
## scales the camera-side effects down. Scoping zooms the camera and brings
## the weapon to the centre (sniper: hidden behind the HUD's scope overlay).
##
## Arms: the player's own character cut down to its arms
## (CharacterRig.make_first_person), its head just behind the camera; every
## frame two-bone IK reaches the right hand to the weapon's grip and the
## left to its fore-end, so the hands follow every pose above.

const SPRINT_FOV := 6.0
const SLIDE_FOV := 9.0
## Where the camera sits relative to the rig's head bone (the eyes are above
## the head joint).
const EYE_FROM_HEAD := Vector3(0.0, 0.12, 0.0)
## Bladed stance: the (hidden) body turns towards the weapon side, bringing
## the left shoulder forward so the support arm comes up from below.
const STANCE_YAW := -0.45
## First-person weapons are drawn this much larger than their hip offsets
## were tuned for, to sit in life-size hands.
const WEAPON_SCALE := 1.5
## Left-hand support: this far from the grip towards the muzzle, and below the barrel.
const SUPPORT_ALONG := 0.55
const SUPPORT_DROP := 0.035
## Melee bash and grenade throw motions (seconds).
## Seconds to scope fully in or out.
const SCOPE_TIME := 0.14
const WALL_LEAN := 0.14  ## radians of camera roll while wall-running
const MELEE_TIME := 0.32
const THROW_TIME := 0.45

var camera := Camera3D.new()
var _viewmodel := Node3D.new()  ## pose root, animated every frame
var _models: Dictionary = {}  ## weapon id -> Node3D
var _arms: CharacterRig
var _current_id: StringName = &""
var _muzzle: Node3D
var _flash := MeshInstance3D.new()
var _flash_light := OmniLight3D.new()
var _eye_height: float = 1.6
var _base_fov: float = 68.0
var _fov_extra: float = 0.0
var _flash_time: float = 0.0
var _last_yaw: float = 0.0
var _last_pitch: float = 0.0
var _sway := Vector2.ZERO
var _bob_phase: float = 0.0
var _bob_amount: float = 0.0
var _land_dip: float = 0.0
var _was_airborne: bool = false
var _last_vy: float = 0.0
var _recoil: float = 0.0  ## spring: displacement
var _recoil_vel: float = 0.0
var _recoil_roll: float = 0.0
var _pose := Vector3.ZERO  ## smoothed [sprint, crouch/slide, reload/switch] blend
var _cam_dip: float = 0.0
var _melee_t: float = 0.0  ## time left in the melee bash
var _throw_t: float = 0.0  ## time left in the throw dip
## 0 = hip, 1 = fully scoped; eases with SCOPE_TIME.
var scope_amount: float = 0.0
var _wall_lean: float = 0.0
var _scope_target: bool = false
var _scope_zoom: float = 1.0
var _scope_overlay: bool = false


func _ready() -> void:
	_base_fov = float(Settings.get_value("video", "fov"))
	camera.fov = _base_fov
	Events.settings_changed.connect(func(section: String, key: String, value: Variant) -> void:
		if section == "video" and key == "fov":
			_base_fov = float(value))
	camera.near = 0.03
	add_child(camera)
	camera.add_child(_viewmodel)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	_flash.mesh = quad
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mat.albedo_texture = _flash_texture()
	flash_mat.albedo_color = Color(0.6, 0.95, 1.0)
	_flash.material_override = flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_flash_light.light_color = Color(0.45, 0.9, 1.0)
	_flash_light.omni_range = 4.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)


## Soft round spark for the muzzle flash.
static func _flash_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.7, 0.95, 1.0, 0.8), Color(0.3, 0.8, 1.0, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


## First-person arms of `style` (CharacterRig.STYLES) in `color`; rigs that
## can't hold a weapon in first person fall back to `fallback`.
func set_character(style: String, color: Color, fallback: String = "armored") -> void:
	if _arms != null:
		_arms.queue_free()
		_arms = null
	for s: String in [style, fallback]:
		var rig := CharacterRig.create(s)
		camera.add_child(rig)
		rig.setup(color)
		if rig.make_first_person():
			_arms = rig
			_arms.rotation.y = STANCE_YAW
			_arms.position = -EYE_FROM_HEAD - _arms.basis * rig.head_position()
			return
		rig.free()


## Our melee: the weapon jabs forward and across.
func melee() -> void:
	_melee_t = MELEE_TIME


## Our grenade throw: the weapon dips out of the way.
func throw() -> void:
	_throw_t = THROW_TIME


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle != null else camera.global_position


func kick(strength: float = 1.0) -> void:
	_recoil_vel += 9.0 * strength
	_recoil_roll = randf_range(-1.0, 1.0) * 0.04 * strength
	var shake: float = 0.3 if Settings.get_value("accessibility", "reduce_screen_shake") else 1.0
	_cam_dip += 0.006 * strength * shake
	_flash_time = 0.05
	_flash.rotation.z = randf() * TAU
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.25) * (1.6 if strength > 1.5 else 1.0) \
			* (0.55 if Settings.get_value("accessibility", "reduce_flashes") == true else 1.0)


func _show_weapon(id: StringName) -> void:
	if id == _current_id:
		return
	_current_id = id
	for m: Node3D in _models.values():
		m.visible = false
	if not _models.has(id):
		var m := WeaponModels.instantiate(id)
		if m == null:
			return
		m.scale = Vector3.ONE * WEAPON_SCALE
		_viewmodel.add_child(m)
		_models[id] = m
	var model: Node3D = _models[id]
	model.visible = true
	_muzzle = model.get_node("Muzzle")
	if _flash.get_parent() != null:
		_flash.get_parent().remove_child(_flash)
	_muzzle.add_child(_flash)


## Scoped this frame with `weapon` (null: not scoped). Call before update_view.
func set_scope(weapon: WeaponData) -> void:
	_scope_target = weapon != null
	if weapon != null:
		_scope_zoom = weapon.scope_zoom
		_scope_overlay = weapon.scope_overlay


## Whether the full-screen scope overlay should show (sniper, mostly in).
func scope_overlay_visible() -> bool:
	return _scope_overlay and scope_amount > 0.6


func update_view(feet: Vector3, eye_height: float, yaw: float, pitch: float, s: PlayerSimState, weapon: WeaponData, delta: float) -> void:
	var shake: float = 0.3 if Settings.get_value("accessibility", "reduce_screen_shake") else 1.0
	_eye_height = lerpf(_eye_height, eye_height, minf(1.0, delta * 14.0))
	# Landing: a dip proportional to the fall speed.
	var airborne := s.move_state == PlayerSimState.Move.AIR
	if _was_airborne and not airborne and _last_vy < -3.0:
		_land_dip = clampf(-_last_vy * 0.012, 0.0, 0.12)
	_was_airborne = airborne
	_last_vy = s.velocity.y
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.5)
	_cam_dip = move_toward(_cam_dip, 0.0, delta * 0.08)
	global_position = feet + Vector3(0.0, _eye_height - _land_dip * 0.6 * shake, 0.0)

	# Walk bob: phase advances with ground speed.
	var speed := Vector2(s.velocity.x, s.velocity.z).length()
	var grounded := s.move_state == PlayerSimState.Move.GROUND
	var bob_target := clampf(speed / 6.0, 0.0, 1.4) if grounded else 0.0
	_bob_amount = lerpf(_bob_amount, bob_target, minf(1.0, delta * 8.0))
	_bob_phase += delta * (6.0 + speed * 0.9)
	var bob := Vector2(sin(_bob_phase) * 0.012, -absf(cos(_bob_phase)) * 0.014) * _bob_amount
	# Wall-run: the head leans away from the wall.
	var lean := 0.0
	if s.move_state == PlayerSimState.Move.WALLRUN:
		lean = -Vector3(cos(yaw), 0.0, -sin(yaw)).dot(s.wall_normal) * WALL_LEAN * shake
	_wall_lean = lerpf(_wall_lean, lean, minf(1.0, delta * 8.0))
	camera.rotation = Vector3(pitch + _cam_dip, yaw, sin(_bob_phase) * 0.004 * _bob_amount * shake + _wall_lean)
	camera.position.y = bob.y * 0.5 * shake

	# FOV kicks
	var fov_target := 0.0
	if s.move_state == PlayerSimState.Move.SLIDE:
		fov_target = SLIDE_FOV
	elif s.sprinting:
		fov_target = SPRINT_FOV
	_fov_extra = lerpf(_fov_extra, fov_target * (0.5 + 0.5 * shake), minf(1.0, delta * 6.0))
	scope_amount = move_toward(scope_amount, 1.0 if _scope_target and s.alive else 0.0, delta / SCOPE_TIME)
	var zoom := lerpf(1.0, _scope_zoom, scope_amount)
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_base_fov + _fov_extra) * 0.5) / zoom))

	# Sway from look speed (the weapon lags the view).
	var look_delta := Vector2(angle_difference(_last_yaw, yaw), pitch - _last_pitch)
	_last_yaw = yaw
	_last_pitch = pitch
	_sway = _sway.lerp((look_delta / maxf(delta, 0.001)) * 0.012, minf(1.0, delta * 9.0))
	_sway = _sway.limit_length(0.6)

	# Recoil spring (critically damped-ish).
	_recoil_vel += (-_recoil * 180.0 - _recoil_vel * 22.0) * delta
	_recoil += _recoil_vel * delta
	_recoil_roll = move_toward(_recoil_roll, 0.0, delta * 0.4)

	# Poses: sprint, crouch/slide, reload/switch.
	var reloading := weapon != null and s.reload[s.weapon_slot] > 0
	var pose_target := Vector3(1.0 if s.sprinting and grounded else 0.0,
			1.0 if s.stance != PlayerSimState.Stance.STAND else 0.0,
			1.0 if s.switch_ticks > 0 else (0.6 if reloading else 0.0))
	_pose = _pose.lerp(pose_target, minf(1.0, delta * 10.0))

	if weapon != null:
		_show_weapon(weapon.id)
	var hip := WeaponModels.hip_offset(_current_id)
	var pos := hip
	pos += Vector3(-_sway.x * 0.03, _sway.y * 0.03, 0.0)
	pos += Vector3(bob.x, bob.y, 0.0)
	pos += Vector3(-0.04, -0.05, 0.03) * _pose.x
	pos += Vector3(-0.02, 0.01, 0.0) * _pose.y
	pos += Vector3(0.0, -0.16, 0.05) * _pose.z
	pos += Vector3(0.0, -_land_dip * 0.4, 0.0)
	pos.z += _recoil * 0.05
	# Scoped: the weapon comes up to the centre, steadier.
	pos = pos.lerp(Vector3(0.0, hip.y + 0.02, hip.z + 0.05), scope_amount * 0.85)
	_melee_t = maxf(_melee_t - delta, 0.0)
	_throw_t = maxf(_throw_t - delta, 0.0)
	var bash := sin(PI * _melee_t / MELEE_TIME) if _melee_t > 0.0 else 0.0
	var dip := sin(PI * _throw_t / THROW_TIME) if _throw_t > 0.0 else 0.0
	pos += Vector3(-0.08, 0.03, -0.16) * bash + Vector3(0.04, -0.22, 0.06) * dip
	_viewmodel.position = pos
	_viewmodel.rotation = Vector3(
		_recoil * 0.12 - _pose.x * 0.35 - _pose.z * 0.5 + _sway.y * 0.15 - dip * 0.6,
		_sway.x * 0.2 + _pose.x * 0.6 + bash * 0.7,
		_recoil_roll + _pose.y * 0.25 + _pose.z * 0.4 - _sway.x * 0.1)

	_flash_time -= delta
	_flash.visible = _flash_time > 0.0
	_flash_light.light_energy = (0.8 if Settings.get_value("accessibility", "reduce_flashes") == true else 2.5) \
			if _flash_time > 0.0 else 0.0
	_flash_light.visible = _flash_time > 0.0 and Settings.video("lights") == true
	if _muzzle != null:
		_flash_light.global_position = _muzzle.global_position
	var behind_scope := scope_overlay_visible()
	_viewmodel.visible = s.alive and not behind_scope
	if _arms != null:
		_arms.visible = s.alive and _models.has(_current_id) and not behind_scope
		if _arms.visible:
			var weapon_node: Node3D = _models[_current_id]
			var to_rig := _arms.global_transform.affine_inverse()
			var grip := weapon_node.global_position
			var support := grip.lerp(_muzzle.global_position, SUPPORT_ALONG) - camera.global_basis.y * SUPPORT_DROP
			var handle := (weapon_node.get_node("Grip") as Node3D).global_position
			_arms.pose_first_person(to_rig * weapon_node.global_transform, to_rig * handle, to_rig * support)


## Death cam (PLAN §2.6): from where we died, looking at the killer.
func death_cam(from: Vector3, target: Vector3, delta: float) -> void:
	scope_amount = 0.0
	global_position = from
	camera.position = Vector3.ZERO
	camera.fov = _base_fov
	var to := target - global_position
	if to.length_squared() > 0.01:
		var yaw := atan2(-to.x, -to.z)
		var pitch := atan2(to.y, Vector2(to.x, to.z).length())
		camera.rotation = Vector3(lerp_angle(camera.rotation.x, pitch, minf(1.0, delta * 6.0)),
				lerp_angle(camera.rotation.y, yaw, minf(1.0, delta * 6.0)), 0.0)
	_viewmodel.visible = false
	_flash_light.light_energy = 0.0
