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
