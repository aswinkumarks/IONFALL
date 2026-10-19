class_name SentinelRig
extends ArmoredRig
## Cybernetic Sentinel (default): a Meshy community model (CC0, by tborcen),
## reduced to ~15.6k triangles and auto-rigged by Meshy (24-bone humanoid,
## centimetres, A-pose). It reuses ArmoredRig's AnimationTree with the
## Universal Animation Library clips, retargeted in model space: each bone
## takes the source bone's rotation relative to its rest, after a per-bone
## correction from the T-pose rest to this A-pose rest. The armour's blue
## panels and light strips are recoloured to the player's colour by
## sentinel.gdshader.

const SENTINEL_SCENE := "res://art/characters/sentinel/sentinel.glb"
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
## The weapon grip in the animation-library hand space (metres), as ArmoredRig.
const GRIP_EULER := Vector3(0.0, PI * 0.5, PI * 0.5)
const GRIP_SCALE := 2.0  ## a touch smaller than ArmoredRig: slimmer hands
const GRIP_OFFSET := Vector3(0.0, 0.08, 0.03)

static var _sentinel_library: AnimationLibrary
static var _grip: Transform3D  ## GRIP in the Sentinel's hand space

var _mat: ShaderMaterial


func setup(color: Color) -> void:
	_color = color
	_model = (load(SENTINEL_SCENE) as PackedScene).instantiate()
	_model.rotation.y = PI  # faces +Z; Godot forward is -Z
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
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
	w.transform = _grip
	_hand.add_child(w)
	_weapon_node = w


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
	_grip = Transform3D(hand_fix * Basis.from_euler(GRIP_EULER) * (GRIP_SCALE * unit), hand_fix * GRIP_OFFSET * unit)

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
