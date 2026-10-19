class_name TouchControls
extends Control
## On-screen touch controls with finger ownership classes (PLAN §3.11):
## 1. move finger: floating joystick on the left (push to the top edge = sprint)
## 2. look fingers: started on empty space on the right
## 3. fire finger: combined fire + look; dragging it also turns the camera
## 4. button fingers: all other buttons, exclusive, never become look fingers

enum Kind { MOVE, LOOK, FIRE, BUTTON }

const LOOK_RADIANS_PER_PIXEL := 0.0045
const JOYSTICK_RADIUS := 110.0
const SPRINT_THRESHOLD := 0.9

var input: InputAdapter

## Buttons in fractions of the screen size. `press` actions fire on touch,
## `held` flags stay set while the finger is down.
var _buttons := [
	{"id": "fire", "label": "TOUCH_FIRE", "pos": Vector2(0.86, 0.62), "radius": 0.075, "kind": Kind.FIRE},
	{"id": "jump", "label": "TOUCH_JUMP", "pos": Vector2(0.93, 0.83), "radius": 0.055, "press": PlayerCommand.Action.JUMP, "held": PlayerCommand.Held.JUMP},
	{"id": "crouch", "label": "TOUCH_CROUCH", "pos": Vector2(0.80, 0.88), "radius": 0.05, "held": PlayerCommand.Held.CROUCH},
	{"id": "reload", "label": "TOUCH_RELOAD", "pos": Vector2(0.73, 0.64), "radius": 0.042, "press": PlayerCommand.Action.RELOAD},
	{"id": "swap", "label": "TOUCH_SWAP", "pos": Vector2(0.93, 0.42), "radius": 0.042, "press": PlayerCommand.Action.SWITCH},
]
var _fingers: Dictionary = {}  ## index -> {kind, origin, pos, button}
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available()
	_font = get_theme_default_font()
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw.call_deferred()


## Layout uses the viewport size directly: this control's own size can still
## be zero on the first frame.
func _screen() -> Vector2:
	return get_viewport_rect().size


func _input(event: InputEvent) -> void:
	if not visible or input == null or not input.enabled:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_down(event.index, event.position)
		else:
			_on_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()


func release_all() -> void:
	for index in _fingers.keys():
		_on_up(index)


func _on_down(index: int, pos: Vector2) -> void:
	var button := _button_at(pos)
	if not button.is_empty():
		var kind: int = button.get("kind", Kind.BUTTON)
		_fingers[index] = {"kind": kind, "origin": pos, "pos": pos, "button": button}
		if kind == Kind.FIRE:
			input.press(PlayerCommand.Action.FIRE)
			input.touch_held |= PlayerCommand.Held.FIRE
		else:
			if button.has("press"):
				input.press(button.press)
			if button.has("held"):
				input.touch_held |= button.held
	elif pos.x < _screen().x * 0.4 and not _has_kind(Kind.MOVE):
		_fingers[index] = {"kind": Kind.MOVE, "origin": pos, "pos": pos}
	else:
		_fingers[index] = {"kind": Kind.LOOK, "origin": pos, "pos": pos}
	queue_redraw()


func _on_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if not _fingers.has(index):
		return
	var f: Dictionary = _fingers[index]
	f.pos = pos
	match f.kind:
		Kind.MOVE:
			var v: Vector2 = (pos - f.origin) / JOYSTICK_RADIUS
			v = v.limit_length(1.0)
			input.touch_move = Vector2(v.x, -v.y)
			if v.length() >= SPRINT_THRESHOLD and -v.y > 0.7:
				input.touch_held |= PlayerCommand.Held.SPRINT
			else:
				input.touch_held &= ~PlayerCommand.Held.SPRINT
		Kind.LOOK, Kind.FIRE:
			var sens: float = Settings.get_value("input", "touch_sensitivity")
			input.add_look(-relative.x * LOOK_RADIANS_PER_PIXEL * sens,
					-relative.y * LOOK_RADIANS_PER_PIXEL * sens)
	queue_redraw()


func _on_up(index: int) -> void:
	if not _fingers.has(index):
		return
	var f: Dictionary = _fingers[index]
	_fingers.erase(index)
	match f.kind:
		Kind.MOVE:
			input.touch_move = Vector2.ZERO
			input.touch_held &= ~PlayerCommand.Held.SPRINT
		Kind.FIRE:
			input.touch_held &= ~PlayerCommand.Held.FIRE
		Kind.BUTTON:
			if f.button.has("held"):
				input.touch_held &= ~int(f.button.held)
	queue_redraw()


func _button_at(pos: Vector2) -> Dictionary:
	var screen := _screen()
	for b in _buttons:
		if pos.distance_to(b.pos * screen) <= b.radius * screen.y * 1.15:
			return b
	return {}


func _has_kind(kind: int) -> bool:
	for f in _fingers.values():
		if f.kind == kind:
			return true
	return false


func _is_pressed(button: Dictionary) -> bool:
	for f in _fingers.values():
		if f.has("button") and f.button.id == button.id:
			return true
	return false


func _draw() -> void:
	var screen := _screen()
	for b in _buttons:
		var center: Vector2 = b.pos * screen
		var r: float = b.radius * screen.y
		var pressed := _is_pressed(b)
		draw_circle(center, r, Color(0.35, 0.9, 1.0, 0.35 if pressed else 0.15))
		draw_arc(center, r, 0.0, TAU, 48, Color(0.35, 0.9, 1.0, 0.7), 2.0)
		var text := tr(b.label)
		var fs := 18
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, center + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.8))
	for f in _fingers.values():
		if f.kind == Kind.MOVE:
			draw_arc(f.origin, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
			var knob: Vector2 = f.origin + (f.pos - f.origin).limit_length(JOYSTICK_RADIUS)
			draw_circle(knob, 34.0, Color(1, 1, 1, 0.35))
