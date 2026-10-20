class_name TouchControls
extends Control
## On-screen touch controls with finger ownership classes (PLAN §3.11):
## 1. move finger: floating joystick on the left (push to the top edge = sprint)
## 2. look fingers: started on empty space on the right
## 3. fire finger: combined fire + look; dragging it also turns the camera
## 4. button fingers: all other buttons, exclusive, never become look fingers
## Layout editor (PLAN §3.11): each button's position and size can be
## overridden (settings input/touch_layout) and all share an opacity; in
## `editing` mode fingers (or the mouse) drag buttons instead of playing.

signal selection_changed(id: String)

enum Kind { MOVE, LOOK, FIRE, BUTTON }

const LOOK_RADIANS_PER_PIXEL := 0.0045
const JOYSTICK_RADIUS := 110.0
const SPRINT_THRESHOLD := 0.9

var input: InputAdapter
## Aim assist slowdown on look fingers (AimAssist.slowdown).
var assist_scale: float = 1.0
## The interact button shows only while something can be picked up.
var show_interact: bool = false:
	set(v):
		if v != show_interact:
			show_interact = v
			queue_redraw()

## Buttons in fractions of the screen size. `press` actions fire on touch,
## `held` flags stay set while the finger is down.
const DEFAULT_BUTTONS := [
	{"id": "fire", "label": "TOUCH_FIRE", "pos": Vector2(0.86, 0.62), "radius": 0.075, "kind": Kind.FIRE},
	{"id": "jump", "label": "TOUCH_JUMP", "pos": Vector2(0.93, 0.83), "radius": 0.055, "press": PlayerCommand.Action.JUMP, "held": PlayerCommand.Held.JUMP},
	{"id": "crouch", "label": "TOUCH_CROUCH", "pos": Vector2(0.80, 0.88), "radius": 0.05, "held": PlayerCommand.Held.CROUCH},
	{"id": "reload", "label": "TOUCH_RELOAD", "pos": Vector2(0.73, 0.64), "radius": 0.042, "press": PlayerCommand.Action.RELOAD},
	{"id": "swap", "label": "TOUCH_SWAP", "pos": Vector2(0.93, 0.42), "radius": 0.042, "press": PlayerCommand.Action.SWITCH},
	{"id": "grenade", "label": "TOUCH_GRENADE", "pos": Vector2(0.70, 0.86), "radius": 0.042, "press": PlayerCommand.Action.GRENADE},
	{"id": "melee", "label": "TOUCH_MELEE", "pos": Vector2(0.64, 0.72), "radius": 0.042, "press": PlayerCommand.Action.MELEE},
	{"id": "interact", "label": "TOUCH_INTERACT", "pos": Vector2(0.62, 0.45), "radius": 0.05, "press": PlayerCommand.Action.INTERACT,
			"contextual": true},
]
const MIN_SCALE := 0.6
const MAX_SCALE := 1.8

var editing: bool = false
var selected: String = ""
var _buttons: Array = []  ## DEFAULT_BUTTONS with the layout applied
var _drag_offset := Vector2.ZERO
var _fingers: Dictionary = {}  ## index -> {kind, origin, pos, button}
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available()
	_font = get_theme_default_font()
	apply_layout(Settings.get_value("input", "touch_layout"))
	modulate.a = float(Settings.get_value("input", "touch_opacity"))
	Events.settings_changed.connect(func(section: String, key: String, value: Variant) -> void:
		if section == "input" and key == "touch_layout":
			apply_layout(value)
		elif section == "input" and key == "touch_opacity":
			modulate.a = float(value))
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw.call_deferred()


## Layout uses the viewport size directly: this control's own size can still
## be zero on the first frame.
func _screen() -> Vector2:
	return get_viewport_rect().size


## Buttons from the defaults with `layout` ({id: [x, y, scale]}) applied.
func apply_layout(layout: Variant) -> void:
	_buttons = []
	for d: Dictionary in DEFAULT_BUTTONS:
		var b := d.duplicate()
		b["base_radius"] = d.radius
		b["scale"] = 1.0
		if layout is Dictionary and layout.has(d.id) and (layout[d.id] as Array).size() == 3:
			var o: Array = layout[d.id]
			b.pos = Vector2(clampf(o[0], 0.03, 0.97), clampf(o[1], 0.05, 0.95))
			b.scale = clampf(o[2], MIN_SCALE, MAX_SCALE)
			b.radius = d.radius * b.scale
		_buttons.append(b)
	queue_redraw()


## The current layout, for saving: {id: [x, y, scale]}.
func layout() -> Dictionary:
	var out := {}
	for b: Dictionary in _buttons:
		out[b.id] = [b.pos.x, b.pos.y, b.scale]
	return out


func set_scale_of(id: String, value: float) -> void:
	for b: Dictionary in _buttons:
		if b.id == id:
			b.scale = clampf(value, MIN_SCALE, MAX_SCALE)
			b.radius = b.base_radius * b.scale
	queue_redraw()


func scale_of(id: String) -> float:
	for b: Dictionary in _buttons:
		if b.id == id:
			return b.scale
	return 1.0


func _edit_input(event: InputEvent) -> void:
	var down: bool = (event is InputEventScreenTouch and event.pressed) or \
			(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed)
	var up: bool = (event is InputEventScreenTouch and not event.pressed) or \
			(event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed)
	var drag: bool = event is InputEventScreenDrag or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT)
	if down:
		var b := _button_at(event.position)
		if not b.is_empty():
			selected = b.id
			_drag_offset = b.pos * _screen() - event.position
			selection_changed.emit(selected)
			get_viewport().set_input_as_handled()
		else:
			selected = ""
	elif drag and not selected.is_empty():
		for b: Dictionary in _buttons:
			if b.id == selected:
				var p: Vector2 = (event.position + _drag_offset) / _screen()
				b.pos = Vector2(clampf(p.x, 0.03, 0.97), clampf(p.y, 0.05, 0.95))
		get_viewport().set_input_as_handled()
	elif up:
		_drag_offset = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if editing:
		_edit_input(event)
		return
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
			var sens: float = Settings.get_value("input", "touch_sensitivity") * assist_scale
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
		if b.get("contextual", false) and not show_interact and not editing:
			continue
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
		if b.get("contextual", false) and not show_interact and not editing:
			continue
		var center: Vector2 = b.pos * screen
		var r: float = b.radius * screen.y
		var pressed := _is_pressed(b)
		var accent := UiStyle.ACCENT
		draw_circle(center, r, Color(accent, 0.38) if pressed else Color(0.02, 0.04, 0.07, 0.35))
		draw_arc(center, r, 0.0, TAU, 48, Color(accent, 0.9 if pressed else 0.55), 2.5)
		draw_arc(center, r - 5.0, -PI * 0.75, -PI * 0.25, 16, Color(accent, 0.35), 2.0)
		_icon(b.id, center, r * 0.42, Color(1, 1, 1, 0.95 if pressed else 0.8))
		if editing and b.id == selected:
			draw_arc(center, r + 8.0, 0.0, TAU, 48, UiStyle.WARN, 3.0)
	var moving := false
	for f in _fingers.values():
		if f.kind == Kind.MOVE:
			moving = true
			var offset: Vector2 = (f.pos - f.origin).limit_length(JOYSTICK_RADIUS)
			var sprint := -offset.y / JOYSTICK_RADIUS >= SPRINT_THRESHOLD
			draw_circle(f.origin, JOYSTICK_RADIUS, Color(0.02, 0.04, 0.07, 0.3))
			draw_arc(f.origin, JOYSTICK_RADIUS, 0.0, TAU, 64, Color(UiStyle.ACCENT, 0.5), 2.0)
			draw_arc(f.origin, JOYSTICK_RADIUS + 8.0, -PI * 0.5 - 0.35, -PI * 0.5 + 0.35, 16,
					Color(UiStyle.WARN, 0.95 if sprint else 0.35), 4.0)
			draw_circle(f.origin + offset, 36.0, Color(UiStyle.ACCENT, 0.35))
			draw_arc(f.origin + offset, 36.0, 0.0, TAU, 40, Color(1, 1, 1, 0.5), 2.0)
	if not moving:
		# Ghost hint where the floating stick usually starts.
		var hint := Vector2(0.14, 0.72) * screen
		draw_arc(hint, JOYSTICK_RADIUS * 0.7, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 2.0)
		draw_circle(hint, 22.0, Color(1, 1, 1, 0.08))


## Simple vector icons so buttons read at a glance without text.
func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(2.5, s * 0.14)
	match id:
		"fire":
			draw_arc(c, s * 0.75, 0.0, TAU, 32, col, w)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * s * 0.35, c + d * s * 1.05, col, w)
		"jump":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.2), c + Vector2(0, -s * 0.5), c + Vector2(s * 0.7, s * 0.2)]), col, w * 1.3)
			draw_line(c + Vector2(-s * 0.5, s * 0.75), c + Vector2(s * 0.5, s * 0.75), col, w)
		"crouch":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.3), c + Vector2(0, s * 0.4), c + Vector2(s * 0.7, -s * 0.3)]), col, w * 1.3)
			draw_line(c + Vector2(-s * 0.5, s * 0.8), c + Vector2(s * 0.5, s * 0.8), col, w)
		"reload":
			draw_arc(c, s * 0.7, -PI * 0.3, PI * 1.35, 24, col, w * 1.2)
			var tip := c + Vector2(cos(-PI * 0.3), sin(-PI * 0.3)) * s * 0.7
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-s * 0.35, -s * 0.1), tip + Vector2(s * 0.15, -s * 0.4), tip + Vector2(s * 0.2, s * 0.2)]), col)
		"swap":
			for k: float in [-1.0, 1.0]:
				var y := c.y + k * s * 0.35
				draw_line(Vector2(c.x - s * 0.7, y), Vector2(c.x + s * 0.7, y), col, w)
				var head := Vector2(c.x + k * s * 0.7, y)
				draw_line(head, head + Vector2(-k * s * 0.3, -s * 0.25), col, w)
				draw_line(head, head + Vector2(-k * s * 0.3, s * 0.25), col, w)
		"grenade":
			draw_arc(c + Vector2(0, s * 0.15), s * 0.55, 0.0, TAU, 24, col, w)
			draw_line(c + Vector2(-s * 0.25, -s * 0.45), c + Vector2(s * 0.25, -s * 0.45), col, w * 1.3)
			draw_line(c + Vector2(s * 0.25, -s * 0.45), c + Vector2(s * 0.6, -s * 0.8), col, w)
		"interact":
			draw_rect(Rect2(c - Vector2(s, s) * 0.6, Vector2(s, s) * 1.2), col, false, w)
			draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.3), col, w)
			draw_line(c + Vector2(-s * 0.3, 0), c + Vector2(s * 0.3, 0), col, w)
		"melee":
			for k in 3:
				var o := Vector2(-s * 0.35 + k * s * 0.35, 0.0)
				draw_line(c + o + Vector2(-s * 0.15, s * 0.6), c + o + Vector2(s * 0.15, -s * 0.6), col, w * 1.2)
		_:
			draw_string(_font, c + Vector2(-s, s * 0.3), tr(id), HORIZONTAL_ALIGNMENT_CENTER, s * 2.0, 16, col)
