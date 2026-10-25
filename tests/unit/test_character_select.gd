extends GutTest
## Player customisation (profile "name", "character", "color"): the panel
## cycles and saves, the picks travel in the handshake and roster, and the
## visual uses them.

const KEYS := ["name", "character", "color"]

var _saved := {}


var _saved_xp: int = 0


## Everything unlocked (test_unlocks covers the locks).
func before_each() -> void:
	for k: String in KEYS:
		_saved[k] = Settings.get_value("profile", k)
	_saved_xp = Profile.data.data.xp
	Profile.data.data.xp = 1000000


func after_each() -> void:
	for k: String in KEYS:
		Settings.set_value("profile", k, _saved[k])
	Settings.save_settings()
	Profile.data.data.xp = _saved_xp


func test_catalog() -> void:
	assert_eq(CharacterRig.SELECTABLE.size(), CharacterRig.SELECTABLE_KEYS.size())
	for style: String in CharacterRig.SELECTABLE:
		assert_has(CharacterRig.STYLES, style)
	assert_eq(CharacterRig.selectable_index("nope"), 0, "unknown falls back to the default")
	assert_eq(CharacterRig.selectable_style(CharacterRig.SELECTABLE.size() + 1), CharacterRig.SELECTABLE[1], "indices wrap")


func test_panel_picks_and_saves() -> void:
	var profile := ProfilePanel.new()
	add_child_autofree(profile)
	var panel := profile.customize
	Settings.set_value("profile", "character", CharacterRig.SELECTABLE[0])
	Settings.set_value("profile", "color", 0)
	profile.open("Tester")
	assert_eq(profile._tabs.current_tab, ProfilePanel.Tab.CUSTOMIZE, "opens on Customise")
	panel._pick_character(1)
	assert_eq(Settings.get_value("profile", "character"), CharacterRig.SELECTABLE[1])
	assert_eq(MatchConfig.profile_character(), 1)
	panel._pick_character(-1)
	assert_eq(Settings.get_value("profile", "character"), CharacterRig.SELECTABLE[-1], "wraps backwards")
	assert_eq(panel.preview_color(), UiStyle.ACCENT, "auto previews in the accent")
	panel._pick_color(3)
	assert_eq(MatchConfig.profile_color(), 3)
	assert_eq(panel.preview_color(), PlayerVisual.PALETTE[3])
	panel._name_edit.text = "  Nova\u0007  "
	profile.close()
	assert_false(profile.visible)
	assert_eq(MatchConfig.profile_name(), "Nova", "callsign sanitised and saved")


func test_handshake_and_roster_carry_the_pick() -> void:
	var hello := Protocol.decode_hello(Protocol.encode_hello(BuildInfo.compat_hash, "b", "u", "Name", 0, 2, 5))
	assert_eq(hello.character, 2)
	assert_eq(hello.color, 5)
	var roster := Protocol.decode_roster(Protocol.encode_roster(7, [{"id": 3, "name": "A", "bot": false, "character": 1,
			"color": 4, "score": 0}]))
	assert_eq(roster.players[0].character, 1)
	assert_eq(roster.players[0].color, 4)


func test_colors() -> void:
	assert_eq(PlayerVisual.color_for(5, 2), PlayerVisual.PALETTE[2])
	assert_eq(PlayerVisual.color_for(5, 0), PlayerVisual.AUTO_COLORS[1], "auto: by player id")
	assert_eq(PlayerVisual.color_for(5, 99), PlayerVisual.AUTO_COLORS[1], "out of range: auto")
	assert_eq(PlayerVisual.color_for(5, 2, true), PlayerVisual.BOT_COLOR)


func test_visual_uses_the_players_character() -> void:
	var v := PlayerVisual.new()
	add_child_autofree(v)
	v.setup("A", false, Color.CYAN, 0, CharacterRig.selectable_style(1))
	assert_eq(v.rig_style, CharacterRig.SELECTABLE[1])
	assert_true(v.rig is MeshyRig and (v.rig as MeshyRig).character == "vanguard")
