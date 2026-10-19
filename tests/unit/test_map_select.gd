extends GutTest
## Map choice (profile "map"): Play and Host use the saved map; the menu
## offers every playable map.

var _saved: Variant


func before_each() -> void:
	_saved = Settings.get_value("profile", "map")


func after_each() -> void:
	Settings.set_value("profile", "map", _saved)


func test_playable_maps_exist() -> void:
	for id: String in Maps.PLAYABLE:
		assert_true(Maps.has(id), id)
		assert_true(ResourceLoader.exists(Maps.LIST[id].gameplay), "%s gameplay" % id)
		assert_true(ResourceLoader.exists(Maps.LIST[id].presentation), "%s presentation" % id)


func test_match_uses_the_saved_map() -> void:
	Settings.set_value("profile", "map", "spire")
	assert_eq(MatchConfig.make(MatchConfig.Mode.OFFLINE, "Tester").map, "spire")
	Settings.set_value("profile", "map", "nonsense")
	assert_eq(MatchConfig.make(MatchConfig.Mode.OFFLINE, "Tester").map, Maps.DEFAULT, "unknown maps fall back")
