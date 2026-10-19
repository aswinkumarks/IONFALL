extends GutTest
## First-person arms (FirstPersonView): the player's character cut to its
## arms; IK puts the right hand on the weapon's grip and the left on its
## fore-end, with the shoulders below the view.


func test_hands_reach_the_weapon() -> void:
	for style: String in CharacterRig.SELECTABLE:
		var v := FirstPersonView.new()
		add_child_autofree(v)
		v.set_character(style, Color.GREEN)
		var s := PlayerSimState.new()
		s.alive = true
		s.move_state = PlayerSimState.Move.GROUND
		s.reload = PackedInt32Array([0, 0, 0])
		for i in 3:
			v.update_view(Vector3.ZERO, 1.6, 0.0, 0.0, s, Loadouts.PULSE, 0.016)
			await wait_physics_frames(1)
		var rig := v._arms as ArmoredRig
		assert_not_null(rig, "%s has first-person arms" % style)
		if rig == null:
			continue
		var sk := rig._skeleton
		var cam := v.camera.global_transform.affine_inverse()
		var at := func(bone: String) -> Vector3:
			return cam * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin
		var chains := rig._arm_chains()
		var grip: Vector3 = cam * (v._models[Loadouts.PULSE.id] as Node3D).global_position
		gut.p("%s grip %s" % [style, grip])
		for c: Array in chains:
			gut.p("  %s %s / %s / %s" % [c[0], at.call(c[0]), at.call(c[1]), at.call(c[2])])
		assert_lt((at.call(chains[0][2]) as Vector3).distance_to(grip), 0.15, "%s: right hand at the grip" % style)
		for c: Array in chains:
			assert_lt((at.call(c[0]) as Vector3).y, -0.08, "%s: %s below the eye" % [style, c[0]])
