class_name PlayerConfig
extends Resource
## Player balance (data/player.tres, read through Balance.PLAYER): health,
## shield, respawning, grenades, melee, scoring and pickups. Part of the
## compatibility hash, like everything in data/: host and clients must have
## the same values. Times are ticks (60 per second).

@export_group("Health and shield")
@export var max_shield: float = 100.0
@export var max_health: float = 100.0
## Shield regeneration starts this long after the last damage.
@export var shield_delay_ticks: int = 300
## Health regeneration starts this long after the last damage, and only
## once the shield is full.
@export var health_delay_ticks: int = 300
## Points regenerated per second.
@export var shield_regen_per_second: float = 10.0
@export var health_regen_per_second: float = 5.0

@export_group("Spawning")
## Damage is ignored this long after spawning.
@export var spawn_protection_ticks: int = 150

@export_group("Grenades")
@export var grenades_per_life: int = 2
## Minimum time between two throws.
@export var throw_cooldown_ticks: int = 30

@export_group("Melee")
## A melee hit lands on targets within this angle of the aim (each side).
@export_range(0.0, 90.0) var melee_cone_degrees: float = 36.87
## A hit from behind (the attacker within this angle of the target's back)
## uses the weapon's direct (back-stab) damage.
@export_range(0.0, 90.0) var backstab_degrees: float = 60.0

@export_group("Scoring")
## Damage that earns an assist when someone else gets the kill.
@export var assist_damage: float = 40.0
## Damage older than this doesn't count for an assist.
@export var assist_ticks: int = 300
@export var max_assists: int = 3

@export_group("Pickups")
## How close (metres) a player has to be to pick something up.
@export var pickup_radius: float = 1.2
## A dropped weapon disappears after this long.
@export var drop_despawn_ticks: int = 1200


func shield_regen_per_tick() -> float:
	return shield_regen_per_second / Sim.TICK_RATE


func health_regen_per_tick() -> float:
	return health_regen_per_second / Sim.TICK_RATE
