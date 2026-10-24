class_name SpireLayout
extends RefCounted
## Map 2, "Halcyon Spire": an open-air research platform on a moon, built
## from the Quaternius Modular Sci-Fi MegaKit and Sci-Fi Essentials Kit
## (CC0). Like Meridian Station, collision (gameplay scene) and the
## generated presentation (tools/build_spire.gd) both come from this data;
## the presentation records layout_hash() and a test fails if it is stale.
##
## Layout (top view, -Z is north; mirror-symmetric in X and Z): a raised
## plaza (top 4 m) round the central spire, open underneath, with ramps on
## its north and south sides; bridges east and west to the rooftops of two
## bases (ground floor rooms with three doors each and an inner ramp to the
## roof); indoor flank corridors along the north and south hulls whose roofs
## are walkways, with ramps down at their ends; half walls, crates, barrels
## and columns across the lanes and courtyards. Floor top is y = 0; play
## area 72 × 56 m.

enum Kind {
	FLOOR, WALL, SLAB, RAMP, COVER, PROP, COLUMN, SPIRE, BOUND,
	# Visual only (no collision):
	TRIM_CYAN, TRIM_ORANGE, SPIRE_GLOW,
}

const HALF_X := 36.0
const HALF_Z := 28.0
const DECK := 4.0  ## top of the upper level
const SLOPE := 26.565  ## atan(4 / 8): every ramp climbs 4 m over 8 m
## Kit models live in one folder; "megakit/" and "essentials/" name their kit.
const KIT_DIR := "res://art/environment/scifi/"
## Kit props used as cover: model -> collision size (its bounds, unrotated).
const PROP_SIZES := {
	"essentials/Prop_Crate_Large": Vector3(3.47, 1.5, 1.5),
	"essentials/Prop_Crate": Vector3(1.57, 1.5, 1.5),
	"essentials/Prop_Crate_Tarp_Large": Vector3(3.22, 1.57, 1.72),
	"essentials/Prop_SatelliteDish": Vector3(1.84, 5.79, 2.78),
	"essentials/Prop_Desk_Medium": Vector3(2.84, 0.94, 1.03),
	"essentials/Prop_Locker": Vector3(0.98, 2.67, 0.5),
	"megakit/Prop_Crate4": Vector3(1.12, 1.12, 1.12),
	"megakit/Prop_Barrel_Large": Vector3(0.51, 1.1, 0.53),
}


## The scene file of a kit model ("megakit/Column_Round").
static func model_path(model: String) -> String:
	return KIT_DIR + model.get_file() + ".gltf"


static func has_collision(kind: int) -> bool:
	return kind < Kind.TRIM_CYAN


## Each box: [kind, centre, size, rotation (Euler degrees)].
static func boxes() -> Array:
	var out := [
		[Kind.FLOOR, Vector3(0, -0.5, 0), Vector3(80, 1, 64), Vector3.ZERO],
		[Kind.SLAB, Vector3(0, 3.75, 0), Vector3(20, 0.5, 16), Vector3.ZERO],  # plaza
		[Kind.SPIRE, Vector3(0, 10, 0), Vector3(3, 20, 3), Vector3.ZERO],
	]
	for sx in [-1.0, 1.0]:
		out.append([Kind.BOUND, Vector3((HALF_X + 0.5) * sx, 10, 0), Vector3(1, 20, 64), Vector3.ZERO])
		out.append([Kind.WALL, Vector3(35.75 * sx, 2, 0), Vector3(0.5, 4, 56), Vector3.ZERO])
		out.append([Kind.SLAB, Vector3(16 * sx, 3.85, 0), Vector3(12, 0.3, 3), Vector3.ZERO])  # bridge
		# Base: three doors (west face and both ends), roof at DECK with an inner ramp up.
		out.append([Kind.WALL, Vector3(22.25 * sx, 2, -5), Vector3(0.5, 4, 6), Vector3.ZERO])
		out.append([Kind.WALL, Vector3(22.25 * sx, 2, 5), Vector3(0.5, 4, 6), Vector3.ZERO])
		out.append([Kind.SLAB, Vector3(26.5 * sx, 3.75, 0), Vector3(9, 0.5, 16), Vector3.ZERO])
		out.append([Kind.SLAB, Vector3(33.25 * sx, 3.75, 4.25), Vector3(4.5, 0.5, 7.5), Vector3.ZERO])
		out.append([Kind.RAMP, Vector3(33.375 * sx, 1.776, -3.388), Vector3(3.75, 0.5, 8.944), Vector3(-SLOPE, 0, 0)])
		for sz in [-1.0, 1.0]:
			out.append([Kind.WALL, Vector3(23 * sx, 2, 7.75 * sz), Vector3(2, 4, 0.5), Vector3.ZERO])
			out.append([Kind.WALL, Vector3(31.75 * sx, 2, 7.75 * sz), Vector3(7.5, 4, 0.5), Vector3.ZERO])
			# Plaza supports and ramps, corridor-roof ramps.
			out.append([Kind.COLUMN, Vector3(8 * sx, 1.75, 6 * sz), Vector3(0.8, 3.5, 0.8), Vector3.ZERO])
			out.append([Kind.RAMP, Vector3(6 * sx, 1.776, 11.888 * sz), Vector3(4, 0.5, 8.944), Vector3(SLOPE * sz, 0, 0)])
			out.append([Kind.RAMP, Vector3(22 * sx, 1.776, 15.888 * sz), Vector3(4, 0.5, 8.944), Vector3(-SLOPE * sz, 0, 0)])
			out.append([Kind.COLUMN, Vector3(17 * sx, 2.5, 5 * sz), Vector3(1, 5, 1), Vector3.ZERO])
			# Cover: lane half walls, a wall by each centre door, under-plaza walls.
			out.append([Kind.COVER, Vector3(14 * sx, 0.6, 12 * sz), Vector3(3, 1.2, 0.5), Vector3.ZERO])
			out.append([Kind.COVER, Vector3(4 * sx, 0.6, 18 * sz), Vector3(0.5, 1.2, 3), Vector3.ZERO])
	for sz in [-1.0, 1.0]:
		out.append([Kind.BOUND, Vector3(0, 10, (HALF_Z + 0.5) * sz), Vector3(80, 20, 1), Vector3.ZERO])
		out.append([Kind.WALL, Vector3(0, 2, 27.75 * sz), Vector3(72, 4, 0.5), Vector3.ZERO])
		# Corridor: inner wall with three doors, roof walkway with a parapet.
		out.append([Kind.SLAB, Vector3(0, 3.75, 24 * sz), Vector3(48, 0.5, 8), Vector3.ZERO])
		for seg: Vector2 in [Vector2(-17, 6), Vector2(-6, 8), Vector2(6, 8), Vector2(17, 6)]:
			out.append([Kind.WALL, Vector3(seg.x, 1.75, 21.25 * sz), Vector3(seg.y, 3.5, 0.5), Vector3.ZERO])
		out.append([Kind.COVER, Vector3(0, 4.45, 20.05 * sz), Vector3(40, 0.9, 0.1), Vector3.ZERO])
	for sx in [-1.0, 1.0]:
		out.append([Kind.COVER, Vector3(5 * sx, 0.6, 0), Vector3(0.5, 1.2, 3), Vector3.ZERO])
	for p in props():
		var size: Vector3 = PROP_SIZES[p[0]]
		if absf(fmod(p[2], 180.0)) > 45.0:
			size = Vector3(size.z, size.y, size.x)
		out.append([Kind.PROP, p[1] + Vector3(0, size.y * 0.5, 0), size, Vector3.ZERO])
	return out


## Cover props: [model, position on the floor, yaw degrees] (quadrant
## entries mirrored to all four quadrants).
static func props() -> Array:
	var quad := [
		["essentials/Prop_Crate_Large", Vector3(16, 0, 17), 0.0],
		["essentials/Prop_Crate", Vector3(28, 0, 12), 0.0],
		["essentials/Prop_Crate_Tarp_Large", Vector3(29, 0, 19), 90.0],
		["megakit/Prop_Barrel_Large", Vector3(33.5, 0, 12.5), 0.0],
		["megakit/Prop_Barrel_Large", Vector3(34.2, 0, 13.4), 0.0],
		["essentials/Prop_SatelliteDish", Vector3(31, 0, 25), 0.0],
		["essentials/Prop_Desk_Medium", Vector3(26, 0, 5), 90.0],
		["essentials/Prop_Locker", Vector3(30, 0, 7.25), 0.0],
		["megakit/Prop_Crate4", Vector3(2.6, 0, 4), 0.0],
		["megakit/Prop_Crate4", Vector3(10.5, 0, 9.2), 0.0],
		["megakit/Prop_Barrel_Large", Vector3(11.4, 0, 8.6), 0.0],
	]
	var out := []
	for p in quad:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var yaw: float = p[2] if sx * sz > 0.0 else -p[2]
				out.append([p[0], Vector3(p[1].x * sx, p[1].y, p[1].z * sz), yaw])
	return out


## Visual-only detail: emissive edge trims and the spire's glow.
static func decor() -> Array:
	var out := []
	for s in [-1.0, 1.0]:
		out.append([Kind.TRIM_CYAN, Vector3(0, 3.97, 8.02 * s), Vector3(20, 0.06, 0.06), Vector3.ZERO])
		out.append([Kind.TRIM_CYAN, Vector3(10.02 * s, 3.97, 0), Vector3(0.06, 0.06, 16), Vector3.ZERO])
		out.append([Kind.TRIM_CYAN, Vector3(0, 3.97, 19.98 * s), Vector3(48, 0.06, 0.06), Vector3.ZERO])
		out.append([Kind.TRIM_CYAN, Vector3(0, 4.92, 20.05 * s), Vector3(40, 0.04, 0.12), Vector3.ZERO])  # parapet top
		out.append([Kind.TRIM_ORANGE, Vector3(22 * s, 4.25, 0), Vector3(0.12, 0.08, 4), Vector3.ZERO])
		for t in [-1.0, 1.0]:
			out.append([Kind.TRIM_CYAN, Vector3(16 * s, 3.97, 1.52 * t), Vector3(12, 0.06, 0.06), Vector3.ZERO])
			out.append([Kind.TRIM_CYAN, Vector3(14 * s, 1.22, 12 * t), Vector3(3, 0.04, 0.52), Vector3.ZERO])
			out.append([Kind.TRIM_CYAN, Vector3(4 * s, 1.22, 18 * t), Vector3(0.52, 0.04, 3), Vector3.ZERO])
			out.append([Kind.TRIM_ORANGE, Vector3(26 * s, 4.25, 7.5 * t), Vector3(4, 0.08, 0.12), Vector3.ZERO])
	# Ceiling light strips: corridors, bases, under the plaza.
	for s in [-1.0, 1.0]:
		out.append([Kind.TRIM_CYAN, Vector3(0, 3.47, 24.5 * s), Vector3(38, 0.04, 0.3), Vector3.ZERO])
		out.append([Kind.TRIM_CYAN, Vector3(26.5 * s, 3.47, 0), Vector3(0.3, 0.04, 14), Vector3.ZERO])
		out.append([Kind.TRIM_CYAN, Vector3(5 * s, 3.47, 0), Vector3(0.3, 0.04, 14), Vector3.ZERO])
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var size := Vector3(0.06, 14, 0.3) if d.x != 0.0 else Vector3(0.3, 14, 0.06)
		out.append([Kind.SPIRE_GLOW, d * 1.52 + Vector3(0, 12, 0), size, Vector3.ZERO])
	out.append([Kind.SPIRE_GLOW, Vector3(0, 20.6, 0), Vector3(1.2, 1.2, 1.2), Vector3.ZERO])
	return out


## Kit pieces (visual only): [model (kit/name, see model_path()),
## Transform3D]. Floors and decks tiled with plates, ramps from ramp wedges,
## walls clad with panels, door frames, columns and the cover props.
static func pieces() -> Array:
	var out := []
	# Ground: plain plates, dark plates in the bases and under the plaza,
	# square plates in the corridors.
	for i in 18:
		for j in 14:
			var c := Vector3(-34 + 4 * i, 0.003, -26 + 4 * j)
			var model := "megakit/Platform_Metal"
			if absf(c.x) > 22.0 and absf(c.z) < 8.0 or absf(c.x) < 10.0 and absf(c.z) < 8.0:
				model = "megakit/Platform_DarkPlates"
			elif absf(c.z) > 21.0 and absf(c.x) < 20.0:
				model = "megakit/Platform_Squares"
			out.append([model, Transform3D(Basis(), c)])
	# Decks.
	_tile(out, "megakit/Platform_Metal2", -10, 10, -8, 8, DECK)
	for s in [-1.0, 1.0]:
		_tile(out, "megakit/Platform_Metal2", -24, 24, 20 * s if s > 0 else -28, 28 if s > 0 else -20, DECK)
		_tile(out, "megakit/Platform_DarkPlates", minf(10 * s, 22 * s), maxf(10 * s, 22 * s), -1.5, 1.5, DECK)
		_tile(out, "megakit/Platform_Metal2", minf(22 * s, 31 * s), maxf(22 * s, 31 * s), -8, 8, DECK)
		_tile(out, "megakit/Platform_Metal2", minf(31 * s, 35.5 * s), maxf(31 * s, 35.5 * s), 0.5, 8, DECK)
	# Ramps: [top edge centre, downhill direction].
	for sx in [-1.0, 1.0]:
		_ramp(out, Vector3(33.375 * sx, DECK, 0.5), Vector3(0, 0, -1), 3.75)
		for sz in [-1.0, 1.0]:
			_ramp(out, Vector3(6 * sx, DECK, 8 * sz), Vector3(0, 0, sz), 4.0)
			_ramp(out, Vector3(22 * sx, DECK, 20 * sz), Vector3(0, 0, -sz), 4.0)
	# Walls: clad every face that can be seen.
	for b in boxes():
		if b[0] == Kind.WALL:
			_clad(out, b[1], b[2])
	# Door frames: base doors and corridor doors.
	for sx in [-1.0, 1.0]:
		_door(out, Vector3(22.25 * sx, 0, 0), Vector3(1, 0, 0), 4.0)
		for sz in [-1.0, 1.0]:
			_door(out, Vector3(26 * sx, 0, 7.75 * sz), Vector3(0, 0, 1), 4.0)
	for sz in [-1.0, 1.0]:
		for x in [-12.0, 0.0, 12.0]:
			_door(out, Vector3(x, 0, 21.25 * sz), Vector3(0, 0, 1), 3.5)
	# Columns: plaza supports, lane columns, the spire.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append(["megakit/Column_Round", Transform3D(Basis().scaled(Vector3(0.8, 0.75, 0.8)), Vector3(8 * sx, 0, 6 * sz))])
			out.append(["megakit/Column_Round", Transform3D(Basis(), Vector3(17 * sx, 0, 5 * sz))])
	out.append(["megakit/Column_Round", Transform3D(Basis().scaled(Vector3(3, 4, 3)), Vector3.ZERO)])
	for p in props():
		out.append([p[0], Transform3D(Basis(Vector3.UP, deg_to_rad(p[2])), p[1])])
	return out


## Plates covering the rectangle [x0, x1] × [z0, z1] at height y (cells of
## up to 4 m, scaled to fit).
static func _tile(out: Array, model: String, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var nx := ceili((x1 - x0) / 4.0 - 0.001)
	var nz := ceili((z1 - z0) / 4.0 - 0.001)
	var w := (x1 - x0) / nx
	var d := (z1 - z0) / nz
	for i in nx:
		for j in nz:
			out.append([model, Transform3D(Basis().scaled(Vector3(w / 4.0, 1, d / 4.0)),
					Vector3(x0 + w * (i + 0.5), y + 0.003, z0 + d * (j + 0.5)))])


## A 4 m-high ramp of ramp wedges (2 m wide, 2 m rise over 4 m each): two
## rows down `downhill` from the top edge centre, `width` across.
static func _ramp(out: Array, top: Vector3, downhill: Vector3, width: float) -> void:
	var side := Vector3.UP.cross(downhill)
	var basis := Basis(side * (width / 4.0), Vector3.UP, downhill)
	for k in 2:
		for j in [-1.0, 1.0]:
			out.append(["megakit/Platform_Ramp_4", Transform3D(basis,
					top + downhill * 4.0 * k + side * (width / 4.0) * j - Vector3(0, 2.0 + 2.0 * k, 0))])


## Panels on the faces of a wall box: the 3 m panel plus a band above it to
## the wall's height, in segments of up to 4 m. Hull walls are only seen
## from inside and get the deep Astra panels and cable tops; walls beyond
## `hull_x` or `hull_z` from the centre are hull walls.
static func _clad(out: Array, centre: Vector3, size: Vector3, hull_x := 35.0, hull_z := 27.0) -> void:
	var along_x := size.x > size.z
	var length := size.x if along_x else size.z
	var t := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var n0 := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var hull := absf(centre.x) > hull_x or absf(centre.z) > hull_z
	var top := centre.y + size.y * 0.5
	var count := ceili(length / 4.0 - 0.001)
	var seg := length / count
	for n: Vector3 in [n0, -n0]:
		if hull and n.dot(centre) > 0.0:
			continue  # the hull's outer face
		var face := centre + n * (size.x if not along_x else size.z) * 0.5
		var tt := t if n.is_equal_approx(Vector3.UP.cross(t)) else -t
		var basis := Basis(n, Vector3.UP, tt)
		for i in count:
			var p := face + t * (-length * 0.5 + seg * (i + 0.5))
			p.y = 0.0
			var origin := p + n * 2.01
			var panel := "megakit/WallAstra_Straight" if hull else "megakit/WallAstra_Straight_Flat"
			out.append([panel, Transform3D(basis * Basis().scaled(Vector3(1, 1, seg / 4.0)), origin)])
			if hull:
				out.append(["megakit/TopAstra_Straight", Transform3D(basis * Basis().scaled(Vector3(1, 1, seg / 4.0)), origin)])
			elif top > 3.01:
				out.append(["megakit/ShortWall_Metal2_Straight", Transform3D(
						basis * Basis().scaled(Vector3(1, (top - 3.0) / 2.0, seg / 4.0)), origin + Vector3(0, 3.0, 0))])


## A door frame in a wall gap: centred at `at` (floor level), facing
## `normal`, `height` tall.
static func _door(out: Array, at: Vector3, normal: Vector3, height: float) -> void:
	var x := Vector3.UP.cross(normal)
	out.append(["megakit/Door_Frame_Square", Transform3D(Basis(x, Vector3.UP * (height / 5.0), normal), at)])


## Baked accent lights: [position, color, energy, range].
static func lights() -> Array:
	var cyan := Color(0.35, 0.9, 1.0)
	var orange := Color(1.0, 0.6, 0.25)
	var out := [[Vector3(0, 14, 0), cyan, 5.0, 18.0]]
	for sx in [-1.0, 1.0]:
		out.append([Vector3(26 * sx, 3.2, 0), orange, 5.0, 11.0])
		out.append([Vector3(32 * sx, 3.2, 4), cyan, 4.0, 9.0])
		for sz in [-1.0, 1.0]:
			out.append([Vector3(5 * sx, 3.0, 4 * sz), cyan, 4.0, 9.0])  # under the plaza
			out.append([Vector3(30 * sx, 4.0, 20 * sz), cyan, 1.5, 9.0])
			out.append([Vector3(14 * sx, 2.5, 12 * sz), cyan, 0.8, 6.0])
	for sz in [-1.0, 1.0]:
		for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
			out.append([Vector3(x, 3.1, 24.5 * sz), cyan, 5.0, 9.0])
	return out


## Spawn points facing the centre: base floors and roofs, courtyards, corridors.
static func spawn_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for p in [Vector3(27.5 * sx, 0.05, 2.5 * sz), Vector3(25 * sx, DECK + 0.05, 5 * sz),
					Vector3(31 * sx, 0.05, 16 * sz)]:
				out.append(Transform3D(Basis(Vector3.UP, atan2(p.x, p.z)), p))
			# Corridor spawns look along the corridor, towards the centre door.
			out.append(Transform3D(Basis(Vector3.UP, atan2(sx, 0.0)), Vector3(8 * sx, 0.05, 24.5 * sz)))
	return out


## Pickup spots (PLAN §2.3): the Rail Sniper on the plaza, the Arc
## Launcher under it, grenades in the side lanes and on the corridor roofs.
static func pickup_spots() -> Array:
	var out := [
		{"weapon": &"rail_sniper", "position": Vector3(0, DECK, -5.5), "respawn_ticks": 7200},
		{"weapon": &"arc_launcher", "position": Vector3(0, 0, 4.5), "respawn_ticks": 5400},
	]
	for s in [-1.0, 1.0]:
		out.append({"weapon": &"grenade", "position": Vector3(12 * s, 0, 0), "respawn_ticks": 1200})
		out.append({"weapon": &"grenade", "position": Vector3(0, DECK, 24 * s), "respawn_ticks": 1200})
	return out


## Jump pads (JumpPads): one in each side lane, by the lane half wall,
## up onto the plaza corner (12 m, over the under-croft's edge).
static func jump_pads() -> Array:
	var out := []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append({"position": Vector3(15 * sx, 0, 14.5 * sz), "target": Vector3(6.5 * sx, DECK, 4.5 * sz)})
	return out


## CTF flag bases (PLAN §2.4): inside the west (team 0) and east (team 1)
## bases, under their roofs.
static func flag_bases() -> Array:
	return [Vector3(-28.5, 0, 0), Vector3(28.5, 0, 0)]


## Hash of everything the presentation is built from.
static func layout_hash() -> String:
	return var_to_str([boxes(), decor(), pieces(), lights()]).sha256_text()
