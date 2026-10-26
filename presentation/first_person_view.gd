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
## the left shoulder forward so the support arm comes up from below and
## reaches the fore-end.
const STANCE_YAW := -1.05
## The arms sit this far ahead of and below where the head bone puts them
## (camera space): the left hand then reaches the fore-end of the larger
## weapons, while the left elbow stays below the screen's edge (further
## forward, the arm's cut-off end showed beside it).
const ARMS_FORWARD := Vector3(0.0, -0.06, -0.05)
## First-person weapons are drawn this much larger than their hip offsets
## were tuned for: beside the (smaller, ArmoredRig.FP_HAND_SCALE) hands a
## life-size weapon looked like a toy.
const WEAPON_SCALE := 1.75
## The weapon and its hip offset are both scaled by this about the eye: the
## same picture, but near enough for life-size arms to hold it with both hands.
const VIEW_DEPTH := 0.85
## Melee bash and grenade throw motions (seconds).
## Seconds to scope fully in or out.
const SCOPE_TIME := 0.14
const MELEE_TIME := 0.36
const THROW_TIME := 0.45

## Where the viewer stands (last update_view), or INF while dead: for its
## blob shadow (BlobShadows).
var feet_position := Vector3.INF
var camera := Camera3D.new()
var _viewmodel := Node3D.new()  ## pose root, animated every frame
var _models: Dictionary = {}  ## weapon id -> Node3D
var _arms: CharacterRig
var _arms_rest := Vector3.ZERO  ## the arms rig's position under the camera at rest
var _bash := 0.0  ## this frame's melee bash amount (_melee_curve)
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
var _melee_struck: bool = false  ## this bash's strike (camera punch) has played
var _punch: float = 0.0  ## camera punch from a melee strike or hit, decays fast
var _throw_t: float = 0.0  ## time left in the throw dip
## 0 = hip, 1 = fully scoped; eases with SCOPE_TIME.
var scope_amount: float = 0.0
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
func set_character(style: String, color: Color, fallback: String = CharacterRig.SELECTABLE[0]) -> void:
	if _arms != null:
		_arms.queue_free()
		_arms = null
	for s: String in [style, fallback]:
		var rig := CharacterRig.create(s)
		camera.add_child(rig)
		rig.setup(color)
		if rig.make_first_person():
			RenderLayers.mark_dynamic(rig)
			_arms = rig
			_arms.rotation.y = STANCE_YAW
			_arms.position = -EYE_FROM_HEAD - _arms.basis * rig.head_position() + ARMS_FORWARD
			_arms_rest = _arms.position
			return
		rig.free()


## Our melee: the weapon jabs forward and across.
func melee() -> void:
	_melee_t = MELEE_TIME
	_melee_struck = false


func meleeing() -> bool:
	return _melee_t > 0.0


## Our melee connected: a heavier jolt.
func melee_impact() -> void:
	_punch = maxf(_punch, 1.0)


## The bash over its time `u` (0 → 1): a short wind-up back, a fast strike
## forward and across, a moment held, then the recovery.
static func _melee_curve(u: float) -> float:
	if u <= 0.0 or u >= 1.0:
		return 0.0
	if u < 0.18:
		return -0.35 * sin(PI * 0.5 * u / 0.18)
	if u < 0.34:
		var k := (u - 0.18) / 0.16
		return lerpf(-0.35, 1.0, 1.0 - pow(1.0 - k, 3.0))  # ease-out snap
	if u < 0.5:
		return 1.0
	return 0.5 + 0.5 * cos(PI * (u - 0.5) / 0.5)


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
		m.scale = Vector3.ONE * WEAPON_SCALE * VIEW_DEPTH
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
	feet_position = feet if s.alive else Vector3.INF
	# After a long frame (a hitch, the app resuming) the springs below would
	# overshoot and blow up: step them at most 0.1 s at a time.
	delta = minf(delta, 0.1)
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
	camera.rotation = Vector3(pitch + _cam_dip, yaw, sin(_bob_phase) * 0.004 * _bob_amount * shake)
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
	var hip := WeaponModels.hip_offset(_current_id) * VIEW_DEPTH
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
	var u := 1.0 - _melee_t / MELEE_TIME if _melee_t > 0.0 else 0.0
	var bash := _melee_curve(u)
	_bash = bash
	if _melee_t > 0.0 and not _melee_struck and u >= 0.26:
		_melee_struck = true
		_punch = maxf(_punch, 0.45)
	_punch = move_toward(_punch, 0.0, delta * 5.0)
	var dip := sin(PI * _throw_t / THROW_TIME) if _throw_t > 0.0 else 0.0
	pos += Vector3(-0.11, 0.05, -0.22) * bash + Vector3(0.04, -0.22, 0.06) * dip
	_viewmodel.position = pos
	_viewmodel.rotation = Vector3(
		_recoil * 0.12 - _pose.x * 0.35 - _pose.z * 0.5 + _sway.y * 0.15 - dip * 0.6 - bash * 0.22,
		_sway.x * 0.2 + _pose.x * 0.6 + bash * 0.7,
		_recoil_roll + _pose.y * 0.25 + _pose.z * 0.4 - _sway.x * 0.1 - bash * 0.35)
	# Melee punch: the view jolts down and in a touch, the FOV pinches.
	var p := _punch * _punch * shake
	camera.rotation.x -= 0.035 * p
	camera.rotation.z += 0.02 * p
	camera.fov -= 4.0 * p

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
			# The shoulders drive the bash too, so the hands keep hold of the
			# weapon at the far end of the strike (it outreaches the arms).
			_arms.position = _arms_rest + Vector3(-0.07, 0.04, -0.15) * maxf(_bash, 0.0)
			var weapon_node: Node3D = _models[_current_id]
			var to_rig := _arms.global_transform.affine_inverse()
			var handle := (weapon_node.get_node("Grip") as Node3D).global_position
			var support := (weapon_node.get_node("Support") as Node3D).global_position
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
