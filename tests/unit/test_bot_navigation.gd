extends GutTest
## Runtime navmesh + generated traversal links on the test arena (PLAN §2.7).

const T := BotNavigation.Traversal

var nav: BotNavigation


func before_all() -> void:
	var arena := SimHarness.make_arena()
	add_child(arena)
	await wait_physics_frames(2)
	nav = BotNavigation.new()
	add_child(nav)
	await nav.build(arena)


func after_all() -> void:
	nav.get_parent().get_child(0).queue_free()
	nav.queue_free()


func _traversals(path: Array) -> Array:
	return path.map(func(p: Array) -> int: return p[1]).filter(func(t: int) -> bool: return t != T.NONE)


func test_navmesh_baked_with_links() -> void:
	assert_gt(nav.navmesh.get_polygon_count(), 10)
	var kinds := {}
	for l in nav.links:
		kinds[l.get_meta("traversal")] = true
	gut.p("links: %d" % nav.links.size())
	assert_true(kinds.has(T.JUMP_MANTLE), "mantle links found")
	assert_true(kinds.has(T.DROP), "drop links found")


func test_path_onto_a_mantle_ledge_uses_a_climb() -> void:
	# 1.5 m ledge at (-11, 1.5, 12): unreachable without climbing.
	var path := nav.path(Vector3(-11, 0, 16), Vector3(-11, 1.5, 12))
	assert_false(path.is_empty())
	assert_almost_eq(path[-1][0].y, 1.5 + 0.4, 0.4, "ends on the ledge (the navmesh floats ~0.5 m up)")
	assert_has(_traversals(path), T.JUMP_MANTLE)


func test_path_to_the_tall_ledge_needs_a_double_jump() -> void:
	var path := nav.path(Vector3(-5, 0, 16), Vector3(-5, 3.2, 12))
	assert_false(path.is_empty())
	assert_almost_eq(path[-1][0].y, 3.2 + 0.4, 0.4)
	assert_has(_traversals(path), T.DOUBLE_JUMP_MANTLE)


func test_ramps_are_walked_not_climbed() -> void:
	# Side walkway (top 2.5 m) via its ramp at z = 16: no traversal needed
	# from the ramp foot.
	var path := nav.path(Vector3(17.5, 0, 19.5), Vector3(17.5, 2.5, 0))
	assert_false(path.is_empty())
	assert_almost_eq(path[-1][0].y, 2.5 + 0.4, 0.4)


func test_random_points_are_on_the_navmesh() -> void:
	for i in 20:
		var p := nav.random_point()
		assert_lt(p.distance_to(nav.closest_point(p)), 0.05)
