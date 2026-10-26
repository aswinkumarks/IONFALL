class_name SkinnedRig
extends CharacterRig
## One skinned CC0 character (Kenney Animated Characters 3): a single mesh
## and material, so 1 draw per character (plus its shadow), animated by an
## AnimationPlayer from the pack's idle / run / jump clips. The pack has no
## weapon clips, so the weapon rides on a pivot in front of the chest (pitched
## with the look) and two-bone IK puts both hands on it after the clip.

## Loaded when one is built (not preloaded): exports leave out this art, as
## no player can pick this rig any more (CharacterRig.SELECTABLE).
const MODEL := "res://art/characters/kenney/characterMedium.fbx"
## Armour suit painted over the pack's UV layout (tools/gen_suit.py); the
## emission mask glows in the player's colour.
const SKIN := "res://art/characters/kenney/suit.png"
const GLOW_MASK := "res://art/characters/kenney/suit_emission.png"
const GLOW_ENERGY := 3.5
const CLIPS := {
	"idle": ["res://art/characters/kenney/idle.fbx", "Root|Idle", true],
	"run": ["res://art/characters/kenney/run.fbx", "Root|Run", true],
	"jump": ["res://art/characters/kenney/jump.fbx", "Root|Jump", false],
}
const MODEL_HEIGHT := 3.765  ## bind-pose height of characterMedium in its own units
const RUN_ANIM_SPEED := 5.0  ## m/s at which the run clip plays at 1x
const BLEND := 0.15
const MAX_LEG_TWIST := deg_to_rad(50.0)
## Weapon pivot in the rig's space (metres; forward is -Z) and how much of
## the look pitch it follows.
const WEAPON_AT := Vector3(0.14, 1.02, -0.34)
const WEAPON_SCALE := 1.5  ## the stylised body has big hands and head
const WEAPON_PITCH := 0.7
const SUPPORT_REACH := 0.22  ## left hand: this far along the barrel from the grip
const ARMS := [["RightArm", "RightForeArm", "RightHand"], ["LeftArm", "LeftForeArm", "LeftHand"]]
## Elbow directions in skeleton space (the model faces +Z; its right is -X).
const POLES := [Vector3(-0.6, -1.0, -0.3), Vector3(0.6, -1.0, -0.3)]


## Runs the arm IK after the animation has posed the skeleton.
class ArmIK extends SkeletonModifier3D:
	var apply: Callable

	func _process_modification_with_delta(_delta: float) -> void:
		apply.call()

static var _library: AnimationLibrary

var _model: Node3D
var _anim: AnimationPlayer
var _material := StandardMaterial3D.new()
var _twist: float = 0.0
var _color := Color.WHITE
var _glow: float = 0.0
var _flash: float = 0.0
var _skeleton: Skeleton3D
var _pivot := Node3D.new()
var _weapon_node: Node3D
var _weapon_id: StringName = &""
var _pitch: float = 0.0


static func library() -> AnimationLibrary:
	if _library == null:
		_library = AnimationLibrary.new()
		for clip: String in CLIPS:
			var src: Node = load(CLIPS[clip][0]).instantiate()
			var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer")[0]
			var a: Animation = ap.get_animation(CLIPS[clip][1]).duplicate()
			a.loop_mode = Animation.LOOP_LINEAR if CLIPS[clip][2] else Animation.LOOP_NONE
			_library.add_animation(clip, a)
			src.free()
	return _library


func setup(color: Color) -> void:
	_model = (load(MODEL) as PackedScene).instantiate()
	_model.scale = Vector3.ONE * (1.8 / MODEL_HEIGHT)
	_model.rotation.y = PI  # the model faces +Z; Godot forward is -Z
	add_child(_model)
	_material.albedo_texture = load(SKIN)
	_material.albedo_color = Color.WHITE.lerp(color, 0.12)
	_material.roughness = 0.55
	_material.metallic = 0.2
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_material.emission_enabled = true
	_color = color
	_material.emission = color
	_material.emission_texture = load(GLOW_MASK)
	_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	_material.emission_energy_multiplier = GLOW_ENERGY
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D"):
		mi.material_override = _material
	_anim = AnimationPlayer.new()
	_model.add_child(_anim)
	_anim.root_node = NodePath("..")
	_anim.add_animation_library("", library())
	_anim.play("idle")
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	var ik := ArmIK.new()
	ik.apply = _pose_arms
	_skeleton.add_child(ik)
	_pivot.position = WEAPON_AT
	_pivot.scale = Vector3.ONE * WEAPON_SCALE
	add_child(_pivot)


func set_weapon(id: StringName) -> void:
	if id == _weapon_id:
		return
	_weapon_id = id
	if _weapon_node != null:
		_weapon_node.queue_free()
		_weapon_node = null
	var w := WeaponModels.instantiate(id)
	if w == null:
		return
	_pivot.add_child(w)
	# Hold the weapon by its handle.
	w.position = -(w.get_node("Grip") as Node3D).position
	_weapon_node = w


func muzzle_position() -> Vector3:
	var m: Node3D = _weapon_node.get_node_or_null("Muzzle") if _weapon_node != null else null
	return m.global_position if m != null else Vector3.INF


## Right hand on the handle, left hand along the barrel (skeleton space).
func _pose_arms() -> void:
	if _weapon_node == null:
		return
	var to_skel := _skeleton.global_transform.affine_inverse()
	var grip := (_weapon_node.get_node("Grip") as Node3D).global_position
	var forward := -_pivot.global_basis.z
	reach(_skeleton, ARMS[0], to_skel * grip, POLES[0])
	reach(_skeleton, ARMS[1], to_skel * (grip + forward * SUPPORT_REACH + _pivot.global_basis.y * 0.03), POLES[1])


func animate(state: PlayerSimState, delta: float, height: float) -> void:
	_model.scale.y = (1.8 / MODEL_HEIGHT) * height / 1.8
	_pitch = lerpf(_pitch, state.pitch * WEAPON_PITCH, minf(delta * 15.0, 1.0))
	_pivot.position = Vector3(WEAPON_AT.x, WEAPON_AT.y * height / 1.8, WEAPON_AT.z)
	_pivot.rotation.x = _pitch
	var flat := Vector3(state.velocity.x, 0.0, state.velocity.z)
	var speed := flat.length()
	var clip := "idle"
	var rate := 1.0
	var twist := 0.0
	if state.move_state == PlayerSimState.Move.AIR:
		clip = "jump"
	elif speed > 0.6:
		clip = "run"
		# Face the legs along the movement; run the clip backwards when
		# moving backwards (the pack has no strafe or backpedal clips).
		var local := flat.rotated(Vector3.UP, -state.yaw)
		var forward := -local.z
		rate = speed / RUN_ANIM_SPEED * (1.0 if forward >= -0.1 else -1.0)
		twist = clampf(atan2(-local.x, absf(local.z) + 0.001) * signf(rate), -MAX_LEG_TWIST, MAX_LEG_TWIST)
	_twist = lerp_angle(_twist, twist, minf(delta * 10.0, 1.0))
	_model.rotation.y = PI + _twist
	if _anim.current_animation != clip:
		_anim.play(clip, BLEND)
	_anim.speed_scale = rate
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 8.0, 0.0)
		_apply_emission()


func set_glow(amount: float) -> void:
	_glow = amount
	_apply_emission()


func flash(amount: float) -> void:
	_flash = maxf(_flash, amount)
	_apply_emission()


## The hit flash switches emission to the whole body (multiply op on a
## white mask would need a second texture), so it lightens the albedo instead.
func _apply_emission() -> void:
	_material.emission_energy_multiplier = GLOW_ENERGY + _glow * 4.0 + _flash * 6.0
	_material.albedo_color = Color.WHITE.lerp(_color, 0.12).lerp(Color(3, 3, 3), _flash * 0.5)
