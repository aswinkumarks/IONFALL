class_name InputAdapter
extends Node
## Turns device input into PlayerCommands (PLAN §3.11). Gameplay never reads
## devices directly. Look angles update every render frame, so the camera turns
## at the display's refresh rate; each command carries the latest angles.

const Action := PlayerCommand.Action
const Held := PlayerCommand.Held
const MOUSE_RADIANS_PER_PIXEL := 0.0022

var look_yaw: float = 0.0
var look_pitch: float = 0.0
## Set by touch controls.
var touch_move := Vector2.ZERO
var touch_held: int = 0
var enabled: bool = true

var _presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
var _mouse_fire: bool = false
var _mouse_aim: bool = false
var _slot_request: int = -1


func _ready() -> void:
	_ensure_actions()


func press(action: int) -> void:
	_presses[action] = (_presses[action] + 1) & 0xFF


## Adds a look delta in radians (used by touch look and fire fingers).
func add_look(delta_yaw: float, delta_pitch: float) -> void:
	look_yaw = fposmod(look_yaw + delta_yaw, TAU)
	look_pitch = clampf(look_pitch + delta_pitch, -PlayerCommand.PITCH_LIMIT, PlayerCommand.PITCH_LIMIT)


func reset_held() -> void:
	_mouse_fire = false
	_mouse_aim = false
	touch_move = Vector2.ZERO
	touch_held = 0


func build_command(tick: int) -> PlayerCommand:
	var c := PlayerCommand.new()
	c.tick = tick
	c.set_look(look_yaw, look_pitch)
	c.presses = _presses.duplicate()
	if not enabled:
		return c
	var kb := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	c.set_move((kb + touch_move).limit_length(1.0))
	var held := touch_held
	if _mouse_fire:
		held |= Held.FIRE
	if _mouse_aim:
		held |= Held.AIM
	if Input.is_action_pressed("sprint"):
		held |= Held.SPRINT
	if Input.is_action_pressed("crouch"):
		held |= Held.CROUCH
	if Input.is_action_pressed("jump"):
		held |= Held.JUMP
	c.held = held
	c.weapon_slot = _slot_request
	_slot_request = -1
	return c


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	# Touch is handled by TouchControls; ignore the mouse events Godot emulates
	# from touches so a tap doesn't also count as a mouse click.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens_x: float = Settings.get_value("input", "sensitivity_x")
		var sens_y: float = Settings.get_value("input", "sensitivity_y")
		var invert: float = -1.0 if Settings.get_value("input", "invert_y") else 1.0
		add_look(-event.relative.x * MOUSE_RADIANS_PER_PIXEL * sens_x,
				-event.relative.y * MOUSE_RADIANS_PER_PIXEL * sens_y * invert)
	elif event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not Platform.is_mobile():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_mouse_fire = event.pressed
				if event.pressed:
					press(Action.FIRE)
			MOUSE_BUTTON_RIGHT:
				_mouse_aim = event.pressed
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					press(Action.SWITCH)
	elif event.is_action_pressed("jump"):
		press(Action.JUMP)
	elif event.is_action_pressed("reload"):
		press(Action.RELOAD)
	elif event.is_action_pressed("switch_weapon"):
		press(Action.SWITCH)
	elif event.is_action_pressed("weapon_1"):
		_slot_request = 0
	elif event.is_action_pressed("weapon_2"):
		_slot_request = 1


## Default bindings, created at runtime so they can be remapped later
## (PLAN §3.16) without hand-editing project.godot.
static func _ensure_actions() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL, KEY_C],
		"reload": [KEY_R],
		"switch_weapon": [KEY_Q],
		"weapon_1": [KEY_1],
		"weapon_2": [KEY_2],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
