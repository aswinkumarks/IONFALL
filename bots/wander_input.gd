class_name WanderInput
extends RefCounted
## Scripted input for headless test clients (PLAN §5 soak): wanders in arcs,
## sprints, jumps, slides, fires in bursts, reloads and switches weapons, so a
## soak exercises movement, prediction, weapons, projectiles and events. Like
## every bot it only produces PlayerCommands.

var _presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
var _rng := RandomNumberGenerator.new()
var _yaw: float = 0.0
var _turn: float = 0.0
var _fire_ticks: int = 0
var _crouch_ticks: int = 0


func _init(seed_value: int) -> void:
	_rng.seed = seed_value
	_yaw = _rng.randf() * TAU


func command_for(tick: int) -> PlayerCommand:
	var c := PlayerCommand.new()
	c.tick = tick
	if tick % 90 == 0:
		_turn = _rng.randf_range(-0.04, 0.04)
	_yaw = fposmod(_yaw + _turn, TAU)
	var held := 0
	if _rng.randf() < 0.004:
		_fire_ticks = _rng.randi_range(10, 60)
	if _fire_ticks > 0:
		_fire_ticks -= 1
		held |= PlayerCommand.Held.FIRE
	@warning_ignore("integer_division")
	if (tick / 180) % 3 != 2:
		held |= PlayerCommand.Held.SPRINT
	if _rng.randf() < 0.002:
		_crouch_ticks = 30
	if _crouch_ticks > 0:
		_crouch_ticks -= 1
		held |= PlayerCommand.Held.CROUCH
	if _rng.randf() < 0.01:
		_press(PlayerCommand.Action.JUMP)
	if _rng.randf() < 0.002:
		_press(PlayerCommand.Action.RELOAD)
	if _rng.randf() < 0.002:
		_press(PlayerCommand.Action.SWITCH)
	c.set_move(Vector2(sin(tick * 0.02) * 0.4, 1.0).limit_length(1.0))
	c.set_look(_yaw, sin(tick * 0.01) * 0.2)
	c.held = held
	c.presses = _presses.duplicate()
	return c


func _press(action: int) -> void:
	_presses[action] = (_presses[action] + 1) & 0xFF
