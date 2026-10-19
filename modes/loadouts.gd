class_name Loadouts
extends RefCounted
## Loadouts per mode (PLAN §2.3). Part of the compatibility hash: every peer
## must agree on slot order. Power-weapon pickups replace the primary in M3;
## until then the Arc Launcher sits in slot 3.

const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const PISTOL := preload("res://data/weapons/mag_pistol.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")


static func ffa() -> Array[WeaponData]:
	var l: Array[WeaponData] = [PULSE, PISTOL, ARC]
	return l
