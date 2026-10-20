extends GutTest
## Every playable map's pickup spots (PLAN §2.3) stand on solid floor with
## headroom to walk over them.


func test_spots_on_floor() -> void:
	for id: String in Maps.PLAYABLE:
		var gameplay := Maps.gameplay(id)
		add_child_autofree(gameplay)
		await wait_physics_frames(2)
		var space := gameplay.get_world_3d().direct_space_state
		var spots: Array = gameplay.pickup_spots()
		assert_gt(spots.size(), 0, "%s has pickups" % id)
		for spot: Dictionary in spots:
			var pos: Vector3 = spot.position
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP, pos + Vector3.DOWN * 0.5, Sim.LAYER_WORLD))
			assert_false(down.is_empty(), "%s %s: floor below %s" % [id, spot.weapon, pos])
			if not down.is_empty():
				assert_almost_eq(down.position.y, pos.y, 0.15, "%s %s: on the floor" % [id, spot.weapon])
			var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.1, pos + Vector3.UP * 2.0, Sim.LAYER_WORLD))
			assert_true(up.is_empty(), "%s %s: headroom at %s" % [id, spot.weapon, pos])
			assert_true(spot.weapon == &"grenade" or Weapons.by_id(spot.weapon) != null)
		gameplay.free()
