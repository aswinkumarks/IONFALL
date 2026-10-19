class_name TargetDummyDriver
extends RefCounted
## Training dummy for M1a: strafes back and forth and hops now and then.
## Like real bots (PLAN §2.7), it only produces PlayerCommands, so it uses the
## same movement and validation code as a human.

var _presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
var _phase_offset: int = 0


func _init(phase_offset: int = 0) -> void:
	_phase_offset = phase_offset


func command_for(tick: int, p: SimPlayer) -> PlayerCommand:
	var c := PlayerCommand.new()
	c.tick = tick
	var t := tick + _phase_offset
	@warning_ignore("integer_division")
	var leg := (t / 75) % 2
	c.set_move(Vector2(1.0 if leg == 0 else -1.0, 0.0))
	if t % 210 == 100:
		_presses[PlayerCommand.Action.JUMP] = (_presses[PlayerCommand.Action.JUMP] + 1) & 0xFF
	c.presses = _presses.duplicate()
	# Keep facing the direction it spawned with.
	c.set_look(p.state.yaw, 0.0)
	return c
