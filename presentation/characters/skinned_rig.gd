class_name SkinnedRig
extends CharacterRig
## One skinned CC0 character (Kenney Animated Characters 3): a single mesh
## and material, so 1 draw per character (plus its shadow), animated by an
## AnimationPlayer from the pack's idle / run / jump clips.

const MODEL := preload("res://art/characters/kenney/characterMedium.fbx")
## Armour suit painted over the pack's UV layout (tools/gen_suit.py); the
## emission mask glows in the player's colour.
const SKIN := preload("res://art/characters/kenney/suit.png")
const GLOW_MASK := preload("res://art/characters/kenney/suit_emission.png")
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

static var _library: AnimationLibrary

var _model: Node3D
var _anim: AnimationPlayer
var _material := StandardMaterial3D.new()
var _twist: float = 0.0


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
	_model = MODEL.instantiate()
	_model.scale = Vector3.ONE * (1.8 / MODEL_HEIGHT)
	_model.rotation.y = PI  # the model faces +Z; Godot forward is -Z
	add_child(_model)
	_material.albedo_texture = SKIN
	_material.albedo_color = Color.WHITE.lerp(color, 0.12)
	_material.roughness = 0.55
	_material.metallic = 0.2
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_texture = GLOW_MASK
	_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	_material.emission_energy_multiplier = GLOW_ENERGY
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D"):
		mi.material_override = _material
	_anim = AnimationPlayer.new()
	_model.add_child(_anim)
	_anim.root_node = NodePath("..")
	_anim.add_animation_library("", library())
	_anim.play("idle")


func animate(state: PlayerSimState, delta: float, height: float) -> void:
	_model.scale.y = (1.8 / MODEL_HEIGHT) * height / 1.8
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


func set_glow(amount: float) -> void:
	_material.emission_energy_multiplier = GLOW_ENERGY + amount * 4.0
