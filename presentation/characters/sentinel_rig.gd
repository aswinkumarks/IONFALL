class_name SentinelRig
extends ArmoredRig
## Cybernetic Sentinel (default): a Meshy community model (CC0, by tborcen),
## reduced to ~15.6k triangles and auto-rigged by Meshy (24-bone humanoid,
## centimetres, A-pose), plus 30 finger bones added by
## tools/rig_sentinel_fingers.gd. It reuses ArmoredRig's AnimationTree with the
## Universal Animation Library clips, retargeted in model space: each bone
## takes the source bone's rotation relative to its rest, after a per-bone
## correction from the T-pose rest to this A-pose rest. The armour's blue
## panels and light strips are recoloured to the player's colour by
## sentinel.gdshader.

const SENTINEL_SCENE := "res://art/characters/sentinel/sentinel.glb"
## Finger bones (Meshy's rig has none), from tools/rig_sentinel_fingers.gd:
## the re-weighted mesh and a skin whose extra binds are the new bones.
const FINGER_MESH := "res://art/characters/sentinel/sentinel_fingers_mesh.res"
const FINGER_SKIN := "res://art/characters/sentinel/sentinel_fingers_skin.tres"
const SHADER := preload("res://presentation/characters/sentinel.gdshader")
## Animation-library bone -> Sentinel bone.
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
const SENTINEL_UPPER := ["Spine01", "Spine", "neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const SAMPLE_FPS := 30.0
## Finger curl in degrees per joint (base, middle, tip), towards the palm:
## the right hand closes around the grip, the left cups the fore-end.
const GRIP_CURL := {"Thumb": [15.0, 30.0, 25.0], "Index": [60.0, 75.0, 45.0], "Middle": [70.0, 80.0, 50.0],
		"Ring": [75.0, 80.0, 50.0], "Pinky": [80.0, 80.0, 50.0]}
const SUPPORT_CURL := {"Thumb": [10.0, 20.0, 15.0], "Index": [35.0, 40.0, 25.0], "Middle": [40.0, 45.0, 30.0],
		"Ring": [45.0, 45.0, 30.0], "Pinky": [50.0, 45.0, 30.0]}
## The palm's normal in the hand bones' space (fingers +Y).
const PALM := Vector3(0.0, 0.0, -1.0)
const SENTINEL_GRIP_SCALE := 2.0  ## a touch smaller than ArmoredRig: slimmer hands

static var _sentinel_library: AnimationLibrary
static var _grip: Transform3D  ## GRIP in the Sentinel's hand space

var _mat: ShaderMaterial


func setup(color: Color) -> void:
	_color = color
	_model = (load(SENTINEL_SCENE) as PackedScene).instantiate()
	_model.rotation.y = PI  # faces +Z; Godot forward is -Z
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	var skin: Skin = load(FINGER_SKIN)
	_add_finger_bones(_skeleton, skin)
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.mesh = load(FINGER_MESH)
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
	_hand = BoneAttachment3D.new()
	_hand.bone_name = "RightHand"
	_skeleton.add_child(_hand)
	_build_tree(_retarget_to(_skeleton, String(_model.get_path_to(_skeleton))), SENTINEL_UPPER)
	_curl_hands()


## The animations don't move the fingers, so their curl is set once (again
## after make_first_person resets the pose).
func _curl_hands() -> void:
	_curl(_skeleton, "Right", GRIP_CURL)
	_curl(_skeleton, "Left", SUPPORT_CURL)


## Bends each joint of `side`'s fingers by `curl` degrees about the axis that
## turns it towards the palm (its direction × the palm normal).
static func _curl(sk: Skeleton3D, side: String, curl: Dictionary) -> void:
	for finger: String in curl:
		for k in 3:
			var bone := sk.find_bone("%sHand%s%d" % [side, finger, k + 1])
			if bone < 0:
				continue
			var next := sk.find_bone("%sHand%s%d" % [side, finger, k + 2])
			var dir := sk.get_bone_rest(next if next >= 0 else bone).origin.normalized()
			sk.set_bone_pose_rotation(bone, Quaternion(dir.cross(PALM).normalized(), deg_to_rad(curl[finger][k])))


func make_first_person() -> bool:
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


func _grip_local() -> Transform3D:
	return _grip


## First person: the palm against the handle, fingers curled round it
## (GRIP_CURL). Hand bone space (cm): fingers +Y, palm -Z, thumb -X.
func _fp_hand() -> Array:
	return [Vector3.UP, Vector3.FORWARD, Vector3(-1.0, 8.0, -4.0)]


func _arm_chains() -> Array:
	return [["RightArm", "RightForeArm", "RightHand"], ["LeftArm", "LeftForeArm", "LeftHand"]]


func _grip_scale() -> float:
	return SENTINEL_GRIP_SCALE


func _apply_emission() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("glow", _glow)
	_mat.set_shader_parameter("flash", _flash)


## The animation-library clips for `target` (the Sentinel skeleton, reached
## from the model root by `skel_path`), baked at SAMPLE_FPS.
static func _retarget_to(target: Skeleton3D, skel_path: String) -> AnimationLibrary:
	if _sentinel_library != null:
		return _sentinel_library
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
	# The weapon grip, carried into the Sentinel's hand space.
	var hand_fix: Basis = dst_rest[tb.call("hand_r")].basis.orthonormalized().inverse() \
			* Basis(fix["hand_r"]).inverse() * src_rest[sb.call("hand_r")].basis.orthonormalized()
	var unit: float = 1.0 / (target.get_parent() as Node3D).scale.x if target.get_parent() is Node3D else 1.0
	_grip = Transform3D(hand_fix * Basis.from_euler(GRIP_EULER) * (SENTINEL_GRIP_SCALE * unit), hand_fix * GRIP_OFFSET * unit)

	_sentinel_library = AnimationLibrary.new()
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
		_sentinel_library.add_animation(clip, out)
	src.free()
	return _sentinel_library


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
