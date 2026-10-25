class_name StationLayout
extends RefCounted
## Map 1, "Meridian Station": a hab deck under an observation dome on an
## orbital research station (PLAN §4 theme). Collision (gameplay scene) and
## meshes (generated presentation scene, tools/build_map.gd) both come from
## this data, so they can't disagree; the presentation records layout_hash()
## and a test fails if it is stale.
##
## Layout (top view, -Z is north): raised lab decks along the north and south
## hulls (top 2.5 m), joined by two catwalk bridges at x = ±11; the ion core
## in the centre; corner ramps; mantle crates in front of the decks; lab
## modules (top 3.0 m, double-jump + mantle) on the east and west lanes.
## Mirror-symmetric in X and Z for FFA fairness. Floor top is y = 0; play
## area 48 × 40 m.

enum Kind {
	FLOOR, HULL, DECK, RAMP, BRIDGE, CRATE, COVER, CORE, MODULE, PILLAR,
	# Visual only (no collision):
	TRIM_CYAN, TRIM_ORANGE, RIB, BEAM, CORE_GLOW, HAZARD,
}

const RAMP_ANGLE := 17.35  ## atan(2.5 / 8)
const DECK_TOP := 2.5


static func has_collision(kind: int) -> bool:
	return kind < Kind.TRIM_CYAN


## Each box: [kind, centre, size, rotation_x_degrees].
static func boxes() -> Array:
	var out := [
		[Kind.FLOOR, Vector3(0, -0.5, 0), Vector3(52, 1, 44), 0.0],
		[Kind.HULL, Vector3(0, 4, -21), Vector3(52, 8, 2), 0.0],
		[Kind.HULL, Vector3(0, 4, 21), Vector3(52, 8, 2), 0.0],
		[Kind.HULL, Vector3(25, 4, 0), Vector3(2, 8, 40), 0.0],
		[Kind.HULL, Vector3(-25, 4, 0), Vector3(2, 8, 40), 0.0],
		[Kind.CORE, Vector3(0, 4, 0), Vector3(3, 8, 3), 0.0],
	]
	for sz in [-1.0, 1.0]:
		# Lab deck and its corner extensions, ramps down toward the centre line.
		out.append([Kind.DECK, Vector3(0, 1.25, 16 * sz), Vector3(30, 2.5, 8), 0.0])
		for sx in [-1.0, 1.0]:
			out.append([Kind.DECK, Vector3(19.5 * sx, 1.25, 17 * sz), Vector3(9, 2.5, 6), 0.0])
			out.append([Kind.RAMP, Vector3(19.5 * sx, 1.011, 10 * sz), Vector3(4, 0.5, 8.38), -RAMP_ANGLE * sz])
			out.append([Kind.CRATE, Vector3(5 * sx, 0.6, 10.6 * sz), Vector3(2, 1.2, 2), 0.0])
			out.append([Kind.COVER, Vector3(4.5 * sx, 0.6, 4.5 * sz), Vector3(2, 1.2, 0.8), 0.0])
			out.append([Kind.COVER, Vector3(15.5 * sx, 0.6, 4 * sz), Vector3(1, 1.2, 2.5), 0.0])
	for sx in [-1.0, 1.0]:
		out.append([Kind.BRIDGE, Vector3(11 * sx, 2.35, 0), Vector3(3, 0.3, 24), 0.0])
		out.append([Kind.PILLAR, Vector3(11 * sx, 1.1, 0), Vector3(0.6, 2.2, 0.6), 0.0])
		out.append([Kind.MODULE, Vector3(20 * sx, 1.5, 0), Vector3(4, 3, 6), 0.0])
	return out


## Visual-only detail: emissive edge trims, hull ribs, dome beams, core glow,
## hazard stripes. Nothing here sticks out more than 0.15 m from a collider
## or sits below 9 m in open space.
static func decor() -> Array:
	var out := []
	# Hull: ribs every 4 m and a cyan strip at floor level and at 6 m.
	for x in range(-22, 23, 4):
		for sz in [-1.0, 1.0]:
			out.append([Kind.RIB, Vector3(x, 4, 19.93 * sz), Vector3(0.6, 8, 0.15), 0.0])
	for z in range(-16, 17, 4):
		for sx in [-1.0, 1.0]:
			out.append([Kind.RIB, Vector3(23.93 * sx, 4, z), Vector3(0.15, 8, 0.6), 0.0])
	for sz in [-1.0, 1.0]:
		out.append([Kind.TRIM_CYAN, Vector3(0, 6.2, 19.84 * sz), Vector3(48, 0.12, 0.08), 0.0])
		out.append([Kind.TRIM_CYAN, Vector3(0, 0.04, 11.97 * sz), Vector3(30, 0.08, 0.08), 0.0])  # deck foot
		out.append([Kind.TRIM_CYAN, Vector3(0, 2.46, 11.96 * sz), Vector3(30, 0.08, 0.1), 0.0])  # deck lip
	for sx in [-1.0, 1.0]:
		out.append([Kind.TRIM_CYAN, Vector3(23.84 * sx, 6.2, 0), Vector3(0.08, 0.12, 40), 0.0])
		# Bridge edges and lab module bands.
		for side in [-1.0, 1.0]:
			out.append([Kind.TRIM_CYAN, Vector3(11 * sx + 1.53 * side, 2.38, 0), Vector3(0.06, 0.08, 24), 0.0])
		out.append([Kind.TRIM_ORANGE, Vector3(20 * sx, 2.2, 0), Vector3(4.06, 0.12, 6.06), 0.0])
		for sz in [-1.0, 1.0]:
			# Corner deck lips above the ramps.
			out.append([Kind.TRIM_CYAN, Vector3(19.5 * sx, 2.46, 13.96 * sz), Vector3(9, 0.08, 0.1), 0.0])
			# Hazard stripes on crate tops and ramp feet.
			out.append([Kind.HAZARD, Vector3(5 * sx, 1.205, 10.6 * sz), Vector3(1.8, 0.02, 1.8), 0.0])
			out.append([Kind.HAZARD, Vector3(19.5 * sx, 0.01, 5.6 * sz), Vector3(4, 0.02, 0.6), 0.0])
	# Core: vertical slits on each face and the glowing ion column above it.
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var size := Vector3(0.06, 6.5, 0.4) if d.x != 0.0 else Vector3(0.4, 6.5, 0.06)
		out.append([Kind.CORE_GLOW, d * 1.52 + Vector3(0, 4.25, 0), size, 0.0])
	out.append([Kind.CORE_GLOW, Vector3(0, 9.5, 0), Vector3(1.6, 3, 1.6), 0.0])
	for s in [-1.0, 1.0]:  # floor ring around the core
		out.append([Kind.TRIM_CYAN, Vector3(0, 0.02, 3.5 * s), Vector3(7.15, 0.04, 0.15), 0.0])
		out.append([Kind.TRIM_CYAN, Vector3(3.5 * s, 0.02, 0), Vector3(0.15, 0.04, 7.15), 0.0])
	# Observation dome frame: beams overhead.
	for x in range(-18, 19, 9):
		out.append([Kind.BEAM, Vector3(x, 12, 0), Vector3(0.5, 0.6, 42), 0.0])
	for z in [-14, 0, 14]:
		out.append([Kind.BEAM, Vector3(0, 11.6, z), Vector3(50, 0.5, 0.5), 0.0])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append([Kind.BEAM, Vector3(24 * sx, 10, 20 * sz), Vector3(1, 4, 1), 0.0])
	return out


## Baked accent lights: [position, color, energy, range].
static func lights() -> Array:
	var cyan := Color(0.35, 0.9, 1.0)
	var orange := Color(1.0, 0.6, 0.25)
	var out := [[Vector3(0, 9, 0), cyan, 4.0, 14.0]]
	for sx in [-1.0, 1.0]:
		out.append([Vector3(20 * sx, 4.5, 0), orange, 2.5, 9.0])
		for sz in [-1.0, 1.0]:
			out.append([Vector3(9 * sx, 1.8, 9.0 * sz), cyan, 0.9, 6.0])
			out.append([Vector3(19.5 * sx, 4.5, 17 * sz), cyan, 2.0, 8.0])
	return out


## Spawn points facing the centre: 4 on the decks, 4 on the floor.
static func spawn_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for p in [Vector3(8, 2.6, 17), Vector3(-8, 2.6, -17), Vector3(-8, 2.6, 17), Vector3(8, 2.6, -17),
			Vector3(14.5, 0.1, 0), Vector3(-14.5, 0.1, 0), Vector3(0, 0.1, 9), Vector3(0, 0.1, -9)]:
		var yaw := atan2(p.x, p.z)
		out.append(Transform3D(Basis(Vector3.UP, yaw), p))
	return out


## Pickup spots (PLAN §2.3): the power weapons mid-bridge (Rail Sniper west,
## Arc Launcher east), grenades on the floor beside the core.
static func pickup_spots() -> Array:
	var out := [
		{"weapon": &"rail_sniper", "position": Vector3(-11, 2.5, 0), "respawn_ticks": 7200},
		{"weapon": &"arc_launcher", "position": Vector3(11, 2.5, 0), "respawn_ticks": 5400},
	]
	for sx in [-1.0, 1.0]:
		out.append({"weapon": &"grenade", "position": Vector3(7 * sx, 0, 0), "respawn_ticks": 1200})
	return out


## CTF flag bases (PLAN §2.4): team 0 (west) and team 1 (east), on the floor
## at the ends of the core's lane.
static func flag_bases() -> Array:
	# In front of the end modules (solid blocks at x = ±20; a base inside one
	# couldn't be touched), clear of the spawns at x = ±14.5.
	return [Vector3(-17, 0, 0), Vector3(17, 0, 0)]


## Hash of everything the presentation is built from.
static func layout_hash() -> String:
	return var_to_str([boxes(), decor(), lights()]).sha256_text()
