class_name WeaponData
extends Resource
## Weapon definition (PLAN §2.3). The balance table is generated from these
## resources; they are the source of truth. All timings are ticks.

enum FireMode { AUTO, SEMI, BURST, PROJECTILE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var fire_mode: FireMode = FireMode.AUTO
@export var is_power_weapon: bool = false

@export_group("Timing (ticks)")
@export var ticks_between_shots: int = 6
@export var burst_count: int = 1
@export var burst_spacing_ticks: int = 0
@export var reload_ticks: int = 120
@export var raise_ticks: int = 24

@export_group("Damage")
@export var damage: float = 18.0
@export var headshot_multiplier: float = 1.5
## Precision weapons apply the headshot multiplier through shields too.
@export var precision: bool = false
@export var full_damage_range: float = 30.0
@export var min_damage_range: float = 60.0
@export_range(0.0, 1.0) var min_damage_fraction: float = 0.7
@export var max_range: float = 200.0
@export var spread_degrees: float = 0.5

@export_group("Ammo")
@export var mag_size: int = 36
@export var reserve: int = 180

@export_group("Projectile")
@export var projectile_speed: float = 40.0
@export var projectile_lifetime_ticks: int = 300
@export var direct_damage: float = 200.0
@export var splash_damage: float = 120.0
@export var splash_radius: float = 4.0
@export_range(0.0, 1.0) var self_damage_multiplier: float = 0.5


func is_projectile() -> bool:
	return fire_mode == FireMode.PROJECTILE


## Damage after range falloff at `distance` metres.
func damage_at(distance: float) -> float:
	if distance <= full_damage_range:
		return damage
	if distance >= min_damage_range:
		return damage * min_damage_fraction
	var t := (distance - full_damage_range) / (min_damage_range - full_damage_range)
	return damage * lerpf(1.0, min_damage_fraction, t)
