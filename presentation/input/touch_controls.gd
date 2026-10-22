class_name TouchControls
extends Control
## On-screen touch controls with finger ownership classes (PLAN §3.11):
## 1. move finger: floating joystick on the left (push to the top edge = sprint)
## 2. look fingers: started on empty space on the right
## 3. fire finger: combined fire + look; dragging it also turns the camera
## 4. button fingers: all other buttons, exclusive, never become look fingers
## Layout: the right-hand buttons form one thumb cluster around Fire,
## anchored to the bottom-right corner and measured in screen heights, so it
## keeps its shape on 16:9 and 20:9 screens alike: Jump in the corner where
## the thumb rests, Crouch below Fire, Reload, Melee and Grenade along its
## left and top, Swap on its right. Icons only, each a picture of the action.
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

## Buttons: `pos` is the centre's offset from the bottom-right corner and
## `radius` its size, both in screen heights. `press` actions fire on touch,
## `held` flags stay set while the finger is down.
const DEFAULT_BUTTONS := [
	{"id": "fire", "label": "TOUCH_FIRE", "pos": Vector2(0.27, 0.31), "radius": 0.1, "kind": Kind.FIRE},
	{"id": "jump", "label": "TOUCH_JUMP", "pos": Vector2(0.09, 0.12), "radius": 0.075, "press": PlayerCommand.Action.JUMP, "held": PlayerCommand.Held.JUMP},
	{"id": "crouch", "label": "TOUCH_CROUCH", "pos": Vector2(0.29, 0.115), "radius": 0.055, "held": PlayerCommand.Held.CROUCH},
	{"id": "reload", "label": "TOUCH_RELOAD", "pos": Vector2(0.47, 0.22), "radius": 0.055, "press": PlayerCommand.Action.RELOAD},
	{"id": "swap", "label": "TOUCH_SWAP", "pos": Vector2(0.09, 0.40), "radius": 0.055, "press": PlayerCommand.Action.SWITCH},
	{"id": "grenade", "label": "TOUCH_GRENADE", "pos": Vector2(0.25, 0.56), "radius": 0.05, "press": PlayerCommand.Action.GRENADE},
	{"id": "melee", "label": "TOUCH_MELEE", "pos": Vector2(0.44, 0.44), "radius": 0.05, "press": PlayerCommand.Action.MELEE},
	{"id": "interact", "label": "TOUCH_INTERACT", "pos": Vector2(0.62, 0.62), "radius": 0.06, "press": PlayerCommand.Action.INTERACT,
			"contextual": true},
]
## Saved layouts older than this used fractions of the screen and are
## dropped for the new defaults.
const LAYOUT_VERSION := 2
## Where the floating stick's resting hint sits: offset from the
## bottom-left corner, in screen heights.
const STICK_HINT := Vector2(0.3, 0.3)
const MIN_SCALE := 0.6
const MAX_SCALE := 1.8

var editing: bool = false
var selected: String = ""
var _buttons: Array = []  ## DEFAULT_BUTTONS with the layout applied
var _drag_offset := Vector2.ZERO
var _fingers: Dictionary = {}  ## index -> {kind, origin, pos, button}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available()
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


## Buttons from the defaults with `layout` ({v, id: [x, y, scale]}, x and y
## as in DEFAULT_BUTTONS) applied.
func apply_layout(layout: Variant) -> void:
	_buttons = []
	var valid: bool = layout is Dictionary and int(layout.get("v", 1)) == LAYOUT_VERSION
	for d: Dictionary in DEFAULT_BUTTONS:
		var b := d.duplicate()
		b["base_radius"] = d.radius
		b["scale"] = 1.0
		if valid and layout.has(d.id) and layout[d.id] is Array and (layout[d.id] as Array).size() == 3:
			var o: Array = layout[d.id]
			b.pos = _clamp_offset(Vector2(o[0], o[1]))
			b.scale = clampf(o[2], MIN_SCALE, MAX_SCALE)
			b.radius = d.radius * b.scale
		_buttons.append(b)
	queue_redraw()


## Keeps a corner offset on a 16:9 screen or wider.
static func _clamp_offset(o: Vector2) -> Vector2:
	return Vector2(clampf(o.x, 0.04, 1.7), clampf(o.y, 0.04, 0.96))


## The current layout, for saving: {v, id: [x, y, scale]}.
func layout() -> Dictionary:
	var out := {"v": LAYOUT_VERSION}
	for b: Dictionary in _buttons:
		out[b.id] = [b.pos.x, b.pos.y, b.scale]
	return out


## A button's centre on screen.
func _center(b: Dictionary) -> Vector2:
	var screen := _screen()
	return screen - (b.pos as Vector2) * screen.y


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
			_drag_offset = _center(b) - event.position
			selection_changed.emit(selected)
			get_viewport().set_input_as_handled()
		else:
			selected = ""
	elif drag and not selected.is_empty():
		for b: Dictionary in _buttons:
			if b.id == selected:
				var screen := _screen()
				b.pos = _clamp_offset((screen - (event.position + _drag_offset)) / screen.y)
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
		if pos.distance_to(_center(b)) <= b.radius * screen.y * 1.15:
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
		var center := _center(b)
		var r: float = b.radius * screen.y
		var pressed := _is_pressed(b)
		var accent: Color = UiStyle.WARN if b.id == "fire" else UiStyle.ACCENT
		if b.get("contextual", false):
			accent = UiStyle.GOOD
		if pressed:
			r *= 0.94  # a slight push-in
		draw_circle(center, r, Color(accent, 0.4) if pressed else Color(0.02, 0.04, 0.07, 0.45))
		draw_arc(center, r, 0.0, TAU, 48, Color(accent, 0.95 if pressed else 0.6), 3.0 if b.id == "fire" else 2.0)
		if b.id == "fire":
			draw_arc(center, r * 0.82, 0.0, TAU, 48, Color(accent, 0.25), 1.5)
		_icon(b.id, center, r * (0.5 if b.id == "fire" else 0.66), Color(1, 1, 1, 0.95 if pressed else 0.88))
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
		# Ghost stick where the left thumb rests (it floats: any touch on the
		# left side starts it), with the sprint notch on top.
		var hint := Vector2(STICK_HINT.x * screen.y, screen.y * (1.0 - STICK_HINT.y))
		draw_circle(hint, JOYSTICK_RADIUS * 0.8, Color(0.02, 0.04, 0.07, 0.22))
		draw_arc(hint, JOYSTICK_RADIUS * 0.8, 0.0, TAU, 48, Color(UiStyle.ACCENT, 0.35), 2.0)
		draw_arc(hint, JOYSTICK_RADIUS * 0.8 + 7.0, -PI * 0.5 - 0.3, -PI * 0.5 + 0.3, 12, Color(UiStyle.WARN, 0.45), 3.0)
		draw_circle(hint, 30.0, Color(UiStyle.ACCENT, 0.18))
		draw_arc(hint, 30.0, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.5)


## Vector icons that picture the action, so buttons read without text.
## `s` is about the icon's half-size.
func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(3.0, s * 0.17)
	match id:
		"fire":  # crosshair
			draw_arc(c, s * 0.7, 0.0, TAU, 40, col, w)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * s * 0.42, c + d * s * 1.05, col, w * 1.2)
			draw_circle(c, s * 0.13, col)
		"jump":  # up arrow leaving the ground
			_poly(c, s, [[-0.17, 0.5], [0.17, 0.5], [0.17, -0.15], [-0.17, -0.15]], col)
			_poly(c, s, [[-0.58, -0.1], [0.0, -0.85], [0.58, -0.1]], col)
			draw_line(c + Vector2(-0.7, 0.82) * s, c + Vector2(0.7, 0.82) * s, col, w)
		"crouch":  # squatting figure
			draw_circle(c + Vector2(0.12, -0.6) * s, s * 0.2, col)
			draw_polyline(_pts(c, s, [[0.02, -0.36], [-0.22, 0.18], [0.35, 0.22], [0.22, 0.72]]), col, w * 1.3)
			draw_line(c + Vector2(-0.06, -0.14) * s, c + Vector2(0.45, -0.02) * s, col, w * 1.1)
			draw_line(c + Vector2(-0.7, 0.82) * s, c + Vector2(0.7, 0.82) * s, col, w)
		"reload":  # magazine inside a circular arrow
			draw_arc(c, s * 0.88, -PI * 0.35, PI * 1.25, 32, col, w)
			var tip := c + Vector2.from_angle(-PI * 0.35) * s * 0.88
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-0.38, -0.08) * s, tip + Vector2(0.1, -0.4) * s,
					tip + Vector2(0.22, 0.18) * s]), col)
			_poly(c, s, [[-0.3, -0.3], [0.1, -0.3], [0.32, 0.45], [-0.1, 0.45]], col)
			_poly(c, s, [[-0.22, -0.36], [-0.12, -0.52], [0.0, -0.36]], col)  # a round on top
		"swap":  # rifle with a two-way arrow
			_poly(c, s, [[-0.95, -0.55], [-0.55, -0.62], [0.55, -0.62], [0.55, -0.68], [0.98, -0.68], [0.98, -0.5],
					[0.55, -0.5], [0.4, -0.3], [-0.95, -0.3]], col)
			_poly(c, s, [[0.12, -0.3], [0.3, -0.3], [0.36, -0.05], [0.18, -0.05]], col)
			_poly(c, s, [[-0.42, -0.3], [-0.2, -0.3], [-0.32, -0.02], [-0.52, -0.02]], col)
			draw_line(c + Vector2(-0.7, 0.5) * s, c + Vector2(0.7, 0.5) * s, col, w)
			_poly(c, s, [[-0.95, 0.5], [-0.6, 0.25], [-0.6, 0.75]], col)
			_poly(c, s, [[0.95, 0.5], [0.6, 0.25], [0.6, 0.75]], col)
		"grenade":  # body, lever and pin ring
			draw_circle(c + Vector2(0, 0.22) * s, s * 0.58, col)
			draw_line(c + Vector2(-0.5, 0.22) * s, c + Vector2(0.5, 0.22) * s, Color(0, 0, 0, 0.45), w * 0.8)
			_poly(c, s, [[-0.22, -0.55], [0.22, -0.55], [0.22, -0.32], [-0.22, -0.32]], col)
			draw_polyline(_pts(c, s, [[0.15, -0.55], [0.55, -0.82], [0.62, -0.1]]), col, w)
			draw_arc(c + Vector2(-0.45, -0.68) * s, s * 0.2, 0.0, TAU, 20, col, w)
		"melee":  # knife, drawn along the diagonal
			draw_set_transform(c, -PI * 0.25)
			_poly(Vector2.ZERO, s, [[-1.0, -0.15], [-0.35, -0.15], [-0.35, 0.15], [-1.0, 0.15]], col)
			_poly(Vector2.ZERO, s, [[-0.32, -0.3], [-0.22, -0.3], [-0.22, 0.3], [-0.32, 0.3]], col)
			_poly(Vector2.ZERO, s, [[-0.18, -0.14], [0.55, -0.14], [1.0, 0.1], [-0.18, 0.16]], col)
			draw_set_transform(Vector2.ZERO)
		"interact":  # arrow dropping into a tray: pick up
			_poly(c, s, [[-0.15, -0.85], [0.15, -0.85], [0.15, -0.05], [-0.15, -0.05]], col)
			_poly(c, s, [[-0.45, -0.12], [0.0, 0.38], [0.45, -0.12]], col)
			draw_polyline(_pts(c, s, [[-0.75, 0.15], [-0.75, 0.75], [0.75, 0.75], [0.75, 0.15]]), col, w)
		_:
			draw_circle(c, s * 0.3, col)


## Points [[x, y], …] in units of `s` around `c`.
func _pts(c: Vector2, s: float, points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in points:
		out.append(c + Vector2(p[0], p[1]) * s)
	return out


func _poly(c: Vector2, s: float, points: Array, col: Color) -> void:
	draw_colored_polygon(_pts(c, s, points), col)
