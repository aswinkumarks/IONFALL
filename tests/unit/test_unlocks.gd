extends GutTest
## Cosmetic unlocks by level (PLAN §3.13).


func test_schedule() -> void:
	assert_eq(Unlocks.character_level("sentinel"), 1, "the default is always free")
	assert_eq(Unlocks.color_level(0), 1, "auto colour is free")
	var unlocked := Unlocks.unlocked_between(1, 2)
	assert_true("CHAR_VANGUARD" in unlocked)
	assert_true("UNLOCK_COLOR_5" in unlocked)
	assert_eq(Unlocks.unlocked_between(8, 9).size(), 0)
	var all := Unlocks.unlocked_between(0, 99)
	assert_eq(all.size(), CharacterRig.SELECTABLE.size() + PlayerVisual.PALETTE.size())


func test_locked_picks_fall_back() -> void:
	var saved_char: Variant = Settings.get_value("profile", "character")
	var saved_color: Variant = Settings.get_value("profile", "color")
	var saved_data: Dictionary = Profile.data.data.duplicate(true)
	Profile.data = ProfileData.fresh()  # level 1
	Settings.set_value("profile", "character", "operative")
	Settings.set_value("profile", "color", 8)
	assert_eq(MatchConfig.profile_character(), 0, "locked character: the default")
	assert_eq(MatchConfig.profile_color(), 0, "locked colour: auto")
	Profile.data.data = saved_data
	Settings.set_value("profile", "character", saved_char)
	Settings.set_value("profile", "color", saved_color)
