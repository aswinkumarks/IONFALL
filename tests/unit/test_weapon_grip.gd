extends GutTest
## Every weapon model's handle sits where the pulse rifle's does, so the
## rigs that hold a weapon by its model origin (ArmoredRig, MeshyRig,
## AstronautRig) hold each one by its handle.


func test_handles_line_up_with_the_pulse_rifle() -> void:
	for id: StringName in WeaponModels.MODELS:
		var w := WeaponModels.instantiate(id)
		var handle := (w.get_node("Grip") as Node3D).position + WeaponModels.grip_shift(w)
		assert_almost_eq(handle, WeaponModels.reference_grip(), Vector3.ONE * 1e-5, String(id))
		w.free()
	var pulse := WeaponModels.instantiate(&"pulse_rifle")
	assert_eq(WeaponModels.grip_shift(pulse), Vector3.ZERO, "the reference rifle doesn't move")
	pulse.free()


func test_rail_sniper_handle_is_in_the_hand() -> void:
	for style: String in ["armored", "sentinel"]:
		var held := {}
		for id: StringName in [&"pulse_rifle", &"rail_sniper"]:
			var rig := CharacterRig.create(style)
			add_child_autofree(rig)
			rig.setup(Color.WHITE)
			rig.set_weapon(id)
			var w: Node3D = rig._weapon_node
			held[id] = (w.get_node("Grip") as Node3D).global_position
		assert_lt((held[&"rail_sniper"] as Vector3).distance_to(held[&"pulse_rifle"]), 0.02, style)


## Third person (ArmoredRig.HoldWeapon): the right wrist by the handle and
## the left at the weapon's Support marker (or, out of reach, further back
## along the weapon), on every character and weapon, the right arm clear of
## the chest. The pistol's left hand cups the gun hand from below and in
## front, so its wrist sits off the handle-support line. (The meshes were
## checked for contact and clipping in Blender; these are the bone-level
## guards.)
## Bone poses are read after the modifiers run.
func test_both_hands_hold_the_weapon() -> void:
	for style: String in CharacterRig.SELECTABLE:
		for id: StringName in WeaponModels.MODELS:
			var rig := CharacterRig.create(style) as ArmoredRig
			add_child_autofree(rig)
			rig.setup(Color.WHITE)
			rig.set_weapon(id)
			var s := PlayerSimState.new()
			s.alive = true
			s.move_state = PlayerSimState.Move.GROUND
			var sk := rig._skeleton
			var wrists := {}
			var chains := rig._arm_chains()
			sk.skeleton_updated.connect(func() -> void:
				for k in 2:
					wrists[k] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(chains[k][2])).origin
				wrists["elbow"] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(chains[0][1])).origin
				wrists["chest"] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(rig._chest_bone())).origin)
			for i in 4:
				rig.animate(s, 0.016, 1.8)
				await wait_process_frames(1)
			var w: Node3D = rig._weapon_node
			var grip := (w.get_node("Grip") as Node3D).global_position
			var support := (w.get_node("Support") as Node3D).global_position
			assert_lt((wrists[0] as Vector3).distance_to(grip), 0.12, "%s %s: right hand at the handle" % [style, id])
			var right := rig.global_basis.x
			var chest: Vector3 = wrists["chest"]
			# Clear of the torso: the right hand out from the chest (a long gun
			# brought back puts it beside the chest rather than in front) and
			# the elbow out to the side, not folded into the armour.
			var off := (wrists[0] as Vector3) - chest
			assert_gt(Vector2(off.x, off.z).length(), 0.18, "%s %s: right hand clear of the chest" % [style, id])
			# Less for the pistol, held out in front with both hands.
			assert_gt(((wrists["elbow"] as Vector3) - chest).dot(right), 0.12 if ArmoredRig.HOLDS.has(id) else 0.14,
					"%s %s: right elbow out to the side" % [style, id])
			# At the support, or (out of reach) further back along the weapon but
			# still on the fore-end, well ahead of the handle.
			var on_gun := Geometry3D.get_closest_point_to_segment(wrists[1], grip, support)
			var slack := 0.12 if ArmoredRig.HOLDS.has(id) else 0.02
			assert_lt((wrists[1] as Vector3).distance_to(on_gun), slack, "%s %s: left hand on the weapon" % [style, id])
			var left := wrists[1] as Vector3
			assert_true(left.distance_to(support) < 0.1 or left.distance_to(grip) > 0.18,
					"%s %s: left hand near the support" % [style, id])


## First person (FirstPersonView): both hands reach the weapon on every
## character and weapon: the right wrist by the handle, the left at the
## fore-end's Support marker.
func test_first_person_hands_reach_the_weapon() -> void:
	var view := FirstPersonView.new()
	add_child_autofree(view)
	var s := PlayerSimState.new()
	s.alive = true
	s.move_state = PlayerSimState.Move.GROUND
	s.reload = PackedInt32Array([0, 0])
	s.weapons = PackedInt32Array([0, 0])
	for style: String in CharacterRig.SELECTABLE:
		view.set_character(style, Color.WHITE)
		for id: StringName in WeaponModels.MODELS:
			for i in 3:
				view.update_view(Vector3.ZERO, 1.6, 0.0, 0.0, s, Weapons.by_id(id), 1.0 / 60.0)
			var arms: ArmoredRig = view._arms
			var sk := arms._skeleton
			var chains := arms._arm_chains()
			var right := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(chains[0][2])).origin
			var left := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(chains[1][2])).origin
			var w: Node3D = view._models[id]
			var handle := (w.get_node("Grip") as Node3D).global_position
			assert_lt(right.distance_to(handle), 0.12, "%s %s: right hand at the handle" % [style, id])
			var support := (w.get_node("Support") as Node3D).global_position
			assert_lt(left.distance_to(support), 0.08, "%s %s: left hand at the fore-end" % [style, id])
			# The hands drawn smaller than the third-person ones.
			assert_lt(sk.get_bone_pose_scale(sk.find_bone(chains[0][2])).x, 0.9, "%s: smaller hands" % style)
