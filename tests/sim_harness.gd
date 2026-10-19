class_name SimHarness
extends RefCounted
## Test helpers: an arena + SimWorld and a scripted command builder.

const MOVEMENT := preload("res://data/movement_config.tres")
const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")
const ARENA := preload("res://maps/test_arena/gameplay.tscn")


static func make_arena() -> Node3D:
	return ARENA.instantiate()


static func make_world(seed_value: int = 7) -> SimWorld:
	var w := SimWorld.new()
	w.configure(seed_value, MOVEMENT, TestArenaLayout.spawn_points())
	return w


static func loadout() -> Array[WeaponData]:
	var l: Array[WeaponData] = [PULSE, ARC]
	return l


## Builds commands with persistent press counters, like a real client.
class CommandScript:
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


## Places a player at `feet`, facing `yaw`, standing on the ground.
static func place(p: SimPlayer, feet: Vector3, yaw: float) -> void:
	var s := p.state.copy()
	s.position = feet
	s.velocity = Vector3.ZERO
	s.yaw = yaw
	s.move_state = PlayerSimState.Move.AIR
	s.spawn_protection_ticks = 0
	p.restore(s)
