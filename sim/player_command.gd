class_name PlayerCommand
extends RefCounted
## One tick of player input (PLAN §3.2). Values are quantized exactly as they
## will be sent over the network, so prediction and the server simulate the
## same numbers.

enum Held { FIRE = 1, SPRINT = 2, CROUCH = 4, AIM = 8, JUMP = 16 }
## One-shot actions tracked with wrap-around press counters.
enum Action { FIRE, JUMP, RELOAD, SWITCH, GRENADE, MELEE, INTERACT }
const ACTION_COUNT := 7

const PITCH_LIMIT := deg_to_rad(89.0)

var tick: int = 0
## Movement input, -127..127 (x = right, y = forward).
var move_x: int = 0
var move_y: int = 0
## Yaw as 0..65535 over a full turn; pitch as -32767..32767 over ±89°.
var view_yaw: int = 0
var view_pitch: int = 0
var held: int = 0
var presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
## Weapon slot the player wants (direct select); -1 = no change requested.
var weapon_slot: int = -1
## Lag compensation inputs, used from M1b (PLAN §3.3.4).
var view_tick: float = 0.0
var interp_ticks: int = 4


static func quantize_axis(v: float) -> int:
	return clampi(roundi(v * 127.0), -127, 127)


static func quantize_yaw(radians: float) -> int:
	return roundi(fposmod(radians, TAU) / TAU * 65536.0) & 0xFFFF


static func quantize_pitch(radians: float) -> int:
	return clampi(roundi(clampf(radians, -PITCH_LIMIT, PITCH_LIMIT) / PITCH_LIMIT * 32767.0), -32767, 32767)


func set_move(v: Vector2) -> void:
	v = v.limit_length(1.0)
	move_x = quantize_axis(v.x)
	move_y = quantize_axis(v.y)


func set_look(yaw: float, pitch: float) -> void:
	view_yaw = quantize_yaw(yaw)
	view_pitch = quantize_pitch(pitch)


func move_vector() -> Vector2:
	return Vector2(move_x / 127.0, move_y / 127.0).limit_length(1.0)


func yaw_radians() -> float:
	return view_yaw * TAU / 65536.0


func pitch_radians() -> float:
	return view_pitch * PITCH_LIMIT / 32767.0


func is_held(flag: int) -> bool:
	return (held & flag) != 0


func copy() -> PlayerCommand:
	var c := PlayerCommand.new()
	c.tick = tick
	c.move_x = move_x
	c.move_y = move_y
	c.view_yaw = view_yaw
	c.view_pitch = view_pitch
	c.held = held
	c.presses = presses.duplicate()
	c.weapon_slot = weapon_slot
	c.view_tick = view_tick
	c.interp_ticks = interp_ticks
	return c


## Neutral command: no movement, nothing held, presses unchanged (PLAN §3.3.2).
static func neutral_from(previous: PlayerCommand, at_tick: int) -> PlayerCommand:
	var c := PlayerCommand.new()
	c.tick = at_tick
	if previous != null:
		c.view_yaw = previous.view_yaw
		c.view_pitch = previous.view_pitch
		c.presses = previous.presses.duplicate()
	return c
