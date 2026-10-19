class_name HitboxHistory
extends RefCounted
## Per-player hitbox history for lag compensation (PLAN §3.3.4): 30 ticks of
## position, stance, alive flag and generations. Only player hitboxes are
## rewound; world geometry is static.

const LENGTH := 30
## Maximum total rewind (15 ticks = 250 ms).
const MAX_REWIND_TICKS := 15


class Entry:
	var tick: int = -1
	var position := Vector3.ZERO
	var stance: int = 0
	var alive: bool = false
	var life_gen: int = 0
	var discontinuity_gen: int = 0


var _ring: Array[Entry] = []


func _init() -> void:
	_ring.resize(LENGTH)
	for i in LENGTH:
		_ring[i] = Entry.new()


func record(tick: int, s: PlayerSimState) -> void:
	var e := _ring[tick % LENGTH]
	e.tick = tick
	e.position = s.position
	e.stance = s.stance
	e.alive = s.alive
	e.life_gen = s.life_gen
	e.discontinuity_gen = s.discontinuity_gen


func at(tick: int) -> Entry:
	var e := _ring[posmod(tick, LENGTH)]
	return e if e.tick == tick else null


## Hitbox pose at fractional `view_tick`, or null if the player didn't exist,
## was dead, or crossed a respawn/teleport between the two bracketing ticks
## (treated as missing, PLAN §3.3.4).
func sample(view_tick: float) -> Entry:
	var t0 := floori(view_tick)
	var a := at(t0)
	var b := at(t0 + 1)
	if a == null:
		return b if b != null and is_equal_approx(view_tick, float(t0 + 1)) else null
	if not a.alive:
		return null
	var frac := view_tick - t0
	if b == null or frac <= 0.0:
		return a
	if not b.alive or b.discontinuity_gen != a.discontinuity_gen:
		return null
	var out := Entry.new()
	out.tick = t0
	out.position = a.position.lerp(b.position, frac)
	out.stance = a.stance if frac < 0.5 else b.stance
	out.alive = true
	out.life_gen = a.life_gen
	out.discontinuity_gen = a.discontinuity_gen
	return out
