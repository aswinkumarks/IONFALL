extends GutTest
## Map 2, Halcyon Spire: the generated presentation matches
## the layout, spawns are valid, and bots can reach every spawn.

var arena: Node3D
var nav: BotNavigation


func before_all() -> void:
	arena = Maps.gameplay("spire")
	add_child(arena)
	await wait_physics_frames(2)
	nav = BotNavigation.new()
	add_child(nav)
	await nav.build(arena)


func after_all() -> void:
	arena.queue_free()
	nav.queue_free()


func test_presentation_is_built_from_the_current_layout() -> void:
	var scene: PackedScene = load(Maps.LIST.spire.presentation)
	var state := scene.get_state()
	var built := ""
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == "metadata/layout_hash":
			built = state.get_node_property_value(0, i)
	assert_eq(built, SpireLayout.layout_hash(), "rebuild with tools/build_spire.sh after layout changes")


func test_presentation_has_a_baked_lightmap() -> void:
	var p := Maps.presentation("spire")
	var lm: LightmapGI = p.find_children("*", "LightmapGI", true, false)[0]
	assert_not_null(lm.light_data, "baked")
	assert_eq(lm.shadowmask_mode, LightmapGIData.SHADOWMASK_MODE_OVERLAY)
	p.free()


func test_spawns_stand_on_free_ground() -> void:
	var space := arena.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	for t: Transform3D in SpireLayout.spawn_points():
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = capsule
		q.transform = Transform3D(Basis(), t.origin + Vector3(0, 1.0, 0))
		q.collision_mask = Sim.LAYER_WORLD
		assert_eq(space.intersect_shape(q).size(), 0, "spawn %s is clear" % t.origin)
		var ray := PhysicsRayQueryParameters3D.create(t.origin + Vector3.UP * 0.5, t.origin + Vector3.DOWN, Sim.LAYER_WORLD)
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty(), "spawn %s has ground" % t.origin)
		if not hit.is_empty():
			assert_almost_eq(hit.position.y, t.origin.y, 0.15)


func test_every_spawn_reaches_every_other() -> void:
	var spawns := SpireLayout.spawn_points()
	for a in spawns:
		for b in spawns:
			if a == b:
				continue
			var path := nav.path(a.origin, b.origin)
			assert_false(path.is_empty(), "path %s -> %s" % [a.origin, b.origin])
			if not path.is_empty():
				assert_lt(path[-1][0].distance_to(b.origin), 1.5, "path %s -> %s arrives" % [a.origin, b.origin])


func test_plaza_and_walkways_are_reachable() -> void:
	for target: Vector3 in [Vector3(0, SpireLayout.DECK, 4), Vector3(-10, SpireLayout.DECK, 24), Vector3(16, SpireLayout.DECK, 0)]:
		var path := nav.path(Vector3(0, 0, 14), target)
		assert_false(path.is_empty(), "path to %s" % target)
		if not path.is_empty():
			assert_almost_eq(path[-1][0].y, target.y + 0.4, 0.5, "arrives on the deck at %s" % target)
