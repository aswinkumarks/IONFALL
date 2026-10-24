class_name TouchLayoutEditor
extends Control
## Touch layout editor (PLAN §3.11): drag the buttons, resize the selected
## one, set the opacity of all; Reset restores the defaults. Saves to
## settings input/touch_layout and input/touch_opacity on Done.

signal closed

var _controls := TouchControls.new()
var _size_slider := HSlider.new()
var _opacity_slider := HSlider.new()
var _hint: Label


func _init() -> void:
	# Over the whole screen, not the settings page's margins: TouchControls
	# lays buttons out in screen space, as in a match.
	top_level = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.07, 0.11, 0.97)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_controls.editing = true
	add_child(_controls)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 24
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_hint = UiStyle.label("TOUCH_EDIT_HINT", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_hint)
	for row: Array in [["TOUCH_EDIT_SIZE", _size_slider, TouchControls.MIN_SCALE, TouchControls.MAX_SCALE],
			["SETTING_TOUCH_OPACITY", _opacity_slider, 0.3, 1.0]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var label := Label.new()
		label.text = row[0]
		label.custom_minimum_size.x = 240
		line.add_child(label)
		var slider: HSlider = row[1]
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(320, 40)
		line.add_child(slider)
		box.add_child(line)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var reset := UiStyle.menu_button("TOUCH_EDIT_RESET")
	reset.custom_minimum_size = Vector2(200, 52)
	reset.pressed.connect(func() -> void:
		_controls.apply_layout({})
		_select(""))
	buttons.add_child(reset)
	var done := UiStyle.menu_button("SETTINGS_DONE", &"PrimaryButton")
	done.custom_minimum_size = Vector2(200, 52)
	done.pressed.connect(_done)
	buttons.add_child(done)
	_controls.selection_changed.connect(_select)
	_size_slider.value_changed.connect(func(v: float) -> void:
		if not _controls.selected.is_empty():
			_controls.set_scale_of(_controls.selected, v))
	_opacity_slider.value_changed.connect(func(v: float) -> void: _controls.modulate.a = v)
	visible = false


func open() -> void:
	_controls.apply_layout(Settings.get_value("input", "touch_layout"))
	_opacity_slider.value = float(Settings.get_value("input", "touch_opacity"))
	_controls.visible = true
	_select("")
	visible = true


func _select(id: String) -> void:
	_size_slider.editable = not id.is_empty()
	_size_slider.set_value_no_signal(_controls.scale_of(id) if not id.is_empty() else 1.0)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_done()


func _done() -> void:
	Settings.set_value("input", "touch_layout", _controls.layout())
	Settings.set_value("input", "touch_opacity", _opacity_slider.value)
	Settings.save_settings()
	visible = false
	closed.emit()
