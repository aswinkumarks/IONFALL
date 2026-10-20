extends GutTest
## Character rigs (PLAN §4, docs/decisions/0003): every style builds and
## animates through all movement states without errors.


func _state(move: PlayerSimState.Move, velocity: Vector3, yaw: float = 0.0) -> PlayerSimState:
	var s := PlayerSimState.new()
	s.move_state = move
	s.velocity = velocity
	s.yaw = yaw
	s.alive = true
	return s


func test_every_style_animates() -> void:
	for style: String in CharacterRig.STYLES:
		var rig := CharacterRig.create(style)
		add_child_autofree(rig)
		rig.setup(Color.ORANGE)
		for s in [_state(PlayerSimState.Move.GROUND, Vector3.ZERO), _state(PlayerSimState.Move.GROUND, Vector3(0, 0, -6)),
				_state(PlayerSimState.Move.GROUND, Vector3(0, 0, 4)), _state(PlayerSimState.Move.GROUND, Vector3(5, 0, 0), 1.0),
				_state(PlayerSimState.Move.AIR, Vector3(0, 3, -2))]:
			rig.animate(s, 1.0 / 60.0, 1.8)
		rig.animate(_state(PlayerSimState.Move.GROUND, Vector3.ZERO), 1.0 / 60.0, 1.2)
		rig.set_glow(0.5)
		assert_true(rig.get_child_count() > 0, "%s built a body" % style)


func test_skinned_clips() -> void:
	var rig := SkinnedRig.new()
	add_child_autofree(rig)
	rig.setup(Color.CYAN)
	var anim: AnimationPlayer = rig.find_children("*", "AnimationPlayer", true, false)[0]
	assert_eq(Array(SkinnedRig.library().get_animation_list()).size(), 3)
	rig.animate(_state(PlayerSimState.Move.GROUND, Vector3(0, 0, -5)), 0.016, 1.8)
	assert_eq(anim.current_animation, "run")
	assert_gt(anim.speed_scale, 0.0, "running forward plays forward")
	rig.animate(_state(PlayerSimState.Move.GROUND, Vector3(0, 0, 5)), 0.016, 1.8)
	assert_lt(anim.speed_scale, 0.0, "backpedal plays the run clip backwards")
	rig.animate(_state(PlayerSimState.Move.AIR, Vector3(0, 2, 0)), 0.016, 1.8)
	assert_eq(anim.current_animation, "jump")
	rig.animate(_state(PlayerSimState.Move.GROUND, Vector3.ZERO), 0.016, 1.8)
	assert_eq(anim.current_animation, "idle")


func test_sentinel_retarget() -> void:
	var rig := SentinelRig.new()
	add_child_autofree(rig)
	rig.setup(Color.ORANGE)
	var lib: AnimationLibrary = SentinelRig._sentinel_library
	for clip: String in ArmoredRig.CLIPS:
		assert_true(lib.has_animation(clip), clip)
	var idle := lib.get_animation("Idle")
	assert_eq(idle.get_track_count(), SentinelRig.BONE_MAP.size() + 1, "a rotation per mapped bone plus hips position")
	var hips: Vector3 = idle.track_get_key_value(idle.get_track_count() - 1, 0)
	assert_between(hips.y, 85.0, 110.0, "hips stay near the model's rest height (cm)")
	rig.set_weapon(Loadouts.PISTOL.id)
	assert_almost_eq(SentinelRig._grip.basis.get_scale().x, SentinelRig.SENTINEL_GRIP_SCALE * 100.0, 0.5, "grip scaled into centimetres")


## The Sentinel's finger bones (tools/rig_sentinel_fingers.gd): three per
## finger and thumb on both hands, skinned, and curled towards the palm.
func test_sentinel_fingers() -> void:
	var rig := SentinelRig.new()
	add_child_autofree(rig)
	rig.setup(Color.ORANGE)
	var sk := rig._skeleton
	for side: String in ["Right", "Left"]:
		for finger: String in SentinelRig.GRIP_CURL:
			for k in 3:
				var bone := sk.find_bone("%sHand%s%d" % [side, finger, k + 1])
				assert_gt(bone, -1, "%s %s %d exists" % [side, finger, k + 1])
				if bone >= 0:
					assert_ne(sk.get_bone_pose_rotation(bone), Quaternion.IDENTITY, "%s %s %d curled" % [side, finger, k + 1])
	var mesh: ArrayMesh = load(SentinelRig.FINGER_MESH)
	var skin: Skin = load(SentinelRig.FINGER_SKIN)
	var arrays := mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var on_fingers := {}
	for i in weights.size() / 4:
		var total := 0.0
		for k in 4:
			total += weights[i * 4 + k]
			if weights[i * 4 + k] > 0.5:
				on_fingers[String(skin.get_bind_name(bones[i * 4 + k]))] = true
		if absf(total - 1.0) > 0.01:
			fail_test("vertex %d weights sum to %f" % [i, total])
			return
	for name: String in ["RightHandIndex3", "RightHandPinky2", "RightHandThumb3", "LeftHandMiddle3"]:
		assert_true(on_fingers.has(name), "%s moves vertices" % name)
