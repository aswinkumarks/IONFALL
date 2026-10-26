@tool
class_name MeshyRig
extends ArmoredRig
## The selectable characters (Sentinel, Vanguard, Operative, Spacer):
## models generated for IONFALL with Meshy and auto-rigged by Meshy (24-bone
## humanoid, centimetres, A- or T-pose), plus 30 finger bones added by
## tools/rig_meshy_fingers.gd. They reuse ArmoredRig's AnimationTree with the
## Universal Animation Library clips, retargeted in model space: each bone
## takes the source bone's rotation relative to its rest, after a per-bone
## correction from the source's T-pose rest to this rest. The armour's light
## plates and glowing strips take the player's colour
## (meshy_character.gdshader).

const DIR := "res://art/characters/meshy/"
const SHADER := preload("res://presentation/characters/meshy_character.gdshader")
## Animation-library bone -> Meshy bone.
const BONE_MAP := {
	"pelvis": "Hips", "spine_01": "Spine02", "spine_02": "Spine01", "spine_03": "Spine", "neck_01": "neck",
	"Head": "Head",
	"clavicle_l": "LeftShoulder", "upperarm_l": "LeftArm", "lowerarm_l": "LeftForeArm", "hand_l": "LeftHand",
	"clavicle_r": "RightShoulder", "upperarm_r": "RightArm", "lowerarm_r": "RightForeArm", "hand_r": "RightHand",
	"thigh_l": "LeftUpLeg", "calf_l": "LeftLeg", "foot_l": "LeftFoot", "ball_l": "LeftToeBase",
	"thigh_r": "RightUpLeg", "calf_r": "RightLeg", "foot_r": "RightFoot", "ball_r": "RightToeBase",
}
## The next bone along each chain, which gives a bone's direction; bones
## without one (head, hands, toes) take their parent's rest correction.
const CHAIN := {
	"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "Head",
	"clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l",
	"thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r",
}
const MESHY_UPPER := ["Spine01", "Spine", "neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const SAMPLE_FPS := 30.0
## Finger curl in degrees per joint (base, middle, tip), towards the palm:
## the right hand closes around the grip (the index finger less, on the
## trigger), the left cups the fore-end.
const GRIP_CURL := {"Thumb": [15.0, 30.0, 25.0], "Index": [25.0, 50.0, 35.0], "Middle": [70.0, 80.0, 50.0],
		"Ring": [75.0, 80.0, 50.0], "Pinky": [80.0, 80.0, 50.0]}
const SUPPORT_CURL := {"Thumb": [10.0, 20.0, 15.0], "Index": [35.0, 40.0, 25.0], "Middle": [40.0, 45.0, 30.0],
		"Ring": [45.0, 45.0, 30.0], "Pinky": [50.0, 45.0, 30.0]}
## First person the left hand cradles the fore-end from below
## (ArmoredRig.FP_SUPPORT_PALM): its fingers close further, round the far
## side.
const FP_SUPPORT_CURL := {"Thumb": [14.0, 28.0, 21.0], "Index": [49.0, 56.0, 35.0], "Middle": [56.0, 63.0, 42.0],
		"Ring": [63.0, 63.0, 42.0], "Pinky": [70.0, 63.0, 42.0]}
## Where the palm's centre is from the hand bone (cm), along the hand
## frame's axes (_hand_frame: thumb side, fingers, palm normal).
const FP_PALM_CENTRE := Vector3(1.0, 8.0, 2.0)
const MESHY_GRIP_SCALE := 2.0  ## a touch smaller than ArmoredRig: slimmer hands
## First person: how far the arms sit ahead of where the head bone puts them
## (metres). The Spacer's head bone sits forward in its big helmet, which
## left its shoulders too far back to reach the handle.
const FP_FORWARD := {"spacer": 0.05}
## Third person: the slim characters bring a long gun back a little for the
## left hand to reach its fore-end (ArmoredRig.MAX_PULL_BACK, metres).
const PULL_BACK := {"operative": 0.06, "spacer": 0.06}
## First person: the Spacer's long, spiked glove fingers stood out past the
## weapon even closed; its hands are drawn smaller still
## (ArmoredRig.FP_HAND_SCALE).
const FP_HAND_SCALES := {"spacer": 0.65}

static var _libraries := {}  ## character -> AnimationLibrary, baked once
static var _grips := {}  ## character -> GRIP in its hand space

var character: String
## The full mesh instead of the reduced one (reduced_mesh_path): set before setup()
## for close-ups (the character screen); first person switches by itself.
var full_detail := false
var _mat: ShaderMaterial


func _init(p_character: String = "sentinel") -> void:
	character = p_character


## Every file the selectable characters load, for loading ahead of a match.
static func paths() -> PackedStringArray:
	var out := PackedStringArray()
	for c: String in CharacterRig.SELECTABLE:
		out.append_array([scene_path(c), finger_mesh_path(c), reduced_mesh_path(c), finger_skin_path(c), anims_path(c)])
	return out


static func scene_path(c: String) -> String:
	return DIR + c + "/" + c + ".glb"


## The re-weighted mesh and the skin with the finger binds
## (tools/rig_meshy_fingers.gd).
static func finger_mesh_path(c: String) -> String:
	return DIR + c + "/" + c + "_fingers_mesh.res"


## The third-person mesh (ReducedMesh, saved by
## tools/bake_reduced_characters.gd).
static func reduced_mesh_path(c: String) -> String:
	return DIR + c + "/" + c + "_reduced_mesh.res"


static func finger_skin_path(c: String) -> String:
	return DIR + c + "/" + c + "_fingers_skin.tres"


## The retargeted clips, baked ahead by tools/rig_meshy_fingers.gd: baking
## takes ~0.4 s per character on a laptop, several times that on a phone.
static func anims_path(c: String) -> String:
	return DIR + c + "/" + c + "_anims.res"


func setup(color: Color) -> void:
	# The aim-up clip retargets badly onto these skeletons (the right hand
	# drops to the hip): looking up keeps the level aim pose; the weapon
	# still tilts.
	_aim_up = 0.0
	_color = color
	_model = (load(scene_path(character)) as PackedScene).instantiate()
	_model.rotation.y = PI  # faces +Z; Godot forward is -Z
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	var skin: Skin = load(finger_skin_path(character))
	_add_finger_bones(_skeleton, skin)
	_curl_hands()
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.mesh = load(finger_mesh_path(character) if full_detail else reduced_mesh_path(character))
		mi.skin = skin
		var base := mi.get_active_material(0) as StandardMaterial3D
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("albedo_tex", base.albedo_texture)
		_mat.set_shader_parameter("mr_tex", base.metallic_texture)
		_mat.set_shader_parameter("normal_tex", base.normal_texture)
		_mat.set_shader_parameter("team_color", color)
		mi.material_override = _mat
	for a: AnimationPlayer in _model.find_children("*", "AnimationPlayer", true, false):
		a.queue_free()  # Meshy's rig-check clip; the tree drives the skeleton
	_build_tree(_retarget_to(character, _skeleton, String(_model.get_path_to(_skeleton))), MESHY_UPPER)


## The animations don't move the fingers, so the curl goes into the finger
## bones' rests: the tree's pose resets then leave them curled, with nothing
## to redo each frame. Again for first person (its left-hand curl).
func _curl_hands() -> void:
	_curl(_skeleton, "Right", GRIP_CURL)
	_curl(_skeleton, "Left", SUPPORT_CURL if _tree == null or _tree.active else FP_SUPPORT_CURL)


## `side`'s hand frame in its bone's space, from the finger bones: columns
## thumb side, fingers, palm normal. The auto-rig orients each character's
## hand bones differently (the Operative's palm faces about 140° from the
## Sentinel's), so no one axis is the palm for all of them.
static func _hand_frame(sk: Skeleton3D, side: String) -> Basis:
	var at := func(f: String) -> Vector3:
		return sk.get_bone_rest(sk.find_bone("%sHand%s1" % [side, f])).origin
	var fingers: Vector3 = (at.call("Index") + at.call("Middle") + at.call("Ring") + at.call("Pinky")).normalized()
	var thumb: Vector3 = at.call("Index") - at.call("Pinky")
	thumb = (thumb - fingers * thumb.dot(fingers)).normalized()
	# Mirrored hands: the right palm is thumb × fingers, the left fingers × thumb.
	var palm := thumb.cross(fingers) if side == "Right" else fingers.cross(thumb)
	return Basis(thumb, fingers, palm)


## Bends each joint of `side`'s fingers by `curl` degrees towards the palm:
## about the hand's knuckle line (the fingers' direction × the palm normal),
## the thumb about its own direction × the palm normal. The auto-rig's
## finger joints zigzag (the Spacer's point half into the palm), so one
## joint's own direction would bend it sideways. Set in the rest as well as
## the pose, so pose resets (the tree's each frame) keep it.
static func _curl(sk: Skeleton3D, side: String, curl: Dictionary) -> void:
	var frame := _hand_frame(sk, side)
	for finger: String in curl:
		for k in 3:
			var bone := sk.find_bone("%sHand%s%d" % [side, finger, k + 1])
			if bone < 0:
				continue
			var axis := frame.y.cross(frame.z)
			if finger == "Thumb":
				var next := sk.find_bone("%sHand%s%d" % [side, finger, k + 2])
				axis = sk.get_bone_rest(next if next >= 0 else bone).origin.normalized().cross(frame.z)
			var q := Quaternion(axis.normalized(), deg_to_rad(curl[finger][k]))
			var rest := sk.get_bone_rest(bone)
			sk.set_bone_rest(bone, Transform3D(Basis(q).scaled_local(rest.basis.get_scale()), rest.origin))
			sk.set_bone_pose_rotation(bone, q)


## First person: the arms are cut from the full mesh (the camera is
## centimetres from them), and the left hand cradles the fore-end
## (FP_SUPPORT_CURL).
func make_first_person() -> bool:
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.mesh = load(finger_mesh_path(character))
	var ok := super()
	_curl_hands()
	return ok


## Adds the skin's binds that `sk` lacks as bones: "<Side>Hand<Finger><n>",
## parented to joint n-1 (the first to the hand). Rests come from the bind
## poses: parent bind × child bind⁻¹.
static func _add_finger_bones(sk: Skeleton3D, skin: Skin) -> void:
	var poses := {}
	for b in skin.get_bind_count():
		poses[String(skin.get_bind_name(b))] = skin.get_bind_pose(b)
	for b in skin.get_bind_count():
		var name := String(skin.get_bind_name(b))
		if sk.find_bone(name) >= 0:
			continue
		var n := name.right(1).to_int()
		var parent := name.left(-1) + str(n - 1) if n > 1 else name.left(name.find("Hand") + 4)
		var bone := sk.add_bone(name)
		sk.set_bone_parent(bone, sk.find_bone(parent))
		sk.set_bone_rest(bone, poses[parent] * (poses[name] as Transform3D).affine_inverse())
	sk.reset_bone_poses()


func head_position() -> Vector3:
	return super() + Vector3(0.0, 0.0, FP_FORWARD.get(character, 0.0))


func _fp_hand_scale() -> float:
	return FP_HAND_SCALES.get(character, super())


func _max_pull_back() -> float:
	return PULL_BACK.get(character, super())


func _grip_local() -> Transform3D:
	return _grips[character]


## First person: the palm against the handle, fingers curled round it
## (GRIP_CURL), in this character's hand frames.
func _fp_hand() -> Array:
	var h := _hand_frame(_skeleton, "Right")
	var l := _hand_frame(_skeleton, "Left")
	return [h.y, h.z, h * FP_PALM_CENTRE, Basis(-l.x, l.y, l.z)]


func _arm_chains() -> Array:
	return [["RightArm", "RightForeArm", "RightHand"], ["LeftArm", "LeftForeArm", "LeftHand"]]


func _chest_bone() -> String:
	return "Spine"


func _grip_scale() -> float:
	return MESHY_GRIP_SCALE


func _apply_emission() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("glow", _glow)
	_mat.set_shader_parameter("flash", _flash)


## The animation-library clips for `target` (`c`'s skeleton, reached from the
## model root by `skel_path`), baked at SAMPLE_FPS unless already baked to
## anims_path (`rebake` ignores that file).
static func _retarget_to(c: String, target: Skeleton3D, skel_path: String, rebake := false) -> AnimationLibrary:
	if _libraries.has(c):
		return _libraries[c]
	if not rebake and ResourceLoader.exists(anims_path(c)):
		var baked: AnimationLibrary = load(anims_path(c))
		_grips[c] = baked.get_meta("grip")
		_libraries[c] = baked
		return baked
	var src: Node = (load(ANIM_SOURCE) as PackedScene).instantiate()
	var src_player: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var src_skel: Skeleton3D = src.find_children("*", "Skeleton3D", true, false)[0]
	var src_rest := _global_rests(src_skel)
	var dst_rest := _global_rests(target)
	var sb := func(n: String) -> int: return src_skel.find_bone(n)
	var tb := func(n: String) -> int: return target.find_bone(BONE_MAP[n])
	# Per-bone rest correction: turns this skeleton's bone direction into the
	# source's (A-pose arms to T-pose), so source-rest maps to target T-pose.
	var fix := {}
	for s: String in BONE_MAP:
		if CHAIN.has(s):
			var a: Vector3 = src_rest[sb.call(CHAIN[s])].origin - src_rest[sb.call(s)].origin
			var b: Vector3 = dst_rest[tb.call(CHAIN[s])].origin - dst_rest[tb.call(s)].origin
			fix[s] = Quaternion(b.normalized(), a.normalized())
	for s: String in BONE_MAP:
		if not fix.has(s):
			fix[s] = fix[src_skel.get_bone_name(src_skel.get_bone_parent(sb.call(s)))]
	var hips_ratio: float = dst_rest[tb.call("pelvis")].origin.y / src_rest[sb.call("pelvis")].origin.y
	# The weapon grip, carried into this skeleton's hand space.
	var hand_fix: Basis = dst_rest[tb.call("hand_r")].basis.orthonormalized().inverse() \
			* Basis(fix["hand_r"]).inverse() * src_rest[sb.call("hand_r")].basis.orthonormalized()
	var unit: float = 1.0 / (target.get_parent() as Node3D).scale.x if target.get_parent() is Node3D else 1.0
	_grips[c] = Transform3D(hand_fix * Basis.from_euler(GRIP_EULER) * (MESHY_GRIP_SCALE * unit), hand_fix * GRIP_OFFSET * unit)

	var library := AnimationLibrary.new()
	library.set_meta("grip", _grips[c])
	for clip: String in CLIPS:
		if not src_player.has_animation(clip):
			continue
		var a: Animation = src_player.get_animation(clip)
		var tracks := {}  ## source bone index -> [rotation track, position track]
		for t in a.get_track_count():
			var bi := src_skel.find_bone(String(a.track_get_path(t).get_concatenated_subnames()))
			if bi < 0:
				continue
			if not tracks.has(bi):
				tracks[bi] = [-1, -1]
			if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				tracks[bi][0] = t
			elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				tracks[bi][1] = t
		var out := Animation.new()
		out.length = a.length
		var out_rot := {}
		for s: String in BONE_MAP:
			var t := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(t, NodePath(skel_path + ":" + BONE_MAP[s]))
			out_rot[s] = t
		var hips_pos := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_pos, NodePath(skel_path + ":" + BONE_MAP["pelvis"]))
		var frames := maxi(ceili(a.length * SAMPLE_FPS), 1)
		for f in frames + 1:
			var time := minf(f / SAMPLE_FPS, a.length)
			var pose := _sample_globals(src_skel, a, tracks, time)
			var dst_global := {}
			for s: String in BONE_MAP:
				var i: int = sb.call(s)
				var delta: Basis = pose[i].basis.orthonormalized() * src_rest[i].basis.orthonormalized().inverse()
				dst_global[s] = delta * Basis(fix[s]) * dst_rest[tb.call(s)].basis.orthonormalized()
			for s: String in BONE_MAP:
				var parent := target.get_bone_parent(tb.call(s))
				var parent_basis: Basis = Basis.IDENTITY
				if parent >= 0:
					var ps := _source_of(target.get_bone_name(parent))
					parent_basis = dst_global[ps] if ps != "" else dst_rest[parent].basis.orthonormalized()
				out.rotation_track_insert_key(out_rot[s], time, (parent_basis.inverse() * dst_global[s]).get_rotation_quaternion())
			var i_p: int = sb.call("pelvis")
			var hips: Vector3 = dst_rest[tb.call("pelvis")].origin + (pose[i_p].origin - src_rest[i_p].origin) * hips_ratio
			out.position_track_insert_key(hips_pos, time, hips)
		if clip in LOOPING:
			out.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(clip, out)
	src.free()
	_libraries[c] = library
	return library


static func _source_of(target_bone: String) -> String:
	for s: String in BONE_MAP:
		if BONE_MAP[s] == target_bone:
			return s
	return ""


static func _global_rests(sk: Skeleton3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for b in sk.get_bone_count():
		out.append(sk.get_bone_global_rest(b))
	return out


## Skeleton-space transforms of every source bone at `time`.
static func _sample_globals(sk: Skeleton3D, a: Animation, tracks: Dictionary, time: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(sk.get_bone_count())
	var done := PackedByteArray()
	done.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		_resolve(sk, a, tracks, time, b, out, done)
	return out


static func _resolve(sk: Skeleton3D, a: Animation, tracks: Dictionary, time: float, b: int,
		out: Array[Transform3D], done: PackedByteArray) -> void:
	if done[b]:
		return
	var local := sk.get_bone_rest(b)
	if tracks.has(b):
		var rot: int = tracks[b][0]
		var pos: int = tracks[b][1]
		var scale := local.basis.get_scale()
		var q := local.basis.get_rotation_quaternion() if rot < 0 else a.rotation_track_interpolate(rot, time)
		local.basis = Basis(q).scaled(scale)
		if pos >= 0:
			local.origin = a.position_track_interpolate(pos, time)
	var parent := sk.get_bone_parent(b)
	if parent >= 0:
		_resolve(sk, a, tracks, time, parent, out, done)
		local = out[parent] * local
	out[b] = local
	done[b] = 1
