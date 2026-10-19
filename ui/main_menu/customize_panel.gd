class_name CustomizePanel
extends Control
## Player customisation: callsign, colour (PlayerVisual.PALETTE) and
## playable character (CharacterRig.SELECTABLE), with a turning 3D preview
## of the pick holding the rifle. Colour and character save to the profile
## as they change; the callsign saves on Done. All three are sent when
## joining a match. Full-screen overlay in the menu's style; left/right
## (keys, pad) cycle the character unless the callsign field has focus.

signal closed

const SWATCH_SIZE := Vector2(64, 44)

var _character: int = 0
var _color: int = 0
var _viewport := SubViewport.new()
var _stage := Node3D.new()
var _rig: CharacterRig
var _idle := PlayerSimState.new()
var _name_edit := LineEdit.new()
var _swatches: Array[Button] = []
var _character_buttons: Array[Button] = []
var _title: Label
var _blurb: Label
var _done: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(UiStyle.BG, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	column.add_child(UiStyle.label("MENU_CUSTOMIZE", &"HeaderLabel"))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 32)
	column.add_child(body)

	# Left: the preview, with the character's name and blurb under it.
	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_stretch_ratio = 1.4
	body.add_child(preview)
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(0, 200)
	preview.add_child(frame)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	frame.add_child(_viewport)
	_viewport.add_child(_stage)
	_build_stage()
	_title = UiStyle.label("", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_size_override("font_size", 36)
	preview.add_child(_title)
	_blurb = UiStyle.label("", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	preview.add_child(_blurb)

	# Right: callsign, colour and character in a card.
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	scroll.add_child(side)
	side.add_child(UiStyle.label("CUSTOMIZE_CALLSIGN", &"DimLabel"))
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "MENU_NAME_PLACEHOLDER"
	_name_edit.custom_minimum_size.y = 52
	_name_edit.text_submitted.connect(func(_t: String) -> void: _done.grab_focus())
	side.add_child(_name_edit)
	side.add_child(_gap())
	side.add_child(UiStyle.label("CUSTOMIZE_COLOR", &"DimLabel"))
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 8)
	swatches.add_theme_constant_override("v_separation", 8)
	side.add_child(swatches)
	for i in PlayerVisual.PALETTE.size():
		var b := Button.new()
		b.custom_minimum_size = SWATCH_SIZE
		b.text = "CUSTOMIZE_AUTO" if i == 0 else ""
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_pick_color.bind(i))
		swatches.add_child(b)
		_swatches.append(b)
	side.add_child(_gap())
	side.add_child(UiStyle.label("CUSTOMIZE_CHARACTER", &"DimLabel"))
	for i in CharacterRig.SELECTABLE.size():
		var b := UiStyle.menu_button(CharacterRig.SELECTABLE_KEYS[i])
		b.toggle_mode = true
		b.custom_minimum_size.y = 50
		b.pressed.connect(_pick_character.bind(i))
		side.add_child(b)
		_character_buttons.append(b)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(bottom)
	_done = UiStyle.menu_button("MENU_DONE", &"PrimaryButton")
	_done.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done.custom_minimum_size.x = 240
	_done.pressed.connect(close)
	bottom.add_child(_done)
	_idle.alive = true
	_idle.move_state = PlayerSimState.Move.GROUND
	visible = false
	set_process(false)


static func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 6
	return c


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.52, 0.62)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_stage.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.2
	_stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.2, 1.9, -1.4)
	rim.light_color = UiStyle.ACCENT
	rim.light_energy = 2.5
	rim.omni_range = 4.0
	_stage.add_child(rim)
	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.transform = Transform3D.IDENTITY.looking_at(Vector3(0, -0.18, -3.9)).translated(Vector3(0, 1.1, 3.9))
	camera.current = true
	_stage.add_child(camera)


## `player_name`: the callsign currently in the menu's name field.
func open(player_name: String) -> void:
	_name_edit.text = player_name
	_character = MatchConfig.profile_character()
	_color = MatchConfig.profile_color()
	_refresh()
	visible = true
	set_process(true)
	_done.grab_focus()


func close() -> void:
	var n := ServerSession.sanitize_name(_name_edit.text)
	Settings.set_value("profile", "name", n)
	Settings.save_settings()
	visible = false
	set_process(false)
	if _rig != null:
		_rig.queue_free()
		_rig = null
	closed.emit()


func _pick_character(index: int) -> void:
	_character = posmod(index, CharacterRig.SELECTABLE.size())
	Settings.set_value("profile", "character", CharacterRig.SELECTABLE[_character])
	Settings.save_settings()
	_refresh()


func _pick_color(index: int) -> void:
	_color = index
	Settings.set_value("profile", "color", _color)
	Settings.save_settings()
	_refresh()


## The preview colour: the pick, or the menu accent for "auto".
func preview_color() -> Color:
	return PlayerVisual.PALETTE[_color] if _color > 0 else UiStyle.ACCENT


func _refresh() -> void:
	var yaw := _rig.rotation.y if _rig != null else 0.5
	if _rig != null:
		_rig.queue_free()
	_rig = CharacterRig.create(CharacterRig.SELECTABLE[_character])
	_stage.add_child(_rig)
	_rig.setup(preview_color())
	_rig.set_weapon(Loadouts.PULSE.id)
	_rig.rotation.y = yaw
	var key: String = CharacterRig.SELECTABLE_KEYS[_character]
	_title.text = tr(key).to_upper()
	_blurb.text = tr(key + "_DESC")
	for i in _character_buttons.size():
		_character_buttons[i].set_pressed_no_signal(i == _character)
	for i in _swatches.size():
		_style_swatch(_swatches[i], i)


func _style_swatch(b: Button, index: int) -> void:
	var fill: Color = UiStyle.PANEL if index == 0 else PlayerVisual.PALETTE[index]
	var selected := index == _color
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill.lightened(0.15) if state == "hover" else fill
		sb.set_corner_radius_all(6)
		var ring: bool = selected or state == "focus"
		sb.set_border_width_all(3 if ring else 1)
		sb.border_color = UiStyle.TEXT if selected else UiStyle.ACCENT if state == "focus" else UiStyle.LINE
		if state == "focus" and not selected:
			sb.draw_center = false
		b.add_theme_stylebox_override(state, sb)


func _process(delta: float) -> void:
	if _rig != null:
		_rig.rotation.y += delta * 0.45
		_rig.animate(_idle, delta, 1.8)


## _input, not _unhandled_input: focused buttons would eat left/right.
func _input(event: InputEvent) -> void:
	if not visible or get_viewport().gui_get_focus_owner() == _name_edit:
		return
	if event.is_action_pressed("ui_left"):
		_pick_character(_character - 1)
	elif event.is_action_pressed("ui_right"):
		_pick_character(_character + 1)
	elif event.is_action_pressed("ui_cancel"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()
