class_name Loadouts
extends RefCounted
## Spawn loadouts (PLAN §2.3, §2.5): a chosen primary plus the Mag Pistol.
## Power weapons (Rail Sniper, Arc Launcher) are map pickups that replace the
## primary for one life. Part of the compatibility hash: every peer must
## agree on the order.

const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const BURST := preload("res://data/weapons/burst_rifle.tres")
const SCATTER := preload("res://data/weapons/scatter_gun.tres")
const PISTOL := preload("res://data/weapons/mag_pistol.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")
const RAIL := preload("res://data/weapons/rail_sniper.tres")
const SMG := preload("res://data/weapons/flux_smg.tres")
## Choosable primaries, by loadout index.
const PRIMARIES: Array[WeaponData] = [PULSE, BURST, SCATTER, SMG]


## The loadout for primary choice `index` (clamped).
static func make(index: int = 0) -> Array[WeaponData]:
	var l: Array[WeaponData] = [PRIMARIES[clampi(index, 0, PRIMARIES.size() - 1)], PISTOL]
	return l


## The default loadout (Pulse Rifle + Mag Pistol).
static func ffa() -> Array[WeaponData]:
	return make(0)
