class_name BotDifficulty
extends Resource
## One bot difficulty level (an entry of BotConfig.difficulties). Higher
## levels only react faster and aim with less error (PLAN §2.7): no level
## sees through walls or aims perfectly.

@export var name: String = ""
## From first seeing a target to the first shot, in ticks (60 per second).
@export var reaction_ticks: int = 15
## How fast the bot can turn its aim.
@export var turn_speed_degrees_per_second: float = 343.8
## Aim wobble around the target, in degrees; bigger misses more.
@export var aim_error_degrees: float = 3.04
## Extra aim error per m/s the target moves sideways (strafing targets are
## harder to hit).
@export var moving_target_error_degrees: float = 0.52
## Chance to throw a grenade at a target seen in grenade range.
@export_range(0.0, 1.0) var grenade_chance: float = 0.2
## How much of its weapon's recoil the bot pulls back down (0: none, 1:
## all of it), like a player holding a gun on target.
@export_range(0.0, 1.0) var recoil_control: float = 0.5
