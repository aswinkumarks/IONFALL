class_name Stepper
extends HBoxContainer
## A number with − and + buttons (the bot count). `changed(value)` fires on
## a press, not when the value is set from code. Read-only steppers show the
## value without buttons that work (lobby members).

signal changed(value: int)

var min_value: int = 0
var max_value: int = 10
var value: int = 0
var read_only: bool = false
## Optional text for a value (0 → "None"); the number otherwise.
var label_for: Callable = Callable()

var _minus := Button.new()
var _plus := Button.new()
var _label := Label.new()


func _init(p_min: int = 0, p_max: int = 10, p_value: int = 0, p_read_only: bool = false) -> void:
	min_value = p_min
	max_value = p_max
	read_only = p_read_only
	add_theme_constant_override("separation", 8)
	for b: Button in [_minus, _plus]:
		b.theme_type_variation = &"ChipButton"
		b.custom_minimum_size = Vector2(64, 46)
		b.focus_mode = Control.FOCUS_ALL if not read_only else Control.FOCUS_NONE
	_minus.text = "−"
	_plus.text = "+"
	_minus.pressed.connect(_step.bind(-1))
	_plus.pressed.connect(_step.bind(1))
	_label.custom_minimum_size = Vector2(96, 46)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UiStyle.font_display_bold)
	_label.add_theme_font_size_override("font_size", 26)
	add_child(_minus)
	add_child(_label)
	add_child(_plus)
	set_value(p_value)


func set_value(v: int) -> void:
	value = clampi(v, min_value, max_value)
	_label.text = label_for.call(value) if label_for.is_valid() else str(value)
	_minus.disabled = read_only or value <= min_value
	_plus.disabled = read_only or value >= max_value
	if read_only:
		_minus.visible = false
		_plus.visible = false


## Greys the stepper out when it doesn't apply (co-op waves bring their own bots).
func set_enabled(enabled: bool) -> void:
	modulate.a = 1.0 if enabled else 0.4
	_minus.disabled = not enabled or read_only or value <= min_value
	_plus.disabled = not enabled or read_only or value >= max_value


func _step(delta: int) -> void:
	var v := clampi(value + delta, min_value, max_value)
	if v == value:
		return
	set_value(v)
	changed.emit(value)
