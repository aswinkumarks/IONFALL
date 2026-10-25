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
## the left at the weapon's Support marker, on every character and weapon.
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
					wrists[k] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(chains[k][2])).origin)
			for i in 4:
				rig.animate(s, 0.016, 1.8)
				await wait_process_frames(1)
			var w: Node3D = rig._weapon_node
			var grip := (w.get_node("Grip") as Node3D).global_position
			var support := (w.get_node("Support") as Node3D).global_position
			assert_lt((wrists[0] as Vector3).distance_to(grip), 0.12, "%s %s: right hand at the handle" % [style, id])
			assert_lt((wrists[1] as Vector3).distance_to(support), 0.07, "%s %s: left hand at the support" % [style, id])
