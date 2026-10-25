class_name Health
extends RefCounted
## Shield + health rules (PLAN §2.2).

## Maxima, regeneration delays and rates: Balance.PLAYER (data/player.tres).
## Health regenerates only once the shield is full.


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
	s.shield_delay_ticks = Balance.PLAYER.shield_delay_ticks
	s.health_delay_ticks = Balance.PLAYER.health_delay_ticks
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
		s.shield = minf(Balance.PLAYER.max_shield, s.shield + Balance.PLAYER.shield_regen_per_tick())
	if s.health_delay_ticks > 0:
		s.health_delay_ticks -= 1
	elif s.shield >= Balance.PLAYER.max_shield:
		s.health = minf(Balance.PLAYER.max_health, s.health + Balance.PLAYER.health_regen_per_tick())


static func reset(s: PlayerSimState) -> void:
	s.shield = Balance.PLAYER.max_shield
	s.health = Balance.PLAYER.max_health
	s.shield_delay_ticks = 0
	s.health_delay_ticks = 0
