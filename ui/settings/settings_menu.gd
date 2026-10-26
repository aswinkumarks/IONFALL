class_name SettingsMenu
extends PanelContainer
## Settings screen (PLAN §3.13, §3.16): controls, video, audio, accessibility
## and key remapping. Built from SCHEMA; changes apply immediately (through
## Events.settings_changed) and are saved when the screen closes.

signal closed

## [section, key, label key, kind, min, max, step]; kind: slider, percent, check,
## choice ([..., choices] where choices is an Array or the name of a Settings
## method returning one; string choices are shown via "SETTING_VALUE_<X>" keys
## or as-is for resolutions), action ([..., method]: a button calling it).
const DESKTOP_ONLY := ["display_mode"]
const SCHEMA := {
	"SETTINGS_TAB_CONTROLS": [
		["input", "sensitivity_x", "SETTING_SENS_X", "slider", 0.1, 5.0, 0.05],
		["input", "sensitivity_y", "SETTING_SENS_Y", "slider", 0.1, 5.0, 0.05],
		["input", "touch_sensitivity", "SETTING_TOUCH_SENS", "slider", 0.1, 5.0, 0.05],
		["input", "invert_y", "SETTING_INVERT_Y", "check"],
		["input", "crouch_toggle", "SETTING_CROUCH_TOGGLE", "check"],
		["input", "sprint_toggle", "SETTING_SPRINT_TOGGLE", "check"],
		["input", "aim_toggle", "SETTING_AIM_TOGGLE", "check"],
		["input", "aim_assist", "SETTING_AIM_ASSIST", "check"],
		["input", "auto_fire", "SETTING_AUTO_FIRE", "check"],
		["input", "touch_layout", "SETTING_TOUCH_LAYOUT", "action", "open_touch_editor"],
	],
	"SETTINGS_TAB_VIDEO": [
		["video", "quality", "SETTING_QUALITY", "choice", ["low", "medium", "high", "ultra", "custom"]],
		["video", "display_mode", "SETTING_DISPLAY_MODE", "choice", ["windowed", "fullscreen", "exclusive"]],
		["video", "resolution", "SETTING_RESOLUTION", "choice", "resolution_options"],
		["video", "fov", "SETTING_FOV", "slider", 55.0, 85.0, 1.0],
		["video", "render_scale", "SETTING_RENDER_SCALE", "percent", 0.5, 1.0, 0.05],
		["video", "fps_cap", "SETTING_FPS_CAP", "choice", [30, 60, 90, 120]],
		["video", "shadows", "SETTING_SHADOWS", "check"],
		["video", "glow", "SETTING_GLOW", "check"],
		["video", "effects", "SETTING_EFFECTS", "percent", 0.25, 1.0, 0.05],
		["video", "anti_aliasing", "SETTING_ANTI_ALIASING", "choice", Settings.ANTI_ALIASING],
		["video", "adaptive_quality", "SETTING_ADAPTIVE_QUALITY", "check"],
	],
	"SETTINGS_TAB_GAME": [
		["profile", "browser_players", "SETTING_BROWSER_PLAYERS", "check"],
		["hud", "show_stats", "SETTING_SHOW_STATS", "check"],
	],
	"SETTINGS_TAB_AUDIO": [
		["audio", "master", "SETTING_VOL_MASTER", "percent", 0.0, 1.0, 0.05],
		["audio", "music", "SETTING_VOL_MUSIC", "percent", 0.0, 1.0, 0.05],
		["audio", "sfx", "SETTING_VOL_SFX", "percent", 0.0, 1.0, 0.05],
		["audio", "night_mode", "SETTING_NIGHT_MODE", "check"],
	],
	"SETTINGS_TAB_ACCESSIBILITY": [
		["accessibility", "hud_scale", "SETTING_HUD_SCALE", "percent", 0.8, 1.5, 0.05],
		["accessibility", "vignette", "SETTING_VIGNETTE", "percent", 0.0, 1.0, 0.05],
		["accessibility", "reduce_screen_shake", "SETTING_REDUCE_SHAKE", "check"],
		["accessibility", "reduce_flashes", "SETTING_REDUCE_FLASHES", "check"],
		["accessibility", "captions", "SETTING_CAPTIONS", "check"],
	],
}
## About tab credits: [what, who, license]. Names and licenses stay as they are.
const CREDITS := [
	["ABOUT_CREDIT_ICONS", "Delapouite, Lorc · game-icons.net", "CC BY 3.0"],
	["ABOUT_CREDIT_CHARACTERS", "Kenney (kenney.nl)", "CC0 1.0"],
	["ABOUT_CREDIT_ENVIRONMENT", "Quaternius (quaternius.com)", "CC0 1.0"],
	["ABOUT_CREDIT_FONTS", "Indian Type Foundry (Rajdhani), The Exo 2 Project Authors (Exo 2)", "SIL OFL 1.1"],
	["ABOUT_CREDIT_ENGINE", "Godot Engine contributors (godotengine.org)", "MIT"],
	["ABOUT_CREDIT_ONLINE", "Epic Online Services (Epic Games); EOSG plugin by Delano Lourenco", "EOS SDK License, MIT"],
]
const REPO_URL := "https://github.com/aswinkumarks/IONFALL"
const REMAPPABLE := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "crouch", "reload",
		"switch_weapon", "weapon_1", "weapon_2", "grenade", "melee", "interact", "scoreboard"]

var _listening_action: String = ""
var _resolution_button: OptionButton
var _tabs: TabContainer
var _controls: Dictionary = {}  ## "section/key" -> control, refreshed when a preset changes values
var _key_buttons: Dictionary = {}  ## action -> Button
var _touch_editor: TouchLayoutEditor


func _init() -> void:
	InputAdapter.apply_keymap()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiStyle.BG, 0.94)
	style.set_content_margin_all(32)
	style.content_margin_left = 72
	add_theme_stylebox_override("panel", style)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.add_child(UiStyle.label("SETTINGS_TITLE", &"HeaderLabel"))
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	for tab in SCHEMA:
		tabs.add_child(_build_tab(tab, SCHEMA[tab]))
	if not Platform.is_mobile():
		tabs.add_child(_build_keys_tab())
	tabs.add_child(_build_about_tab())
	Events.settings_changed.connect(_refresh_control)
	var done := UiStyle.menu_button("SETTINGS_DONE", &"PrimaryButton")
	done.alignment = HORIZONTAL_ALIGNMENT_CENTER
	done.custom_minimum_size.x = 260
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(close)
	root.add_child(done)
	visible = false


## The touch layout editor, over the settings screen.
func open_touch_editor() -> void:
	if _touch_editor == null:
		_touch_editor = TouchLayoutEditor.new()
		add_child(_touch_editor)
	_touch_editor.open()


func open() -> void:
	visible = true
	var tab := Platform.get_user_arg("--settings-tab")  # dev: screenshots of a tab
	if tab.is_valid_int():
		_tabs.current_tab = clampi(tab.to_int(), 0, _tabs.get_tab_count() - 1)


func close() -> void:
	_listening_action = ""
	Settings.save_settings()
	visible = false
	closed.emit()


func _build_tab(tab_name: String, rows: Array) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = tr(tab_name)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for row in rows:
		if row[1] in DESKTOP_ONLY and not Settings.has_window_modes():
			continue
		var label := Label.new()
		label.text = row[2]
		label.custom_minimum_size.x = 340
		grid.add_child(label)
		var control := _control_for(row)
		_controls[row[0] + "/" + row[1]] = control
		grid.add_child(control)
	return scroll


func _control_for(row: Array) -> Control:
	var section: String = row[0]
	var key: String = row[1]
	var value: Variant = Settings.get_value(section, key)
	match row[3]:
		"action":
			var button := UiStyle.menu_button("SETTINGS_EDIT")
			button.custom_minimum_size = Vector2(200, 44)
			button.pressed.connect(Callable(self, row[4]))
			return button
		"check":
			var check := CheckButton.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(on: bool) -> void: Settings.set_value(section, key, on))
			return check
		"choice":
			var opt := OptionButton.new()
			opt.custom_minimum_size.x = 260
			var choices: Array = row[4] if row[4] is Array else Settings.call(row[4])
			for c in choices:
				opt.add_item(_choice_label(c))
			opt.selected = maxi(choices.find(value if value is String else int(value)), 0)
			opt.item_selected.connect(func(i: int) -> void:
				Settings.set_value(section, key, choices[i])
				if key == "display_mode":
					_rebuild_resolution_choices())
			if key == "resolution":
				_resolution_button = opt
			return opt
		_:
			var box := HBoxContainer.new()
			box.add_theme_constant_override("separation", 12)
			var slider := HSlider.new()
			slider.min_value = row[4]
			slider.max_value = row[5]
			slider.step = row[6]
			slider.value = float(value)
			slider.custom_minimum_size = Vector2(360, 40)
			var readout := Label.new()
			readout.custom_minimum_size.x = 70
			var percent: bool = row[3] == "percent"
			var show := func(v: float) -> void:
				readout.text = "%d%%" % roundi(v * 100.0) if percent else ("%.2f" % v if row[6] < 1.0 else "%d" % v)
			show.call(slider.value)
			box.set_meta("show", show)
			slider.value_changed.connect(func(v: float) -> void:
				show.call(v)
				Settings.set_value(section, key, v))
			box.add_child(slider)
			box.add_child(readout)
			return box


## Version, credits (CC BY assets need visible credit) and licenses.
func _build_about_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = tr("SETTINGS_TAB_ABOUT")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	# Keep the licence column clear of the scroll bar.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_child(box)
	scroll.add_child(margin)
	box.add_child(UiStyle.label("MENU_TITLE", &"HeaderLabel"))
	box.add_child(UiStyle.label(tr("ABOUT_VERSION") % BuildInfo.display_string(), &"DimLabel"))
	var heading := UiStyle.label("ABOUT_CREDITS")
	heading.add_theme_font_size_override("font_size", 26)
	box.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for c: Array in CREDITS:
		grid.add_child(UiStyle.label(c[0]))
		var who := UiStyle.label(c[1], &"DimLabel")
		who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		who.autowrap_mode = TextServer.AUTOWRAP_WORD
		who.custom_minimum_size.x = 380
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(who)
		var license := UiStyle.label(c[2], &"DimLabel")
		license.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		grid.add_child(license)
	var note := UiStyle.label("ABOUT_LICENSE", &"DimLabel")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(note)
	var link := UiStyle.menu_button("ABOUT_SOURCE")
	link.custom_minimum_size = Vector2(320, 44)
	link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	link.pressed.connect(func() -> void: OS.shell_open(REPO_URL))
	box.add_child(link)
	return scroll


func _build_keys_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = tr("SETTINGS_TAB_KEYS")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for action: String in REMAPPABLE:
		var label := Label.new()
		label.text = "ACTION_" + action.to_upper()
		label.custom_minimum_size.x = 340
		grid.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(200, 40)
		button.text = InputAdapter.key_name(action)
		button.pressed.connect(func() -> void:
			_listening_action = action
			button.text = tr("SETTINGS_PRESS_KEY"))
		grid.add_child(button)
		_key_buttons[action] = button
	var reset := Button.new()
	reset.text = "SETTINGS_RESET_KEYS"
	reset.pressed.connect(func() -> void:
		Settings.set_value("input", "keymap", {})
		InputAdapter.apply_keymap()
		_refresh_keys())
	grid.add_child(reset)
	return scroll


func _input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		# Back / Escape closes the screen (the touch layout editor first).
		if visible and event.is_action_pressed("ui_cancel") \
				and not (_touch_editor != null and _touch_editor.visible):
			get_viewport().set_input_as_handled()
			close()
		return
	if not event is InputEventKey or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if event.keycode != KEY_ESCAPE:
		var keymap: Dictionary = (Settings.get_value("input", "keymap") as Dictionary).duplicate()
		keymap[_listening_action] = event.physical_keycode
		Settings.set_value("input", "keymap", keymap)
		InputAdapter.apply_keymap()
	_listening_action = ""
	_refresh_keys()


func _refresh_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = InputAdapter.key_name(action)


static func _choice_label(c: Variant) -> String:
	if c is String:
		var r := Settings.parse_resolution(c)
		if r != Vector2i.ZERO:
			return "%d × %d" % [r.x, r.y]
		return TranslationServer.translate("SETTING_VALUE_" + String(c).to_upper())
	return str(c)


## Windowed and fullscreen offer different resolutions (16:9 vs the screen's).
func _rebuild_resolution_choices() -> void:
	if _resolution_button == null:
		return
	var choices: Array = Settings.resolution_options()
	_resolution_button.clear()
	for c in choices:
		_resolution_button.add_item(_choice_label(c))
	var current: String = Settings.get_value("video", "resolution")
	if not choices.has(current):
		Settings.set_value("video", "resolution", "native")
		current = "native"
	_resolution_button.selected = maxi(choices.find(current), 0)
	# Re-bind the handler to the new list.
	for conn in _resolution_button.item_selected.get_connections():
		_resolution_button.item_selected.disconnect(conn.callable)
	_resolution_button.item_selected.connect(func(i: int) -> void: Settings.set_value("video", "resolution", choices[i]))


## Keeps a control in step when its value changes elsewhere (presets).
func _refresh_control(section: String, key: String, value: Variant) -> void:
	var c: Control = _controls.get(section + "/" + key)
	if c == null:
		return
	if c is CheckButton:
		(c as CheckButton).set_pressed_no_signal(bool(value))
	elif c is OptionButton:
		var opt := c as OptionButton
		for i in opt.item_count:
			if opt.get_item_text(i) == _choice_label(value):
				opt.select(i)
	elif c is HBoxContainer:
		var slider := c.get_child(0) as HSlider
		if slider != null and not is_equal_approx(slider.value, float(value)):
			slider.set_value_no_signal(float(value))
			(c.get_meta("show") as Callable).call(float(value))
