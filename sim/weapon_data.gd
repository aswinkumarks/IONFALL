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
## Pellet weapons (Scatter Gun): rays per shot, each with its own spread.
@export var pellets: int = 1

@export_group("Scope")
## Aiming (right mouse button / the touch scope button) zooms the view by
## this factor and tightens the spread; 1 = the weapon has no scope.
@export var scope_zoom: float = 1.0
## Spread while scoped, as a fraction of `spread_degrees`.
@export_range(0.0, 1.0) var scope_spread: float = 0.4
## Ground speed while scoped, as a fraction of walking speed (no sprint).
@export_range(0.0, 1.0) var scope_move_speed: float = 0.7
## A full-screen scope overlay instead of the crosshair (sniper).
@export var scope_overlay: bool = false

@export_group("Recoil")
## Each shot kicks the aim up this much (degrees). The camera follows, so
## the player pulls down to stay on target.
@export var recoil_kick_degrees: float = 0.0
## And sideways, up to this much either way at random (degrees).
@export var recoil_side_degrees: float = 0.0
## The most the aim is kicked away in total (degrees).
@export var recoil_max_degrees: float = 5.0
## After the last shot the aim waits this long (ticks), then settles back
## at `recoil_recovery_degrees_per_second`. Longer than the time between
## shots makes held fire climb.
@export var recoil_recovery_delay_ticks: int = 8
@export var recoil_recovery_degrees_per_second: float = 14.0
## Scoped, kicks are this fraction of the full kick.
@export_range(0.0, 1.0) var recoil_scoped: float = 0.7

@export_group("Ammo")
@export var mag_size: int = 36
@export var reserve: int = 180
## Reloads never run the reserve down (loadout weapons); off for the power
## weapons picked up on the map, whose ammo is `mag_size` + `reserve`.
@export var infinite_reserve: bool = true
## Reload one round per `reload_ticks` until full (shells), instead of the
## whole magazine at once.
@export var reload_per_round: bool = false

@export_group("Projectile")
@export var projectile_speed: float = 40.0
@export var projectile_lifetime_ticks: int = 300
@export var direct_damage: float = 200.0
@export var splash_damage: float = 120.0
@export var splash_radius: float = 4.0
@export_range(0.0, 1.0) var self_damage_multiplier: float = 0.5
## Thrown projectiles (grenades): gravity in m/s², bounce off the world
## keeping this fraction of speed, and explode after `fuse_ticks` instead of
## on contact. 0 = straight flight, explode on contact.
@export var gravity: float = 0.0
@export_range(0.0, 1.0) var bounce: float = 0.0
@export var fuse_ticks: int = 0


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
