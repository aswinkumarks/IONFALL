class_name PlayerSimState
extends RefCounted
## Everything needed to replay a player's simulation exactly (PLAN §3.2).
## Restoring this state and re-running the same commands must reproduce the
## same results bit for bit on the same build.

enum Move { GROUND, AIR, SLIDE, MANTLE, DEAD }
enum Stance { STAND, CROUCH, SLIDE }

# Movement
var position := Vector3.ZERO  ## Feet position.
var velocity := Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var move_state: Move = Move.AIR
var stance: Stance = Stance.STAND
var sprinting: bool = false
var floor_normal := Vector3.UP
var ticks_since_floor: int = 0
var jump_buffer_ticks: int = 0
var air_jumps_left: int = 1
var slide_ticks: int = 0
var mantle_tick: int = 0
var mantle_start := Vector3.ZERO
var mantle_target := Vector3.ZERO

# Health (PLAN §2.2)
var shield: float = 100.0
var health: float = 100.0
var shield_delay_ticks: int = 0
var health_delay_ticks: int = 0
var alive: bool = true
## World tick at which a dead player respawns (absolute, so processing order
## within a tick can't change it).
var respawn_tick: int = 0
var spawn_protection_ticks: int = 0
var life_gen: int = 0
var discontinuity_gen: int = 0

# Weapons: each slot holds a Weapons.ALL index, so pickups can change it.
var action_seq: int = 0
var weapon_slot: int = 0
var switch_ticks: int = 0
var weapons := PackedInt32Array()
var mag := PackedInt32Array()
var reserve := PackedInt32Array()
var cooldown := PackedInt32Array()
var reload := PackedInt32Array()
var burst_left := PackedInt32Array()
var burst_timer := PackedInt32Array()
var grenades: int = 0
var throw_cooldown: int = 0
var melee_cooldown: int = 0
## Recoil (PLAN §2.3): how far shots have kicked the aim off yaw and pitch
## (radians), and the ticks until it starts to settle back.
var recoil := Vector2.ZERO
var recoil_hold: int = 0

# Input bookkeeping
var last_presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
var pending_presses := PackedByteArray([0, 0, 0, 0, 0, 0, 0])
var input_anomalies: int = 0


func is_on_floor() -> bool:
	return move_state == Move.GROUND or move_state == Move.SLIDE



func init_weapons(loadout: Array[WeaponData]) -> void:
	var n := loadout.size()
	weapons.resize(n)
	mag.resize(n)
	reserve.resize(n)
	cooldown.resize(n)
	reload.resize(n)
	burst_left.resize(n)
	burst_timer.resize(n)
	for i in n:
		set_slot(i, Weapons.index_of(loadout[i].id), loadout[i].mag_size, loadout[i].reserve)
	weapon_slot = 0
	switch_ticks = 0
	grenades = Balance.PLAYER.grenades_per_life
	throw_cooldown = 0
	melee_cooldown = 0
	recoil = Vector2.ZERO
	recoil_hold = 0


## Puts weapon `index` (Weapons.ALL) in `slot` with the given ammo.
func set_slot(slot: int, index: int, p_mag: int, p_reserve: int) -> void:
	weapons[slot] = index
	mag[slot] = p_mag
	reserve[slot] = p_reserve
	cooldown[slot] = 0
	reload[slot] = 0
	burst_left[slot] = 0
	burst_timer[slot] = 0


## Whether slot `slot`'s weapon can reload: an infinite reserve, or rounds left.
func has_reserve(slot: int) -> bool:
	var w := weapon(slot)
	return w != null and (w.infinite_reserve or reserve[slot] > 0)


## The weapon in `slot` (default: the held one), or null.
func weapon(slot: int = -1) -> WeaponData:
	var i := weapon_slot if slot < 0 else slot
	return Weapons.at(weapons[i]) if i >= 0 and i < weapons.size() else null


## Where the player is aiming: the look direction kicked by recoil.
func aim_yaw() -> float:
	return yaw + recoil.x


func aim_pitch() -> float:
	return clampf(pitch + recoil.y, -PI * 0.49, PI * 0.49)


## Every field, written out: copying by name through _fields() took ~25 us,
## and copies run every tick per player on a host and per predicted tick on
## a client. test_player_sim_state.gd checks this covers every field.
func copy() -> PlayerSimState:
	var s := PlayerSimState.new()
	s.position = position
	s.velocity = velocity
	s.yaw = yaw
	s.pitch = pitch
	s.move_state = move_state
	s.stance = stance
	s.sprinting = sprinting
	s.floor_normal = floor_normal
	s.ticks_since_floor = ticks_since_floor
	s.jump_buffer_ticks = jump_buffer_ticks
	s.air_jumps_left = air_jumps_left
	s.slide_ticks = slide_ticks
	s.mantle_tick = mantle_tick
	s.mantle_start = mantle_start
	s.mantle_target = mantle_target
	s.shield = shield
	s.health = health
	s.shield_delay_ticks = shield_delay_ticks
	s.health_delay_ticks = health_delay_ticks
	s.alive = alive
	s.respawn_tick = respawn_tick
	s.spawn_protection_ticks = spawn_protection_ticks
	s.life_gen = life_gen
	s.discontinuity_gen = discontinuity_gen
	s.action_seq = action_seq
	s.weapon_slot = weapon_slot
	s.switch_ticks = switch_ticks
	s.weapons = weapons.duplicate()
	s.mag = mag.duplicate()
	s.reserve = reserve.duplicate()
	s.cooldown = cooldown.duplicate()
	s.reload = reload.duplicate()
	s.burst_left = burst_left.duplicate()
	s.burst_timer = burst_timer.duplicate()
	s.grenades = grenades
	s.throw_cooldown = throw_cooldown
	s.melee_cooldown = melee_cooldown
	s.recoil = recoil
	s.recoil_hold = recoil_hold
	s.last_presses = last_presses.duplicate()
	s.pending_presses = pending_presses.duplicate()
	s.input_anomalies = input_anomalies
	return s


## Exact equality over every field. Returns "" if equal, otherwise the first
## differing field name with both values (used by replay tests).
func diff(other: PlayerSimState) -> String:
	for p in _fields():
		var a: Variant = get(p)
		var b: Variant = other.get(p)
		if a != b:
			return "%s: %s != %s" % [p, a, b]
	return ""


static var _field_cache: PackedStringArray = PackedStringArray()


func _fields() -> PackedStringArray:
	if _field_cache.is_empty():
		for prop in get_property_list():
			if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_field_cache.append(prop.name)
	return _field_cache
