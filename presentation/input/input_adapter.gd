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
## Mouse and touch look speed multiplier; the match lowers it while scoped
## so the zoomed view turns at the same on-screen speed.
var look_scale: float = 1.0
## Touch auto-fire (AimAssist) holds the trigger; a burst weapon needs a
## press, so the rising edge presses too.
var assist_fire: bool = false:
	set(v):
		if v and not assist_fire:
			press(Action.FIRE)
		assist_fire = v

var _presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
var _mouse_fire: bool = false
var _mouse_aim: bool = false
var _slot_request: int = -1
## The match wants the cursor free (choosing a gun while respawning): a
## click doesn't recapture the mouse.
var keep_cursor: bool = false
## A slot request is sent with every command until the player holds that
## slot (confirm_slot) or this time passes: one command alone was lost while
## dead or respawning, or behind a melee.
const SLOT_REQUEST_MS := 3000
var _slot_request_until: int = 0
## Toggle modes (PLAN §3.16): the held state flips on each press.
var _crouch_on: bool = false
var _sprint_on: bool = false


func _ready() -> void:
	_ensure_actions()
	apply_keymap()
	Events.settings_changed.connect(func(section: String, key: String, _value: Variant) -> void:
		if section == "input" and key == "keymap":
			apply_keymap())


func press(action: int) -> void:
	_presses[action] = (_presses[action] + 1) & 0xFF
	if action == Action.SWITCH:
		_slot_request = -1  # cycling overrides a pending slot request


## Adds a look delta in radians (used by touch look and fire fingers).
func add_look(delta_yaw: float, delta_pitch: float) -> void:
	look_yaw = fposmod(look_yaw + delta_yaw, TAU)
	look_pitch = clampf(look_pitch + delta_pitch, -PlayerCommand.PITCH_LIMIT, PlayerCommand.PITCH_LIMIT)


func reset_held() -> void:
	_mouse_fire = false
	_mouse_aim = false
	_crouch_on = false
	_sprint_on = false
	touch_move = Vector2.ZERO
	touch_held = 0
	assist_fire = false


## Switches to weapon `slot` on the next command (touch: tapping its chip).
func select_slot(slot: int) -> void:
	_slot_request = slot
	_slot_request_until = Time.get_ticks_msec() + SLOT_REQUEST_MS


## The weapon slot the player holds now: a pending request for it is done.
func confirm_slot(slot: int) -> void:
	if slot == _slot_request:
		_slot_request = -1


## Aim (scope) is held: right mouse button or the touch scope toggle.
func aim_held() -> bool:
	return enabled and (_mouse_aim or (touch_held & Held.AIM) != 0)


## Lets go of a held mouse button (all of them with the default), e.g. when
## the cursor is freed and the release may never reach the game. Toggled aim
## stays as it is.
func release_mouse(button: int = -1) -> void:
	if button in [-1, MOUSE_BUTTON_LEFT]:
		_mouse_fire = false
	if button in [-1, MOUSE_BUTTON_RIGHT] and not Settings.get_value("input", "aim_toggle"):
		_mouse_aim = false


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
	if assist_fire:
		held |= Held.FIRE
	if _mouse_fire:
		held |= Held.FIRE
	if _mouse_aim:
		held |= Held.AIM
	var sprint := _sprint_on if Settings.get_value("input", "sprint_toggle") else Input.is_action_pressed("sprint")
	var crouch := _crouch_on if Settings.get_value("input", "crouch_toggle") else Input.is_action_pressed("crouch")
	if sprint:
		held |= Held.SPRINT
	if crouch:
		held |= Held.CROUCH
	if Input.is_action_pressed("jump"):
		held |= Held.JUMP
	c.held = held
	if _slot_request >= 0 and Time.get_ticks_msec() > _slot_request_until:
		_slot_request = -1
	c.weapon_slot = _slot_request
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
		add_look(-event.relative.x * MOUSE_RADIANS_PER_PIXEL * sens_x * look_scale,
				-event.relative.y * MOUSE_RADIANS_PER_PIXEL * sens_y * invert * look_scale)
	elif event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not Platform.is_mobile() and not keep_cursor:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif not event.pressed:
				# The cursor was freed while a button was held (death, a
				# menu): still let go, or the trigger stays held.
				release_mouse(event.button_index)
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_mouse_fire = event.pressed
				if event.pressed:
					press(Action.FIRE)
			MOUSE_BUTTON_RIGHT:
				if Settings.get_value("input", "aim_toggle"):
					if event.pressed:
						_mouse_aim = not _mouse_aim
				else:
					_mouse_aim = event.pressed
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					press(Action.MELEE)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					press(Action.SWITCH)
	elif event.is_action_pressed("crouch"):
		_crouch_on = not _crouch_on
	elif event.is_action_pressed("sprint"):
		_sprint_on = not _sprint_on
		_crouch_on = false
	elif event.is_action_pressed("jump"):
		press(Action.JUMP)
	elif event.is_action_pressed("reload"):
		press(Action.RELOAD)
	elif event.is_action_pressed("switch_weapon"):
		press(Action.SWITCH)
	elif event.is_action_pressed("weapon_1"):
		select_slot(0)
	elif event.is_action_pressed("weapon_2"):
		select_slot(1)
	elif event.is_action_pressed("grenade"):
		press(Action.GRENADE)
	elif event.is_action_pressed("melee"):
		press(Action.MELEE)
	elif event.is_action_pressed("interact"):
		press(Action.INTERACT)


## Default bindings, created at runtime so they can be remapped later
## (PLAN §3.16) without hand-editing project.godot.
## Remappable actions and their default keys (PLAN §3.16).
const DEFAULT_KEYS := {
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
		"grenade": [KEY_G],
		"melee": [KEY_V, KEY_F],
		"interact": [KEY_E],
		"scoreboard": [KEY_TAB],
}


static func _ensure_actions() -> void:
	for action in DEFAULT_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


## Default keys, with the player's overrides from settings (one key per
## remapped action; the defaults' alternate keys are dropped then).
static func apply_keymap() -> void:
	_ensure_actions()
	var overrides: Dictionary = Settings.get_value("input", "keymap")
	for action in DEFAULT_KEYS:
		InputMap.action_erase_events(action)
		var keys: Array = [overrides[action]] if overrides.has(action) else DEFAULT_KEYS[action]
		for key in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(key)
			InputMap.action_add_event(action, ev)


static func key_name(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "-"
	var ev := events[0] as InputEventKey
	if ev == null:
		return "-"
	# Show the key for the user's keyboard layout where the platform can say.
	if DisplayServer.get_name() == "headless" or Platform.is_mobile() or Platform.is_web():
		return OS.get_keycode_string(ev.physical_keycode)
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode))
