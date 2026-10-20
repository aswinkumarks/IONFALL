class_name Health
extends RefCounted
## Shield + health rules (PLAN §2.2).

const MAX_SHIELD := 100.0
const MAX_HEALTH := 100.0
## Both regens wait 5 s after the last damage; health then waits for a full
## shield.
const SHIELD_DELAY_TICKS := 300
const HEALTH_DELAY_TICKS := 300
const SHIELD_REGEN_PER_TICK := 10.0 / Sim.TICK_RATE  ## 10% per second
const HEALTH_REGEN_PER_TICK := 5.0 / Sim.TICK_RATE  ## 5% per second


class Result:
	var shield_damage: float = 0.0
	var health_damage: float = 0.0
	var shield_broken: bool = false
	var killed: bool = false
	var blocked: bool = false


## Applies `amount` damage. The headshot multiplier only applies to damage
## dealt to health, unless the weapon is `precision`, where it applies to the
## whole hit (so a precision headshot goes through shields).
static func apply(s: PlayerSimState, amount: float, headshot: bool, multiplier: float, precision: bool) -> Result:
	var r := Result.new()
	if not s.alive or amount <= 0.0:
		return r
	if s.spawn_protection_ticks > 0:
		r.blocked = true
		return r
	if headshot and precision:
		amount *= multiplier
	r.shield_damage = minf(s.shield, amount)
	s.shield -= r.shield_damage
	r.shield_broken = r.shield_damage > 0.0 and s.shield <= 0.0
	var remaining := amount - r.shield_damage
	if remaining > 0.0:
		if headshot and not precision:
			remaining *= multiplier
		r.health_damage = minf(s.health, remaining)
		s.health -= remaining
	s.shield_delay_ticks = SHIELD_DELAY_TICKS
	s.health_delay_ticks = HEALTH_DELAY_TICKS
	if s.health <= 0.0:
		s.health = 0.0
		r.killed = true
	return r


static func tick_regen(s: PlayerSimState) -> void:
	if not s.alive:
		return
	if s.shield_delay_ticks > 0:
		s.shield_delay_ticks -= 1
	else:
		s.shield = minf(MAX_SHIELD, s.shield + SHIELD_REGEN_PER_TICK)
	if s.health_delay_ticks > 0:
		s.health_delay_ticks -= 1
	elif s.shield >= MAX_SHIELD:
		s.health = minf(MAX_HEALTH, s.health + HEALTH_REGEN_PER_TICK)


static func reset(s: PlayerSimState) -> void:
	s.shield = MAX_SHIELD
	s.health = MAX_HEALTH
	s.shield_delay_ticks = 0
	s.health_delay_ticks = 0
