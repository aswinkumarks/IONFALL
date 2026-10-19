class_name SettingsMenu
extends PanelContainer
## Settings screen (PLAN §3.13, §3.16): controls, video, audio, accessibility
## and key remapping. Built from SCHEMA; changes apply immediately (through
## Events.settings_changed) and are saved when the screen closes.

signal closed

## [section, key, label key, kind, min, max, step]; kind: slider, percent, check, choice.
const SCHEMA := {
	"SETTINGS_TAB_CONTROLS": [
		["input", "sensitivity_x", "SETTING_SENS_X", "slider", 0.1, 5.0, 0.05],
		["input", "sensitivity_y", "SETTING_SENS_Y", "slider", 0.1, 5.0, 0.05],
		["input", "touch_sensitivity", "SETTING_TOUCH_SENS", "slider", 0.1, 5.0, 0.05],
		["input", "invert_y", "SETTING_INVERT_Y", "check"],
		["input", "crouch_toggle", "SETTING_CROUCH_TOGGLE", "check"],
		["input", "sprint_toggle", "SETTING_SPRINT_TOGGLE", "check"],
		["input", "aim_toggle", "SETTING_AIM_TOGGLE", "check"],
	],
	"SETTINGS_TAB_VIDEO": [
		["video", "fov", "SETTING_FOV", "slider", 55.0, 85.0, 1.0],
		["video", "render_scale", "SETTING_RENDER_SCALE", "percent", 0.5, 1.0, 0.05],
		["video", "fps_cap", "SETTING_FPS_CAP", "choice", [30, 60, 90, 120]],
		["video", "shadows", "SETTING_SHADOWS", "check"],
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
		["accessibility", "captions", "SETTING_CAPTIONS", "check"],
	],
}
const REMAPPABLE := ["move_forward", "move_back", "move_left", "move_right", "jump", "sprint", "crouch", "reload",
		"switch_weapon", "weapon_1", "weapon_2", "weapon_3", "scoreboard"]

var _listening_action: String = ""
var _key_buttons: Dictionary = {}  ## action -> Button


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
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	for tab in SCHEMA:
		tabs.add_child(_build_tab(tab, SCHEMA[tab]))
	if not Platform.is_mobile():
		tabs.add_child(_build_keys_tab())
	var done := UiStyle.menu_button("SETTINGS_DONE", &"PrimaryButton")
	done.alignment = HORIZONTAL_ALIGNMENT_CENTER
	done.custom_minimum_size.x = 260
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(close)
	root.add_child(done)
	visible = false


func open() -> void:
	visible = true


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
		var label := Label.new()
		label.text = row[2]
		label.custom_minimum_size.x = 340
		grid.add_child(label)
		grid.add_child(_control_for(row))
	return scroll


func _control_for(row: Array) -> Control:
	var section: String = row[0]
	var key: String = row[1]
	var value: Variant = Settings.get_value(section, key)
	match row[3]:
		"check":
			var check := CheckButton.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(on: bool) -> void: Settings.set_value(section, key, on))
			return check
		"choice":
			var opt := OptionButton.new()
			var choices: Array = row[4]
			for c in choices:
				opt.add_item(str(c))
			opt.selected = maxi(choices.find(int(value)), 0)
			opt.item_selected.connect(func(i: int) -> void: Settings.set_value(section, key, choices[i]))
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
			slider.value_changed.connect(func(v: float) -> void:
				show.call(v)
				Settings.set_value(section, key, v))
			box.add_child(slider)
			box.add_child(readout)
			return box


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
	if _listening_action.is_empty() or not event is InputEventKey or not event.pressed:
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
