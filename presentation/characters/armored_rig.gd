@tool
class_name ArmoredRig
extends CharacterRig
## Armoured soldier (default): the Quaternius Universal Base Characters
## "Superhero" body (CC0) as a dark undersuit, animated with the Universal
## Animation Library clips (CC0, same skeleton; rotations retargeted, pelvis
## height scaled), plus armour plates generated here
## from the skeleton's rest pose (helmet with visor, chest, pauldrons,
## gauntlets, thigh/shin plates, boots, backpack) and skinned rigidly to
## their bones in one mesh (2 surfaces: armour in the player's colour, gold
## visor). Animation: an AnimationTree layers upper-body aiming (blended by
## look pitch) and a shoot one-shot over lower-body locomotion.

const SCENE := "res://art/characters/ubc/Superhero_Male_FullBody.gltf"
const ANIM_SOURCE := "res://art/characters/ual/UAL1_Standard.glb"
const CLIPS := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump", "Pistol_Aim_Down",
		"Pistol_Aim_Neutral", "Pistol_Aim_Up", "Pistol_Shoot"]
const UPPER_BONES := ["spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
		"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
const LOOPING := ["Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd", "Jump", "Pistol_Idle",
		"Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up"]
const MAX_LEG_TWIST := deg_to_rad(35.0)
## The weapon in the right hand (hand-bone space).
const GRIP_EULER := Vector3(0.0, PI * 0.5, PI * 0.5)
const GRIP_OFFSET := Vector3(0.0, 0.08, 0.03)
const GRIP_SCALE := 2.6
## How much of the look pitch the head follows (the rest is the aim pose's
## arms and spine).
const HEAD_PITCH := 0.6
## Third person: the weapon is shouldered, its handle this far from the
## right shoulder (look-direction axes: right, up, forward is -Z); the arms
## reach for it (HoldWeapon), the left hand to the model's Support marker.
## A little right of and below the shoulder, the weapon in front of the
## chest rather than out at the side (from the front, the left hand hid
## behind the right); far enough out that the right forearm and hand clear
## the bulkier chests (checked against the meshes in Blender).
const SHOULDER_TO_HANDLE := Vector3(0.1, -0.13, -0.48)
## Third person: the right elbow points out to the side, a little down and
## forward (skeleton space: the body faces +Z, its right is -X), as when
## shouldering a rifle; down and back, it folded the forearm into the torso.
const TP_RIGHT_ELBOW := Vector3(-1.0, -0.6, 0.5)
## Third person: the left elbow points out to the left and a little down
## and forward, keeping the forearm off the chest as it reaches across for
## the fore-end; down and back, it lay along the Sentinel's chest plate.
const TP_LEFT_ELBOW := Vector3(1.0, -0.4, 0.2)
## Holding a weapon the chest turns this far to the right (a bladed stance),
## bringing the left shoulder forward so the left hand reaches the fore-end.
const BLADE := deg_to_rad(40.0)
## A long gun comes back towards the shoulder at most this far (metres) for
## the left hand to reach its fore-end (_pull_back). Held this close in, the
## left hand reaches without; brought back, the right hand went into the
## bulkier chests. The slim characters still bring it back a little
## (_max_pull_back).
const MAX_PULL_BACK := 0.0
## Weapons held otherwise than shouldered: id -> [handle from the right
## shoulder (as SHOULDER_TO_HANDLE), chest turn]. The pistol is pushed out
## in front, both hands on it, the chest squarer.
const HOLDS := {&"mag_pistol": [Vector3(0.14, -0.04, -0.57), deg_to_rad(30.0)]}
## Hand on the handle (_fp_hand): how far the fingers point down from the
## barrel and in across it (tan of the angles), and where the hand's palm
## centre goes relative to the handle (metres, weapon axes: right, up,
## back). Nearly level and turned in, the fingers wrap the grip's front
## below the trigger while the wrist sits low and out to the right; pointing
## down from the grip's middle, they put the wrist up in the receiver (and
## a bullpup's magazine). Slightly left of, below and behind the handle's
## middle: the knuckles close round a slim grip.
const FP_FINGER_DROP := 0.2
const FP_FINGER_IN := 0.3
const FP_PALM_AT := Vector3(-0.015, -0.005, 0.01)
## The left hand on the fore-end (weapon axes): fingers forward and across
## to the right, palm against its left side. (Palm up would roll the forearm
## half a turn from the rest pose and wring the elbow.)
const SUPPORT_FINGERS := Vector3(0.6, 0.0, -1.0)
const SUPPORT_PALM := Vector3(1.0, -0.3, 0.0)
## The most a forearm rolls about its own axis (radians); the wrist takes
## the rest. The forearm turns whole from the elbow, so more twists the
## elbow's skin.
const MAX_FOREARM_TWIST := deg_to_rad(90.0)
## The support hand reaches at most this much of its arm's length; past it,
## it holds the weapon further back towards the handle (_within_reach)
## rather than stretching into the air in front of it.
const SUPPORT_REACH := 0.96
## First person: the top of each upper arm (this fraction, from the
## shoulder) is cut away with the body, so the stance never shows its edge.
const FP_SHOULDER_CUT := 0.4
## First person: the hands (and their fingers) are drawn this much smaller
## (_fp_hand_scale). Life-size gloves this near the eye dwarfed the weapon,
## and their fingers stood out round it.
const FP_HAND_SCALE := 0.75
## First person: the left hand cradles the fore-end from below (weapon
## axes): fingers forward and a little across, palm up and towards it, so
## from the eye the weapon hides it. Held against its side as in third
## person, the hand stood out beside the weapon.
const FP_SUPPORT_FINGERS := Vector3(0.3, 0.0, -1.0)
const FP_SUPPORT_PALM := Vector3(0.8, 0.6, 0.0)

static var _armor_cache: Dictionary = {}  ## "mesh"/"skin" built once per skeleton layout
static var _library: AnimationLibrary
static var _arms_cache: Dictionary = {}  ## source mesh instance id -> arms-only mesh

var _model: Node3D
var _skeleton: Skeleton3D
var _tree: AnimationTree
var _armor_mat := StandardMaterial3D.new()
var _visor_mat := StandardMaterial3D.new()
var _body_mat := StandardMaterial3D.new()
var _weapon_id: StringName = &""
var _weapon_node: Node3D
var _hand_scale := 1.0  ## _fp_hand_scale() once first person
var _twist: float = 0.0
var _color := Color.WHITE
var _glow: float = 0.0
var _flash: float = 0.0
var _state_name: String = ""
var _look_pitch: float = 0.0
## The held weapon's transform in this rig's space, set by _hold_weapon.
var _weapon_local := Transform3D()
## The aim blend's upper end: 1 uses the aim-up clip fully.
var _aim_up: float = 1.0
## The held weapon's Grip and Support markers (its own space).
var _grip_at := Vector3.ZERO
var _support_at := Vector3.ZERO
## Looked up once (_cache_bones), not by name every frame: the chest, its
## parent, the head, its parent, and per arm (right first) [upper arm,
## forearm, hand, upper arm's parent].
var _b_chest := -1
var _b_chest_parent := -1
var _b_spine := PackedInt32Array()  ## the chest and the two spine bones below it, lowest first
var _b_head := -1
var _b_head_parent := -1
var _head_rest := Basis()
var _arms: Array[PackedInt32Array] = []
## Per arm, skeleton space: [upper arm rest, forearm rest, hand rest] global
## rests, the shoulder's offset from its parent, and the two bone lengths.
var _arm_rests: Array = []
## Animation detail (set_detail): the arms' IK, the bladed stance and the
## head levelling run only when `_ik`; the tree advances every `_anim_every`
## frames (0: never), `_anim_phase` frames apart from other characters.
var _ik := true
var _anim_every := 1
var _anim_phase := 0
var _anim_dt := 0.0
var _hold: HoldWeapon


## Third person, after the clips: the arms hold the weapon rather than
## following the clips, whose two-handed pistol pose clasped both hands
## behind a rifle's grip; then the head is levelled (_level_head). One
## modifier, not two: each active one costs the skeleton a pass.
class HoldWeapon extends SkeletonModifier3D:
	var rig: ArmoredRig

	func _process_modification_with_delta(_delta: float) -> void:
		rig._hold_weapon()
		rig._level_head()


func setup(color: Color) -> void:
	_color = color
	_model = (load(SCENE) as PackedScene).instantiate()
	_model.rotation.y = PI  # faces +Z; Godot forward is -Z
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	# Undersuit: the body, dark matte; face details sit under the helmet.
	_body_mat.albedo_color = Color(0.08, 0.09, 0.11)
	_body_mat.roughness = 0.75
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mi.name in ["Eyes", "Eyebrows"]:
			mi.visible = false
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
	_build_tree(_retargeted(_skeleton), UPPER_BONES)


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
	pieces.append(["spine_03", Transform3D(Basis.looking_at(-fwd).scaled(Vector3(0.54, 0.4, 0.38)), chest_c + fwd * 0.04), chest, 0])
	var collar := BoxMesh.new()
	collar.size = Vector3(0.34, 0.07, 0.27)
	pieces.append(["spine_03", Transform3D(Basis.looking_at(-fwd), chest_c + Vector3(0, 0.17, 0)), collar, 0])
	var abs_shell := SphereMesh.new()
	abs_shell.radius = 0.5
	abs_shell.height = 1.0
	abs_shell.radial_segments = 12
	abs_shell.rings = 6
	pieces.append(["spine_01", Transform3D(Basis.looking_at(-fwd).scaled(Vector3(0.36, 0.22, 0.28)), pos.call("spine_01") + fwd * 0.02), abs_shell, 0])
	var belt := CylinderMesh.new()
	belt.top_radius = 0.5
	belt.bottom_radius = 0.5
	belt.height = 1.0
	belt.radial_segments = 14
	belt.rings = 1
	pieces.append(["pelvis", Transform3D(Basis.looking_at(-fwd).scaled(Vector3(0.38, 0.08, 0.29)), pos.call("pelvis") + Vector3(0, 0.03, 0)), belt, 0])
	var cod := BoxMesh.new()
	cod.size = Vector3(0.12, 0.12, 0.06)
	pieces.append(["pelvis", Transform3D(Basis.looking_at(-fwd), pos.call("pelvis") + fwd * 0.12 - Vector3(0, 0.05, 0)), cod, 0])
	var pack := BoxMesh.new()
	pack.size = Vector3(0.32, 0.34, 0.1)
	pieces.append(["spine_03", Transform3D(Basis.looking_at(-fwd), chest_c - fwd * 0.17 - Vector3(0, 0.02, 0)), pack, 0])
	# Helmet: rounded shell and a wraparound visor.
	var head_c: Vector3 = pos.call("Head") + Vector3(0, 0.1, 0) + fwd * 0.015
	var helmet := SphereMesh.new()
	helmet.radius = 0.16
	helmet.height = 0.34
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
		pieces.append(["upperarm_" + s, Transform3D(Basis.looking_at(-fwd).scaled(Vector3(0.27, 0.24, 0.28)), sh + Vector3(0, 0.03, 0)), pauldron, 0])
		limb.call("upperarm_" + s, "upperarm_" + s, "lowerarm_" + s, 0.13, 0.13, 0.6, 0.55, 0.0)
		limb.call("lowerarm_" + s, "lowerarm_" + s, "hand_" + s, 0.13, 0.13, 0.7, 0.55, 0.0)
		limb.call("thigh_" + s, "thigh_" + s, "calf_" + s, 0.2, 0.2, 0.7, 0.45, 0.02)
		limb.call("calf_" + s, "calf_" + s, "foot_" + s, 0.15, 0.15, 0.62, 0.5, 0.025)
		var foot: Vector3 = pos.call("foot_" + s)
		var boot := BoxMesh.new()
		boot.size = Vector3(0.15, 0.12, 0.29)
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

## Layers `library` (the CLIPS, for this skeleton) in an AnimationTree; aim
## and shoot drive only `upper_bones`.
func _build_tree(library: AnimationLibrary, upper_bones: Array) -> void:
	var player := AnimationPlayer.new()
	_model.add_child(player)
	player.add_animation_library("", library)
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
	for b: String in upper_bones:
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
	# Advanced by animate() (_advance), at a rate set_detail picks.
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_model.add_child(_tree)
	_tree.root_node = NodePath("..")
	_tree.anim_player = _tree.get_path_to(player)
	_tree.set("parameters/upper/blend_amount", 1.0)
	_tree.active = true
	_hold = HoldWeapon.new()
	_hold.rig = self
	_skeleton.add_child(_hold)
	_skeleton.skeleton_updated.connect(_place_weapon)
	_cache_bones()


func _cache_bones() -> void:
	var sk := _skeleton
	_b_chest = sk.find_bone(_chest_bone())
	_b_chest_parent = sk.get_bone_parent(_b_chest)
	_b_spine = PackedInt32Array([_b_chest])
	for i in 2:
		var below := sk.get_bone_parent(_b_spine[0])
		if below >= 0:
			_b_spine.insert(0, below)
	_b_head = sk.find_bone("Head")
	_b_head_parent = sk.get_bone_parent(_b_head)
	if _b_head >= 0:
		_head_rest = sk.get_bone_global_rest(_b_head).basis.orthonormalized()
	_arms.clear()
	_arm_rests.clear()
	for chain: Array in _arm_chains():
		var u := sk.find_bone(chain[0])
		var f := sk.find_bone(chain[1])
		var h := sk.find_bone(chain[2])
		_arms.append(PackedInt32Array([u, f, h, sk.get_bone_parent(u)]))
		var rests := [sk.get_bone_global_rest(u), sk.get_bone_global_rest(f), sk.get_bone_global_rest(h)]
		_arm_rests.append([rests[0], rests[1], rests[2], sk.get_bone_rest(u).origin,
				rests[0].origin.distance_to(rests[1].origin), rests[1].origin.distance_to(rests[2].origin)])


## Animation detail, for characters far away or off screen (PlayerVisual):
## `ik` off leaves the arms and head in the clips' pose (the HoldWeapon
## modifier is off; the weapon still follows the aim); the tree advances
## every `anim_every` frames (0: paused), `phase` spreading those frames
## across characters.
func set_detail(ik: bool, anim_every: int, phase: int = 0) -> void:
	_ik = ik
	_anim_every = anim_every
	_anim_phase = phase
	if _hold != null:
		_hold.active = ik


func _advance(delta: float) -> void:
	_anim_dt += delta
	if not _tree.active or _anim_every <= 0 or (Engine.get_process_frames() + _anim_phase) % _anim_every != 0:
		return
	_tree.advance(_anim_dt)
	_anim_dt = 0.0
	if not _ik:
		_hold_weapon()  # the modifier is off: just aim the weapon
		_place_weapon()


## The animation-library clips for this body: rotations only, except the
## pelvis position, scaled to this body's hip height (keeps its proportions).
static func _retargeted(target: Skeleton3D) -> AnimationLibrary:
	if _library != null:
		return _library
	var src: Node = (load(ANIM_SOURCE) as PackedScene).instantiate()
	var src_player: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var src_skel: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var hips_src := src_skel.get_bone_global_rest(src_skel.find_bone("pelvis")).origin.y
	var hips_dst := target.get_bone_global_rest(target.find_bone("pelvis")).origin.y
	var ratio := hips_dst / maxf(hips_src, 0.01)
	_library = AnimationLibrary.new()
	for clip: String in CLIPS:
		if not src_player.has_animation(clip):
			continue
		var a: Animation = src_player.get_animation(clip).duplicate(true)
		for t in range(a.get_track_count() - 1, -1, -1):
			var type := a.track_get_type(t)
			var bone := String(a.track_get_path(t).get_concatenated_subnames())
			if type == Animation.TYPE_SCALE_3D or (type == Animation.TYPE_POSITION_3D and bone != "pelvis"):
				a.remove_track(t)
			elif type == Animation.TYPE_POSITION_3D:
				for k in a.track_get_key_count(t):
					a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * ratio)
		if clip in LOOPING:
			a.loop_mode = Animation.LOOP_LINEAR
		_library.add_animation(clip, a)
	src.free()
	return _library


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
	_tree.set("parameters/aim/blend_position", clampf(state.pitch / 1.2, -1.0, _aim_up))
	_look_pitch = state.pitch
	var twist := 0.0
	if speed > 0.6:
		twist = clampf(atan2(-local.x, absf(local.z) + 0.001) * (-1.0 if backwards else 1.0), -MAX_LEG_TWIST, MAX_LEG_TWIST)
	_twist = lerp_angle(_twist, twist, minf(delta * 10.0, 1.0))
	_model.rotation.y = PI + _twist
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 8.0, 0.0)
		_apply_emission()
	_advance(delta)


## Keeps the head upright after the animation: the library's pistol-aim
## clips bow the neck to sight down a pistol, which read as a head tilted
## forward. The head keeps its rest (upright) orientation in the skeleton,
## turned by the look pitch.
func _level_head() -> void:
	if _b_head < 0 or _b_head_parent < 0 or not _tree.active:
		return
	# The skeleton faces +Z (the model is turned to face -Z), so its right is -X.
	var upright := Basis(Vector3.LEFT, _look_pitch * HEAD_PITCH) * _head_rest
	var local := _skeleton.get_bone_global_pose(_b_head_parent).basis.orthonormalized().inverse() * upright
	_skeleton.set_bone_pose_rotation(_b_head, local.get_rotation_quaternion())


## Third person: the weapon where _hold_weapon put it, along the look
## direction. Held by the hand bone's own rotation, the aim clips (made for a
## pistol) turned it 90 degrees across the body. A child of the rig, so it
## moves with it between pose updates.
func _place_weapon() -> void:
	if _weapon_node != null and is_inside_tree():  # the skeleton updates once more while leaving
		_weapon_node.transform = _weapon_local


## The weapon shouldered along the aim (SHOULDER_TO_HANDLE), the right hand
## on its handle and the left on the fore-end (only the weapon when not
## `_ik`). Runs after the animation.
func _hold_weapon() -> void:
	if _weapon_node == null or not _tree.active or not is_inside_tree():
		return  # first person poses the arms itself (pose_first_person)
	var hold: Array = HOLDS.get(_weapon_id, [SHOULDER_TO_HANDLE, BLADE])
	if _ik:
		# Bladed stance: the chest turns right about the skeleton's up (+Y; it
		# faces +Z, so a right turn is negative), and back by the legs' twist
		# towards a strafe (_twist turns the whole model): turned with the
		# legs, a strafe to the left swung the left shoulder away from the
		# fore-end. The turn back is spread over the chest and the two spine
		# bones below it (_b_spine), so the waist doesn't wring.
		for bone: int in _b_spine:
			var angle := -_twist / _b_spine.size() - (float(hold[1]) if bone == _b_chest else 0.0)
			var turned := Basis(Vector3.UP, angle) * _skeleton.get_bone_global_pose(bone).basis
			_skeleton.set_bone_pose_rotation(bone, (_skeleton.get_bone_global_pose(
					_skeleton.get_bone_parent(bone)).basis.inverse() * turned).get_rotation_quaternion())
		# The left collarbone at rest: the run clips swing it, carrying the
		# left shoulder back out of reach of the fore-end.
		_skeleton.set_bone_pose_rotation(_arms[1][3], _skeleton.get_bone_rest(_arms[1][3]).basis.get_rotation_quaternion())
	var to_rig := global_transform.affine_inverse() * _skeleton.global_transform
	var shoulder := to_rig * _skeleton.get_bone_global_pose(_arms[0][0]).origin
	var aim := Basis(Vector3.RIGHT, _look_pitch)
	var held := aim.scaled_local(Vector3.ONE * _grip_scale())
	var handle: Vector3 = shoulder + aim * (hold[0] as Vector3)
	handle -= aim * Vector3.FORWARD * _pull_back(handle, held * (_support_at - _grip_at), aim * Vector3.FORWARD, _max_pull_back())
	_weapon_local = Transform3D(held, handle - held * _grip_at)
	if _ik:
		_pose_arms(_weapon_local, handle, _weapon_local * _support_at)


## Fire: the upper body plays a recoil.
func on_fire() -> void:
	_tree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func muzzle_position() -> Vector3:
	var m: Node3D = _weapon_node.get_node_or_null("Muzzle") if _weapon_node != null else null
	return m.global_position if m != null else Vector3.INF


func set_weapon(id: StringName) -> void:
	if id == _weapon_id or _skeleton == null:
		return
	_weapon_id = id
	hold_model(WeaponModels.instantiate(id))


## Holds weapon model `w` (from WeaponModels; null: empty hands).
func hold_model(w: Node3D) -> void:
	if _weapon_node != null:
		_weapon_node.queue_free()
		_weapon_node = null
	if w == null or _skeleton == null:
		return
	# Placed every pose (_place_weapon): the handle in the right hand, the
	# barrel where the player looks.
	add_child(w)
	_weapon_node = w
	_grip_at = (w.get_node("Grip") as Node3D).position
	_support_at = (w.get_node("Support") as Node3D).position
	_place_weapon()


## The weapon's transform in the hand bone's space: grip in the right hand,
## barrel along the hand's forward.
func _grip_local() -> Transform3D:
	return Transform3D(Basis.from_euler(GRIP_EULER) * GRIP_SCALE, GRIP_OFFSET)


## The weapon's scale relative to the hand, in metres.
func _grip_scale() -> float:
	return GRIP_SCALE


## Each arm's [upper arm, forearm, hand] bones, right first; the upper arms'
## subtrees are what first person keeps.
func _arm_chains() -> Array:
	return [["upperarm_r", "lowerarm_r", "hand_r"], ["upperarm_l", "lowerarm_l", "hand_l"]]


## The upper chest, which turns for the bladed stance.
func _chest_bone() -> String:
	return "spine_03"


func _arm_roots() -> Array:
	return _arm_chains().map(func(c: Array) -> String: return c[0])


## First-person right hand placed from the handle rather than the
## third-person grip: [fingers, palm normal, palm centre] in the hand bone's
## space (skeleton units), optionally then the left hand's frame (columns
## little-finger side, fingers, palm normal; else the right's). The hand is
## posed palm against the handle's right side, fingers forward, thumb up;
## the rig curls its fingers around it.
## Empty: hold the weapon by the grip transform (_grip_local).
func _fp_hand() -> Array:
	return []


func head_position() -> Vector3:
	var head := _skeleton.find_bone("Head") if _skeleton.find_bone("Head") >= 0 else _skeleton.find_bone("neck")
	return global_transform.affine_inverse() * _skeleton.global_transform * _skeleton.get_bone_global_rest(head).origin


func pose_first_person(weapon: Transform3D, handle: Vector3, support: Vector3) -> void:
	_pose_arms(weapon, handle, support)


## The right hand on `handle` of `weapon`, the left on `support` (this rig's
## space), by IK.
func _pose_arms(weapon: Transform3D, handle: Vector3, support: Vector3) -> void:
	var to_skel := (global_transform.affine_inverse() * _skeleton.global_transform).affine_inverse()
	var grip := _grip_local()
	var unit := grip.basis.get_scale().x / _grip_scale()  ## skeleton units per metre (e.g. 100 for cm)
	var hand_basis: Basis
	var hand_pos: Vector3
	var support_basis := Basis()  ## identity: the left hand keeps its forearm's
	var fp := _fp_hand()
	if fp.is_empty():
		# The hand that holds `weapon`: undo the grip, keeping metres for the offset.
		# The weapon is held as in third person, moved so its handle sits
		# where the pulse rifle's does (WeaponModels.grip_shift).
		var w := weapon.basis.orthonormalized()
		hand_basis = w * grip.basis.orthonormalized().inverse()
		var shift := weapon.basis * WeaponModels.reference_grip() - (handle - weapon.origin)
		hand_pos = weapon.origin - hand_basis * (grip.origin / unit) - shift
	else:
		# Fingers forward and a little down, palm against the handle's right
		# side; the rig curls the fingers around it.
		var w := weapon.basis.orthonormalized()
		var fingers := (w * Vector3(-FP_FINGER_IN, -FP_FINGER_DROP, -1.0)).normalized()
		var palm := -w.x
		palm = (palm - fingers * palm.dot(fingers)).normalized()
		var hand_fingers: Vector3 = (fp[0] as Vector3).normalized()
		var hand_palm: Vector3 = (fp[1] as Vector3).normalized()
		var local := Basis(hand_fingers.cross(hand_palm), hand_fingers, hand_palm)
		hand_basis = Basis(fingers.cross(palm), fingers, palm) * local.inverse()
		var centre: Vector3 = fp[2]
		hand_pos = handle + w * FP_PALM_AT - hand_basis * (centre * _hand_scale / unit)
		# The left hand on the fore-end: palm against its side, fingers
		# forward and across, curled round it.
		var s_fingers := (w * (SUPPORT_FINGERS if _tree.active else FP_SUPPORT_FINGERS)).normalized()
		var s_palm := w * (SUPPORT_PALM if _tree.active else FP_SUPPORT_PALM)
		s_palm = (s_palm - s_fingers * s_palm.dot(s_fingers)).normalized()
		var s_local: Basis = fp[3] if fp.size() > 3 else local
		support_basis = Basis(s_fingers.cross(s_palm), s_fingers, s_palm) * s_local.inverse()
	support = to_skel.affine_inverse() * _within_reach(1, to_skel * support, to_skel * handle)
	# Elbows down, out and slightly back in first person; third person turns
	# them as TP_RIGHT_ELBOW and TP_LEFT_ELBOW (skeleton space: the body faces
	# +Z, its right is -X).
	_reach(0, to_skel * hand_pos, (to_skel.basis * hand_basis).orthonormalized(),
			TP_RIGHT_ELBOW if _tree.active else Vector3(-0.5, -1.0, -0.6))
	_reach(1, to_skel * support, (to_skel.basis * support_basis).orthonormalized(),
			TP_LEFT_ELBOW if _tree.active else Vector3(0.3, -1.0, -0.8))


## FP_HAND_SCALE, for this rig's hands.
func _fp_hand_scale() -> float:
	return FP_HAND_SCALE


## MAX_PULL_BACK, for this rig's build.
func _max_pull_back() -> float:
	return MAX_PULL_BACK


## How far (rig space, at most `most`) to move the weapon from `handle`
## back along `forward` for the left arm to reach its fore-end, `support`
## ahead of the handle.
func _pull_back(handle: Vector3, support: Vector3, forward: Vector3, most: float) -> float:
	var to_rig := global_transform.affine_inverse() * _skeleton.global_transform
	var rests: Array = _arm_rests[1]
	var shoulder := to_rig * (_skeleton.get_bone_global_pose(_arms[1][3]) * (rests[3] as Vector3))
	var unit := to_rig.affine_inverse().basis.get_scale().x
	var reach: float = (rests[4] + rests[5]) * SUPPORT_REACH / unit
	# Least t >= 0 with |handle + support - t forward - shoulder| <= reach.
	var f := handle + support - shoulder
	var b := -2.0 * f.dot(forward)
	var c := f.length_squared() - reach * reach
	if c <= 0.0:
		return 0.0
	var disc := b * b - 4.0 * c
	if disc < 0.0:
		return most
	return clampf((-b - sqrt(disc)) / 2.0, 0.0, most)


## The point nearest `want` along the weapon (from `handle` towards `want`)
## that arm `arm` (0 right, 1 left) reaches (SUPPORT_REACH), skeleton space.
func _within_reach(arm: int, want: Vector3, handle: Vector3) -> Vector3:
	var rests: Array = _arm_rests[arm]
	var shoulder := _skeleton.get_bone_global_pose(_arms[arm][3]) * (rests[3] as Vector3)
	var reach: float = (rests[4] + rests[5]) * SUPPORT_REACH
	if want.distance_to(shoulder) <= reach:
		return want
	# The far end of the weapon line within the reach sphere:
	# |handle + t (want - handle) - shoulder| = reach.
	var d := want - handle
	var f := handle - shoulder
	var a := d.length_squared()
	var b := 2.0 * f.dot(d)
	var disc := b * b - 4.0 * a * (f.length_squared() - reach * reach)
	if a < 1e-8 or disc < 0.0:
		return handle
	return handle + d * clampf((-b + sqrt(disc)) / (2.0 * a), 0.0, 1.0)


## Two-bone IK in skeleton space: arm `arm`'s (0 right, 1 left) upper arm
## and forearm bend in the plane towards `pole` so the hand lands on
## `target`; the hand takes `hand_basis` (identity basis: keep the forearm's).
func _reach(arm: int, target: Vector3, hand_basis: Basis, pole: Vector3) -> void:
	var sk := _skeleton
	var bones := _arms[arm]
	var rests: Array = _arm_rests[arm]
	var u := bones[0]
	var f := bones[1]
	var h := bones[2]
	var rest_u: Transform3D = rests[0]
	var rest_f: Transform3D = rests[1]
	var rest_h: Transform3D = rests[2]
	var l1: float = rests[4]
	var l2: float = rests[5]
	var parent := sk.get_bone_global_pose(bones[3])
	var shoulder := parent * (rests[3] as Vector3)
	var to_target := target - shoulder
	var d := clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to_target.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * a + bend * sqrt(maxf(l1 * l1 - a * a, 0.0))
	var wrist := shoulder + dir * d
	# Upper arm: turn its rest direction onto the elbow.
	var swing_u := Quaternion((rest_f.origin - rest_u.origin).normalized(), (elbow - shoulder).normalized())
	var upper := Basis(swing_u) * rest_u.basis.orthonormalized()
	sk.set_bone_pose_rotation(u, (parent.basis.orthonormalized().inverse() * upper).get_rotation_quaternion())
	# Forearm: from where the upper arm carried it onto the wrist.
	var fore_dir := Basis(swing_u) * (rest_h.origin - rest_f.origin).normalized()
	var swing_f := Quaternion(fore_dir, (wrist - elbow).normalized())
	var fore := Basis(swing_f) * Basis(swing_u) * rest_f.basis.orthonormalized()
	sk.set_bone_pose_rotation(f, (upper.inverse() * fore).get_rotation_quaternion())
	if hand_basis != Basis():
		# The forearm takes the hand's roll about its own axis (as the radius
		# does), so the wrist only bends instead of wringing the skin.
		var rel := (fore.inverse() * hand_basis).get_rotation_quaternion()
		var axis := (fore.inverse() * (Basis(swing_f) * fore_dir)).normalized()
		var proj := axis * Vector3(rel.x, rel.y, rel.z).dot(axis)
		var twist := Quaternion(proj.x, proj.y, proj.z, rel.w).normalized()
		if twist.w < 0.0:
			twist = -twist  # the shorter way round
		if twist.get_angle() > MAX_FOREARM_TWIST:
			twist = Quaternion(twist.get_axis(), MAX_FOREARM_TWIST)
		fore = fore * Basis(twist)
		sk.set_bone_pose_rotation(f, (upper.inverse() * fore).get_rotation_quaternion())
		sk.set_bone_pose_rotation(h, (fore.inverse() * hand_basis).get_rotation_quaternion())


func make_first_person() -> bool:
	_tree.active = false
	_skeleton.reset_bone_poses()
	_hand_scale = _fp_hand_scale()
	for chain: Array in _arm_chains():
		_skeleton.set_bone_pose_scale(_skeleton.find_bone(chain[2]), Vector3.ONE * _hand_scale)
	_model.rotation.y = PI
	var keep := {}
	for root: String in _arm_roots():
		var stack := [_skeleton.find_bone(root)]
		while not stack.is_empty():
			var b: int = stack.pop_back()
			keep[_skeleton.get_bone_name(b)] = true
			stack.append_array(_skeleton.get_bone_children(b))
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.skin == null or not mi.visible:
			mi.visible = false
			continue
		var key := mi.mesh.get_instance_id()
		if not _arms_cache.has(key):
			_arms_cache[key] = _arms_only(mi.mesh, mi.skin, _skeleton, keep, _arm_chains())
		mi.mesh = _arms_cache[key]
	return true


## `mesh` keeping only triangles mostly weighted to `keep` bones, less the
## top FP_SHOULDER_CUT of each upper arm (`chains`: upper arm, forearm and
## hand bone names). Kept vertices follow only the kept bones.
static func _arms_only(mesh: Mesh, skin: Skin, sk: Skeleton3D, keep: Dictionary, chains: Array = []) -> ArrayMesh:
	var kept_bind := PackedByteArray()
	kept_bind.resize(skin.get_bind_count())
	for i in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(i))
		if bone_name.is_empty():
			bone_name = sk.get_bone_name(skin.get_bind_bone(i))
		kept_bind[i] = 1 if keep.has(bone_name) else 0
	# Each upper arm, shoulder to elbow, in the mesh's bind space.
	var upper_arms := []
	for chain: Array in chains:
		var ends := []
		for bone_name: String in [chain[0], chain[1]]:
			for i in skin.get_bind_count():
				var n := String(skin.get_bind_name(i))
				if (n if not n.is_empty() else sk.get_bone_name(skin.get_bind_bone(i))) == bone_name:
					ends.append(skin.get_bind_pose(i).affine_inverse().origin)
		if ends.size() == 2:
			upper_arms.append(ends)
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or bones.is_empty():
			continue  # no CPU-side data (headless dummy renderer)
		var per := bones.size() / verts.size()
		var on_arm := PackedByteArray()
		on_arm.resize(verts.size())
		for v in verts.size():
			var w := 0.0
			for k in per:
				if kept_bind[bones[v * per + k]]:
					w += weights[v * per + k]
			on_arm[v] = 1 if w > 0.5 and not _near_shoulder(verts[v], upper_arms) else 0
		# Kept vertices follow the kept bones only, so nothing stretches back
		# to the (hidden) body.
		for v in verts.size():
			if not on_arm[v]:
				continue
			var total := 0.0
			for k in per:
				if kept_bind[bones[v * per + k]]:
					total += weights[v * per + k]
				else:
					weights[v * per + k] = 0.0
			for k in per:
				weights[v * per + k] /= total
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		for t in range(0, indices.size(), 3):
			if on_arm[indices[t]] and on_arm[indices[t + 1]] and on_arm[indices[t + 2]]:
				kept.append_array([indices[t], indices[t + 1], indices[t + 2]])
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
	return out


## Whether bind-space point `v` is in the top FP_SHOULDER_CUT of one of the
## `upper_arms` ([shoulder, elbow] pairs).
static func _near_shoulder(v: Vector3, upper_arms: Array) -> bool:
	for seg: Array in upper_arms:
		var a: Vector3 = seg[0]
		var ab: Vector3 = seg[1] - a
		var t := (v - a).dot(ab) / ab.length_squared()
		if t < FP_SHOULDER_CUT and (v - a - ab * clampf(t, 0.0, 1.0)).length() < ab.length() * 0.6:
			return true
	return false


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

