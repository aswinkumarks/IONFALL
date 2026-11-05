extends RefCounted
## Builds commands with persistent press counters, like a real client. Used
## by the scripted fights of NativeParityCheck and the tests (SimHarness).

var presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
var yaw: float = 0.0
var pitch: float = 0.0


func cmd(tick: int, move: Vector2 = Vector2.ZERO, held: int = 0, press: Array = []) -> PlayerCommand:
	for a in press:
		presses[a] = (presses[a] + 1) & 0xFF
	var c := PlayerCommand.new()
	c.tick = tick
	c.set_move(move)
	c.set_look(yaw, pitch)
	c.held = held
	c.presses = presses.duplicate()
	return c
