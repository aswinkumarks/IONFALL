class_name Balance
extends RefCounted
## The balance configuration files, loaded once. Weapons have their own
## files (data/weapons, Weapons), as does movement (data/movement_config.tres)
## and the bots (data/bots.tres, BotBrain.CONFIG).

const PLAYER: PlayerConfig = preload("res://data/player.tres")
const MODES: ModeConfig = preload("res://data/modes.tres")
