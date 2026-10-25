class_name AstronautRig
extends CharacterRig
## Quaternius Ultimate Space Kit astronauts (CC0): one skinned mesh each,
## gun-ready animations (Idle_Gun / Walk_Gun / Run_Gun, Jump_Idle, Duck).
## Four variants; the player's current weapon model sits in the right hand
## instead of the pack's pistol.

const DIR := "res://art/characters/quaternius/"
const VARIANTS := ["Astronaut_FinnTheFrog", "Astronaut_RaeTheRedPanda", "Astronaut_BarbaraTheBee",
		"Astronaut_FernandoTheFlamingo"]
const MODEL_HEIGHT := 2.69  ## bind-pose height in the model's units
const RUN_ANIM_SPEED := 5.5  ## m/s at which Run_Gun plays at 1x
const WALK_ANIM_SPEED := 2.4
const BLEND := 0.15
const MAX_LEG_TWIST := deg_to_rad(50.0)
const LOOPING := ["Idle_Gun", "Walk_Gun", "Run_Gun", "Jump_Idle", "Duck"]

var variant: int = 0

var _model: Node3D
var _anim: AnimationPlayer
var _materials: Array[StandardMaterial3D] = []
var _hand: BoneAttachment3D
var _weapon_id: StringName = &""
var _weapon_node: Node3D
var _twist: float = 0.0
var _glow: float = 0.0
var _flash: float = 0.0
var _color := Color.WHITE


func setup(color: Color) -> void:
	_color = color
	var scene: PackedScene = load(DIR + VARIANTS[posmod(variant, VARIANTS.size())] + ".gltf")
	_model = scene.instantiate()
	_model.scale = Vector3.ONE * (1.8 / MODEL_HEIGHT)
	_model.rotation.y = PI  # glTF faces +Z; Godot forward is -Z
	add_child(_model)
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mi.get_parent() is BoneAttachment3D:
			_hand = mi.get_parent()
			mi.visible = false  # the pack's pistol; we show our own weapon
			continue
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i) as StandardMaterial3D
			if base == null:
				continue
			var m := base.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			m.emission = Color.WHITE
			m.emission_energy_multiplier = 0.0
			mi.set_surface_override_material(i, m)
			_materials.append(m)
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	for clip: String in LOOPING:
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play("Idle_Gun")


## Shows `id`'s weapon model in the right hand.
func muzzle_position() -> Vector3:
	var m: Node3D = _weapon_node.get_node_or_null("Muzzle") if _weapon_node != null else null
	return m.global_position if m != null else Vector3.INF


func set_weapon(id: StringName) -> void:
	if id == _weapon_id or _hand == null:
		return
	_weapon_id = id
	if _weapon_node != null:
		_weapon_node.queue_free()
		_weapon_node = null
	var w := WeaponModels.instantiate(id)
	if w == null:
		return
	# The hand bone's space is in model units; undo the model scale and
	# point the barrel along the hand's grip like the pack's pistol.
	var pistol: Node3D = null
	for c in _hand.get_children():
		if c is MeshInstance3D:
			pistol = c
	w.scale = Vector3.ONE * (MODEL_HEIGHT / 1.8) * 2.4
	if pistol != null:
		w.transform.basis = pistol.transform.basis.orthonormalized() * Basis(Vector3.UP, PI) * Basis.from_scale(w.scale)
		w.position = pistol.position
	w.position += w.basis * WeaponModels.grip_shift(w)
	_hand.add_child(w)
	_weapon_node = w


func animate(state: PlayerSimState, delta: float, height: float) -> void:
	var flat := Vector3(state.velocity.x, 0.0, state.velocity.z)
	var speed := flat.length()
	var clip := "Idle_Gun"
	var rate := 1.0
	var twist := 0.0
	var crouched := state.stance != PlayerSimState.Stance.STAND
	if state.move_state == PlayerSimState.Move.AIR:
		clip = "Jump_Idle"
	elif crouched and speed < 0.6:
		clip = "Duck"
	elif speed > 0.6:
		clip = "Run_Gun" if speed > 3.2 else "Walk_Gun"
		var local := flat.rotated(Vector3.UP, -state.yaw)
		var forward := -local.z
		rate = speed / (RUN_ANIM_SPEED if clip == "Run_Gun" else WALK_ANIM_SPEED) * (1.0 if forward >= -0.1 else -1.0)
		twist = clampf(atan2(-local.x, absf(local.z) + 0.001) * signf(rate), -MAX_LEG_TWIST, MAX_LEG_TWIST)
	_twist = lerp_angle(_twist, twist, minf(delta * 10.0, 1.0))
	_model.rotation.y = PI + _twist
	# Crouch while moving: lower the whole body a little.
	_model.position.y = -0.25 * (1.8 - height) / 0.6 if crouched and clip != "Duck" else 0.0
	if _anim.current_animation != clip:
		_anim.play(clip, BLEND)
	_anim.speed_scale = rate
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 8.0, 0.0)
		_apply_emission()


func set_glow(amount: float) -> void:
	if not is_equal_approx(amount, _glow):
		_glow = amount
		_apply_emission()


func flash(amount: float) -> void:
	_flash = maxf(_flash, amount)
	_apply_emission()


func _apply_emission() -> void:
	for m in _materials:
		m.emission = Color.WHITE.lerp(_color, 0.6 if _flash <= 0.0 else 0.0)
		m.emission_energy_multiplier = _glow * 0.6 + _flash * 1.5
