class_name ArmoredRig
extends CharacterRig
## Armoured soldier (default): the Quaternius Universal Animation Library
## mannequin (CC0) as a dark undersuit, plus armour plates generated here
## from the skeleton's rest pose (helmet with visor, chest, pauldrons,
## gauntlets, thigh/shin plates, boots, backpack) and skinned rigidly to
## their bones in one mesh (2 surfaces: armour in the player's colour, gold
## visor). Animation: an AnimationTree layers upper-body aiming (blended by
## look pitch) and a shoot one-shot over lower-body locomotion.

const SCENE := "res://art/characters/ual/UAL1_Standard.glb"
const UPPER_BONES := ["spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
		"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
const LOOPING := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump", "Pistol_Idle",
		"Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up"]
const MAX_LEG_TWIST := deg_to_rad(50.0)

static var _armor_cache: Dictionary = {}  ## "mesh"/"skin" built once per skeleton layout

var _model: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _armor_mat := StandardMaterial3D.new()
var _visor_mat := StandardMaterial3D.new()
var _body_mat := StandardMaterial3D.new()
var _hand: BoneAttachment3D
var _weapon_id: StringName = &""
var _weapon_node: Node3D
var _twist: float = 0.0
var _color := Color.WHITE
var _glow: float = 0.0
var _flash: float = 0.0
var _state_name: String = ""


func setup(color: Color) -> void:
	_color = color
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.rotation.y = PI  # faces +Z; Godot forward is -Z
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	# Undersuit: the mannequin, dark matte.
	_body_mat.albedo_color = Color(0.09, 0.1, 0.12)
	_body_mat.roughness = 0.8
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _body_mat
	# Armour in the player's colour (desaturated, metallic) and a gold visor.
	_armor_mat.albedo_color = Color.from_hsv(color.h, color.s * 0.55, clampf(color.v * 0.8, 0.35, 0.85))
	_armor_mat.metallic = 0.55
	_armor_mat.roughness = 0.35
	_armor_mat.emission_enabled = true
	_armor_mat.emission = Color.WHITE
	_armor_mat.emission_energy_multiplier = 0.0
	_visor_mat.albedo_color = Color(1.0, 0.72, 0.25)
	_visor_mat.metallic = 1.0
	_visor_mat.roughness = 0.12
	_visor_mat.emission_enabled = true
	_visor_mat.emission = Color(1.0, 0.6, 0.2)
	_visor_mat.emission_energy_multiplier = 0.6
	var armor := MeshInstance3D.new()
	var built := _armor()
	armor.mesh = built.mesh
	armor.skin = built.skin
	armor.set_surface_override_material(0, _armor_mat)
	armor.set_surface_override_material(1, _visor_mat)
	_skeleton.add_child(armor)
	armor.skeleton = NodePath("..")
	_hand = BoneAttachment3D.new()
	_hand.bone_name = "hand_r"
	_skeleton.add_child(_hand)
	_build_tree()


# --- Armour mesh ---

func _armor() -> Dictionary:
	if _armor_cache.has("mesh"):
		return _armor_cache
	var sk := _skeleton
	var pos := func(bone: String) -> Vector3:
		return sk.get_bone_global_rest(sk.find_bone(bone)).origin
	# Model forward from the feet (heel -> ball).
	var fwd: Vector3 = ((pos.call("ball_l") - pos.call("foot_l")) * Vector3(1, 0, 1)).normalized()
	var pieces := []  ## [bone, Transform3D (skeleton space), Mesh, surface]
	var limb := func(bone: String, from: String, to: String, width: float, depth: float, frac: float, along: float, push: float) -> void:
		var a: Vector3 = pos.call(from)
		var b: Vector3 = pos.call(to)
		var axis := (b - a).normalized()
		var side := axis.cross(fwd).normalized()
		var front := side.cross(axis).normalized()
		var length := a.distance_to(b)
		# Rounded plates: a capsule squashed to the plate's width and depth.
		var cap := CapsuleMesh.new()
		cap.radius = 0.5
		cap.height = maxf(length * frac / width, 1.05)
		cap.radial_segments = 10
		cap.rings = 3
		var basis := Basis(side, axis, front).scaled(Vector3(width, width, depth))
		var center := a.lerp(b, along) + front * push
		pieces.append([bone, Transform3D(basis, center), cap, 0])
	# Torso
	var chest_c: Vector3 = pos.call("spine_03") + Vector3(0, 0.06, 0)
	var chest := SphereMesh.new()
	chest.radial_segments = 14
	chest.rings = 7
	chest.radius = 0.5
	chest.height = 1.0
	pieces.append(["spine_03", Transform3D(Basis.looking_at(-fwd).scaled(Vector3(0.48, 0.36, 0.34)), chest_c + fwd * 0.035), chest, 0])
	var collar := BoxMesh.new()
	collar.size = Vector3(0.3, 0.06, 0.24)
	pieces.append(["spine_03", Transform3D(Basis.looking_at(-fwd), chest_c + Vector3(0, 0.17, 0)), collar, 0])
	var abs_box := BoxMesh.new()
	abs_box.size = Vector3(0.3, 0.16, 0.22)
	pieces.append(["spine_01", Transform3D(Basis.looking_at(-fwd), pos.call("spine_01") + fwd * 0.02), abs_box, 0])
	var belt := BoxMesh.new()
	belt.size = Vector3(0.36, 0.08, 0.25)
	pieces.append(["pelvis", Transform3D(Basis.looking_at(-fwd), pos.call("pelvis") + Vector3(0, 0.02, 0)), belt, 0])
	var pack := BoxMesh.new()
	pack.size = Vector3(0.28, 0.3, 0.09)
	pieces.append(["spine_03", Transform3D(Basis.looking_at(-fwd), chest_c - fwd * 0.17 - Vector3(0, 0.02, 0)), pack, 0])
	# Helmet: rounded shell and a wraparound visor.
	var head_c: Vector3 = pos.call("Head") + Vector3(0, 0.1, 0) + fwd * 0.015
	var helmet := SphereMesh.new()
	helmet.radius = 0.15
	helmet.height = 0.32
	helmet.radial_segments = 12
	helmet.rings = 6
	pieces.append(["Head", Transform3D(Basis.looking_at(-fwd).scaled(Vector3(1.0, 1.0, 1.1)), head_c), helmet, 0])
	var visor := SphereMesh.new()
	visor.radius = 0.5
	visor.height = 1.0
	visor.radial_segments = 12
	visor.rings = 6
	pieces.append(["Head", Transform3D(Basis.looking_at(-fwd).scaled(Vector3(0.25, 0.13, 0.16)), head_c + fwd * 0.1 + Vector3(0, 0.0, 0)), visor, 1])
	var jaw := BoxMesh.new()
	jaw.size = Vector3(0.17, 0.07, 0.1)
	pieces.append(["Head", Transform3D(Basis.looking_at(-fwd), head_c + fwd * 0.1 - Vector3(0, 0.08, 0)), jaw, 0])
	for s in ["l", "r"]:
		# Pauldrons sit over the shoulder joint.
		var sh: Vector3 = pos.call("upperarm_" + s)
		var pauldron := SphereMesh.new()
		pauldron.radius = 0.5
		pauldron.height = 1.0
		pauldron.radial_segments = 10
		pauldron.rings = 5
		pauldron.is_hemisphere = true
		pieces.append(["upperarm_" + s, Transform3D(Basis.looking_at(-fwd).scaled(Vector3(0.22, 0.2, 0.24)), sh + Vector3(0, 0.02, 0)), pauldron, 0])
		limb.call("upperarm_" + s, "upperarm_" + s, "lowerarm_" + s, 0.1, 0.1, 0.6, 0.55, 0.0)
		limb.call("lowerarm_" + s, "lowerarm_" + s, "hand_" + s, 0.11, 0.11, 0.7, 0.55, 0.0)
		limb.call("thigh_" + s, "thigh_" + s, "calf_" + s, 0.17, 0.17, 0.7, 0.45, 0.02)
		limb.call("calf_" + s, "calf_" + s, "foot_" + s, 0.13, 0.13, 0.62, 0.5, 0.025)
		var foot: Vector3 = pos.call("foot_" + s)
		var boot := BoxMesh.new()
		boot.size = Vector3(0.13, 0.11, 0.27)
		pieces.append(["foot_" + s, Transform3D(Basis.looking_at(-fwd), Vector3(foot.x, 0.06, foot.z) + fwd * 0.06), boot, 0])
	# One mesh, rigid weights: each piece follows its bone.
	var skin := Skin.new()
	var bind_of := {}
	var surfaces := [SurfaceTool.new(), SurfaceTool.new()]
	for st: SurfaceTool in surfaces:
		st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in pieces:
		var bone: String = p[0]
		if not bind_of.has(bone):
			bind_of[bone] = skin.get_bind_count()
			skin.add_named_bind(bone, sk.get_bone_global_rest(sk.find_bone(bone)).affine_inverse())
		var arrays: Array = (p[2] as PrimitiveMesh).get_mesh_arrays()
		var xf: Transform3D = p[1]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var st: SurfaceTool = surfaces[p[3]]
		for idx in indices:
			st.set_normal((xf.basis * normals[idx]).normalized())
			st.set_bones(PackedInt32Array([bind_of[bone], 0, 0, 0]))
			st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
			st.add_vertex(xf * verts[idx])
	var mesh := ArrayMesh.new()
	for st: SurfaceTool in surfaces:
		st.index()
		st.commit(mesh)
	_armor_cache = {"mesh": mesh, "skin": skin}
	return _armor_cache


# --- Animation ---

func _build_tree() -> void:
	var player: AnimationPlayer = _model.find_children("*", "AnimationPlayer", true, false)[0]
	for clip: String in LOOPING:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	for pt in [["Idle", 0.0], ["Walk", 1.8], ["Jog_Fwd", 4.6], ["Sprint", 7.5]]:
		loco.add_blend_point(_clip(pt[0]), pt[1], -1, pt[0])
	loco.min_space = 0.0
	loco.max_space = 8.0
	bt.add_node("loco", loco)
	var loco_ts := AnimationNodeTimeScale.new()
	bt.add_node("loco_ts", loco_ts)
	bt.connect_node("loco_ts", 0, "loco")
	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.add_blend_point(_clip("Crouch_Idle"), 0.0, -1, "idle")
	crouch.add_blend_point(_clip("Crouch_Fwd"), 2.5, -1, "fwd")
	crouch.max_space = 3.0
	bt.add_node("crouch", crouch)
	bt.add_node("air", _clip("Jump"))
	var state := AnimationNodeTransition.new()
	state.input_count = 3
	state.set_input_name(0, "ground")
	state.set_input_name(1, "crouch")
	state.set_input_name(2, "air")
	state.xfade_time = 0.15
	bt.add_node("state", state)
	bt.connect_node("state", 0, "loco_ts")
	bt.connect_node("state", 1, "crouch")
	bt.connect_node("state", 2, "air")
	var aim := AnimationNodeBlendSpace1D.new()
	aim.add_blend_point(_clip("Pistol_Aim_Down"), -1.0, -1, "down")
	aim.add_blend_point(_clip("Pistol_Aim_Neutral"), 0.0, -1, "neutral")
	aim.add_blend_point(_clip("Pistol_Aim_Up"), 1.0, -1, "up")
	bt.add_node("aim", aim)
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	var shoot := AnimationNodeOneShot.new()
	shoot.filter_enabled = true
	shoot.fadein_time = 0.03
	shoot.fadeout_time = 0.12
	var skel_path := String(_model.get_path_to(_skeleton))
	for b: String in UPPER_BONES:
		upper.set_filter_path(NodePath(skel_path + ":" + b), true)
		shoot.set_filter_path(NodePath(skel_path + ":" + b), true)
	bt.add_node("upper", upper)
	bt.connect_node("upper", 0, "state")
	bt.connect_node("upper", 1, "aim")
	bt.add_node("shoot", shoot)
	bt.add_node("shoot_clip", _clip("Pistol_Shoot"))
	bt.connect_node("shoot", 0, "upper")
	bt.connect_node("shoot", 1, "shoot_clip")
	bt.connect_node("output", 0, "shoot")
	_tree = AnimationTree.new()
	_tree.tree_root = bt
	_model.add_child(_tree)
	_tree.root_node = NodePath("..")
	_tree.anim_player = _tree.get_path_to(player)
	_tree.set("parameters/upper/blend_amount", 1.0)
	_tree.active = true


static func _clip(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


func animate(state: PlayerSimState, delta: float, _height: float) -> void:
	var flat := Vector3(state.velocity.x, 0.0, state.velocity.z)
	var speed := flat.length()
	var local := flat.rotated(Vector3.UP, -state.yaw)
	var backwards := -local.z < -0.1 and speed > 0.6
	var target := "ground"
	if state.move_state == PlayerSimState.Move.AIR:
		target = "air"
	elif state.stance != PlayerSimState.Stance.STAND:
		target = "crouch"
	if target != _state_name:
		_state_name = target
		_tree.set("parameters/state/transition_request", target)
	_tree.set("parameters/loco/blend_position", speed)
	_tree.set("parameters/loco_ts/scale", -1.0 if backwards else 1.0)
	_tree.set("parameters/crouch/blend_position", speed)
	_tree.set("parameters/aim/blend_position", clampf(state.pitch / 1.2, -1.0, 1.0))
	var twist := 0.0
	if speed > 0.6:
		twist = clampf(atan2(-local.x, absf(local.z) + 0.001) * (-1.0 if backwards else 1.0), -MAX_LEG_TWIST, MAX_LEG_TWIST)
	_twist = lerp_angle(_twist, twist, minf(delta * 10.0, 1.0))
	_model.rotation.y = PI + _twist
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 8.0, 0.0)
		_apply_emission()


## Fire: the upper body plays a recoil.
func on_fire() -> void:
	_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


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
	# Grip in the right hand, barrel along the hand's forward.
	w.scale = Vector3.ONE * 2.6
	w.rotation = Vector3(0.0, PI * 0.5, PI * 0.5)
	w.position = Vector3(0.0, 0.08, 0.03)
	_hand.add_child(w)
	_weapon_node = w


func set_glow(amount: float) -> void:
	if not is_equal_approx(amount, _glow):
		_glow = amount
		_apply_emission()


func flash(amount: float) -> void:
	_flash = maxf(_flash, amount)
	_apply_emission()


func _apply_emission() -> void:
	_armor_mat.emission = _color.lerp(Color.WHITE, 0.5) if _flash <= 0.0 else Color.WHITE
	_armor_mat.emission_energy_multiplier = _glow * 0.8 + _flash * 1.6
