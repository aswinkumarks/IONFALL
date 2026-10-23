class_name Weapons
extends RefCounted
## Every weapon by its wire index (PLAN §2.3). Slots in PlayerSimState hold
## these indices, so a pickup can put any weapon in a slot. The order is part
## of the protocol: append only.

const ALL: Array[WeaponData] = [
	preload("res://data/weapons/pulse_rifle.tres"),
	preload("res://data/weapons/arc_launcher.tres"),
	preload("res://data/weapons/burst_rifle.tres"),
	preload("res://data/weapons/mag_pistol.tres"),
	preload("res://data/weapons/rail_sniper.tres"),
	preload("res://data/weapons/scatter_gun.tres"),
	preload("res://data/weapons/frag_grenade.tres"),
	preload("res://data/weapons/melee.tres"),
	preload("res://data/weapons/flux_smg.tres"),
]
const PULSE := 0
const ARC := 1
const BURST := 2
const PISTOL := 3
const RAIL := 4
const SCATTER := 5
const FRAG := 6
const MELEE := 7
const SMG := 8


static func at(index: int) -> WeaponData:
	return ALL[index] if index >= 0 and index < ALL.size() else null


static func index_of(id: StringName) -> int:
	for i in ALL.size():
		if ALL[i].id == id:
			return i
	return -1


static func by_id(id: StringName) -> WeaponData:
	return at(index_of(id))
