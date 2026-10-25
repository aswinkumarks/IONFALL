class_name BotConfig
extends Resource
## Bot tuning (data/bots.tres, read through BotBrain.CONFIG): the difficulty
## levels, what bots notice and how they fight. Part of the compatibility
## hash, like everything in data/. Distances are metres, times ticks (60
## per second).

## Easy, Normal, Hard, Insane, in that order (the lobby's difficulty picks
## one; co-op waves step up through them).
@export var difficulties: Array[BotDifficulty] = []

@export_group("Perception")
## Targets farther than this are never seen.
@export var view_range: float = 60.0
## Field of view, degrees across.
@export_range(10.0, 360.0) var field_of_view_degrees: float = 126.7
## Targets this close are noticed at any angle.
@export var close_awareness: float = 6.0
## How long a bot keeps chasing a target it lost sight of.
@export var chase_memory_ticks: int = 300

@export_group("Fighting")
## Closer than this a bot backs off while strafing; farther than
## approach_beyond it closes in; farther than follow_beyond it walks a path
## to the target instead of strafing.
@export var back_off_within: float = 7.0
@export var approach_beyond: float = 18.0
@export var follow_beyond: float = 25.0
## Bots aim down sights at targets this far or farther.
@export var scope_range: float = 10.0
@export var melee_range: float = 1.8
## Splash weapons (Arc Launcher) are used only in this range band (closer
## hurts the bot; the sidearm is used instead).
@export var splash_min_range: float = 6.0
@export var splash_max_range: float = 30.0
## Grenades are thrown at targets in this range band.
@export var grenade_min_range: float = 7.0
@export var grenade_max_range: float = 18.0

@export_group("Retreating")
## A bot retreats to regenerate when its shield is down, its health below
## retreat_health and the target has more than retreat_margin more shield
## plus health than it has health.
@export var retreat_health: float = 45.0
@export var retreat_margin: float = 20.0
## It keeps retreating for this long, or until its shield is back above
## retreat_until_shield.
@export var retreat_ticks: int = 360
@export var retreat_until_shield: float = 60.0

@export_group("Pickups")
## Out of combat, bots fetch power weapons and grenades this close.
@export var power_fetch_range: float = 35.0
@export var grenade_fetch_range: float = 15.0


func difficulty(level: int) -> BotDifficulty:
	return difficulties[clampi(level, 0, difficulties.size() - 1)]
