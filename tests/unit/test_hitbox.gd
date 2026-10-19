extends GutTest

const Stance := PlayerSimState.Stance


func test_ray_aimed_at_head_centre_hits_head_in_every_stance() -> void:
	for stance in [Stance.STAND, Stance.CROUCH, Stance.SLIDE]:
		var head: Array = Hitbox.SHAPES[stance][0]
		var from := Vector3(0, head[1], 10)
		var hit := Hitbox.intersect(Vector3.ZERO, stance, from, Vector3.FORWARD, 100.0)
		assert_not_null(hit)
		assert_eq(hit.part, Hitbox.Part.HEAD, "stance %d" % stance)


func test_torso_and_legs_heights() -> void:
	var hit := Hitbox.intersect(Vector3.ZERO, Stance.STAND, Vector3(0, 1.15, 10), Vector3.FORWARD, 100.0)
	assert_eq(hit.part, Hitbox.Part.TORSO)
	hit = Hitbox.intersect(Vector3.ZERO, Stance.STAND, Vector3(0, 0.5, 10), Vector3.FORWARD, 100.0)
	assert_eq(hit.part, Hitbox.Part.LEGS)


func test_miss_beside_and_over() -> void:
	assert_null(Hitbox.intersect(Vector3.ZERO, Stance.STAND, Vector3(0.6, 1.2, 10), Vector3.FORWARD, 100.0))
	assert_null(Hitbox.intersect(Vector3.ZERO, Stance.STAND, Vector3(0, 1.85, 10), Vector3.FORWARD, 100.0))


func test_max_distance_limits_hits() -> void:
	assert_null(Hitbox.intersect(Vector3.ZERO, Stance.STAND, Vector3(0, 1.2, 10), Vector3.FORWARD, 5.0),
			"a wall 5 m away blocks the shot")


func test_crouch_is_lower_than_stand() -> void:
	assert_null(Hitbox.intersect(Vector3.ZERO, Stance.CROUCH, Vector3(0, 1.5, 10), Vector3.FORWARD, 100.0),
			"standing-head height misses a crouched player")
