class_name FoundryLayout
extends RefCounted
## Map 3, "Vesper Foundry": an ore refinery yard on a volcanic moon, built
## from the same Quaternius kits as Halcyon Spire (CC0) and the same
## pipeline (tools/build_spire.gd --map foundry); the presentation records
## layout_hash() and a test fails if it is stale.
##
## Layout (top view, -Z is north; mirror-symmetric in X and Z): the
## crucible in the middle ringed by low cover; catwalks (top 4 m) along its
## north and south sides with ramps down at both ends; loading bays east
## and west (ground floor rooms with a front door and two side doors, roofs
## reached by ramps along the hull); outer flank lanes along the north and
## south hulls with crates and barrels. Floor top is y = 0; play area
## 56 × 40 m, tighter than Meridian Station for close-range fights.

const Kind := SpireLayout.Kind

const HALF_X := 28.0
const HALF_Z := 20.0
const DECK := 4.0  ## top of the catwalks and bay roofs
const SLOPE := SpireLayout.SLOPE
## Uphill shift of a ramp box's centre from the middle of its surface
## (half its 0.5 m thickness along the tilted normal).
const RAMP_SHIFT := 0.1118
const PROP_SIZES := SpireLayout.PROP_SIZES


static func model_path(model: String) -> String:
	return SpireLayout.model_path(model)


static func has_collision(kind: int) -> bool:
	return SpireLayout.has_collision(kind)


## Each box: [kind, centre, size, rotation (Euler degrees)].
static func boxes() -> Array:
	var out := [
		[Kind.FLOOR, Vector3(0, -0.5, 0), Vector3(64, 1, 48), Vector3.ZERO],
		[Kind.SPIRE, Vector3(0, 3, 0), Vector3(3, 6, 3), Vector3.ZERO],  # the crucible
	]
	for sx in [-1.0, 1.0]:
		out.append([Kind.BOUND, Vector3((HALF_X + 0.5) * sx, 10, 0), Vector3(1, 20, 48), Vector3.ZERO])
		out.append([Kind.WALL, Vector3(27.75 * sx, 2, 0), Vector3(0.5, 4, 40), Vector3.ZERO])
		# Loading bay: front door facing the crucible, roof at DECK.
		out.append([Kind.SLAB, Vector3(23.75 * sx, 3.75, 0), Vector3(7.5, 0.5, 12.5), Vector3.ZERO])
		out.append([Kind.COVER, Vector3(9 * sx, 0.6, 0), Vector3(0.5, 1.2, 4), Vector3.ZERO])
		for sz in [-1.0, 1.0]:
			out.append([Kind.WALL, Vector3(20.25 * sx, 2, 4 * sz), Vector3(0.5, 4, 4), Vector3.ZERO])
			# Side walls with a door; a ramp up to the roof along the hull.
			out.append([Kind.WALL, Vector3(20.75 * sx, 2, 6 * sz), Vector3(1.5, 4, 0.5), Vector3.ZERO])
			out.append([Kind.WALL, Vector3(26.5 * sx, 2, 6 * sz), Vector3(2, 4, 0.5), Vector3.ZERO])
			out.append([Kind.RAMP, Vector3(25.75 * sx, 1.776, (10.25 - RAMP_SHIFT) * sz), Vector3(3.5, 0.5, 8.944), Vector3(SLOPE * sz, 0, 0)])
			# Catwalk ramps down towards the bays, columns under the catwalks.
			out.append([Kind.RAMP, Vector3((16 - RAMP_SHIFT) * sx, 1.776, 9 * sz), Vector3(8.944, 0.5, 4), Vector3(0, 0, -SLOPE * sx)])
			out.append([Kind.COLUMN, Vector3(6 * sx, 1.75, 9 * sz), Vector3(0.8, 3.5, 0.8), Vector3.ZERO])
			# Flank cover.
			out.append([Kind.COVER, Vector3(6 * sx, 0.6, 15.5 * sz), Vector3(3, 1.2, 0.5), Vector3.ZERO])
	for sz in [-1.0, 1.0]:
		out.append([Kind.BOUND, Vector3(0, 10, (HALF_Z + 0.5) * sz), Vector3(64, 20, 1), Vector3.ZERO])
		out.append([Kind.WALL, Vector3(0, 2, 19.75 * sz), Vector3(56, 4, 0.5), Vector3.ZERO])
		out.append([Kind.SLAB, Vector3(0, 3.75, 9 * sz), Vector3(24, 0.5, 4), Vector3.ZERO])  # catwalk
		out.append([Kind.COVER, Vector3(0, 4.45, 7.05 * sz), Vector3(16, 0.9, 0.1), Vector3.ZERO])  # rail
		out.append([Kind.COVER, Vector3(0, 0.6, 4.5 * sz), Vector3(3, 1.2, 0.5), Vector3.ZERO])
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
		["essentials/Prop_Crate_Large", Vector3(14, 0, 15), 0.0],
		["essentials/Prop_Crate", Vector3(17.5, 0, 3), 0.0],
		["essentials/Prop_Crate_Tarp_Large", Vector3(20, 0, 16.5), 90.0],
		["megakit/Prop_Barrel_Large", Vector3(26.5, 0, 17.5), 0.0],
		["megakit/Prop_Barrel_Large", Vector3(25.8, 0, 18.4), 0.0],
		["megakit/Prop_Barrel_Large", Vector3(10.5, 0, 12.5), 0.0],
		["essentials/Prop_Locker", Vector3(26.5, 0, 4.8), 0.0],
		["megakit/Prop_Crate4", Vector3(3.2, 0, 2.8), 0.0],
		["megakit/Prop_Crate4", Vector3(12.5, 0, 4.5), 0.0],
	]
	var out := []
	for p in quad:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var yaw: float = p[2] if sx * sz > 0.0 else -p[2]
				out.append([p[0], Vector3(p[1].x * sx, p[1].y, p[1].z * sz), yaw])
	return out


## Visual-only detail: catwalk and roof edge trims, ceiling strips and the
## crucible's molten glow.
static func decor() -> Array:
	var out := []
	for s in [-1.0, 1.0]:
		for t in [-1.0, 1.0]:
			out.append([Kind.TRIM_ORANGE, Vector3(0, 3.97, (9 + 2.02 * t) * s), Vector3(24, 0.06, 0.06), Vector3.ZERO])
			out.append([Kind.TRIM_CYAN, Vector3(23.75 * s, 3.97, 6.27 * t), Vector3(7.5, 0.06, 0.06), Vector3.ZERO])
			out.append([Kind.TRIM_ORANGE, Vector3(6 * s, 1.22, 15.5 * t), Vector3(3, 0.04, 0.52), Vector3.ZERO])
		out.append([Kind.TRIM_CYAN, Vector3(19.98 * s, 3.97, 0), Vector3(0.06, 0.06, 12.5), Vector3.ZERO])
		out.append([Kind.TRIM_ORANGE, Vector3(0, 4.92, 7.05 * s), Vector3(16, 0.04, 0.12), Vector3.ZERO])  # rail top
		out.append([Kind.TRIM_ORANGE, Vector3(9 * s, 1.22, 0), Vector3(0.52, 0.04, 4), Vector3.ZERO])
		out.append([Kind.TRIM_CYAN, Vector3(0, 3.47, 9 * s), Vector3(20, 0.04, 0.3), Vector3.ZERO])  # under the catwalk
		out.append([Kind.TRIM_CYAN, Vector3(23.75 * s, 3.47, 0), Vector3(0.3, 0.04, 10), Vector3.ZERO])  # bay ceiling
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var size := Vector3(0.06, 1.2, 1.6) if d.x != 0.0 else Vector3(1.6, 1.2, 0.06)
		out.append([Kind.SPIRE_GLOW, d * 1.72 + Vector3(0, 5.2, 0), size, Vector3.ZERO])
	out.append([Kind.SPIRE_GLOW, Vector3(0, 6.05, 0), Vector3(2.6, 0.1, 2.6), Vector3.ZERO])
	return out


## Kit pieces (visual only): [model (kit/name, see model_path()), Transform3D].
static func pieces() -> Array:
	var out := []
	# Ground: dark plates in the bays and round the crucible, square plates
	# in the flank lanes, plain plates elsewhere.
	for i in 14:
		for j in 10:
			var c := Vector3(-26 + 4 * i, 0.003, -18 + 4 * j)
			var model := "megakit/Platform_Metal"
			if absf(c.x) > 20.0 and absf(c.z) < 6.0 or absf(c.x) < 6.0 and absf(c.z) < 6.0:
				model = "megakit/Platform_DarkPlates"
			elif absf(c.z) > 12.0:
				model = "megakit/Platform_Squares"
			out.append([model, Transform3D(Basis(), c)])
	for s in [-1.0, 1.0]:
		SpireLayout._tile(out, "megakit/Platform_Metal2", -12, 12, 7 * s if s > 0 else -11, 11 if s > 0 else -7, DECK)
		SpireLayout._tile(out, "megakit/Platform_DarkPlates", minf(20 * s, 27.5 * s), maxf(20 * s, 27.5 * s), -6.25, 6.25, DECK)
	# Ramps: [top edge centre, downhill direction, width].
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			SpireLayout._ramp(out, Vector3(25.75 * sx, DECK, 6.25 * sz), Vector3(0, 0, sz), 3.5)
			SpireLayout._ramp(out, Vector3(12 * sx, DECK, 9 * sz), Vector3(sx, 0, 0), 4.0)
	for b in boxes():
		if b[0] == Kind.WALL:
			SpireLayout._clad(out, b[1], b[2], HALF_X - 0.5, HALF_Z - 0.5)
	for sx in [-1.0, 1.0]:
		SpireLayout._door(out, Vector3(20.25 * sx, 0, 0), Vector3(1, 0, 0), 4.0)
		for sz in [-1.0, 1.0]:
			SpireLayout._door(out, Vector3(23.5 * sx, 0, 6 * sz), Vector3(0, 0, 1), 4.0)
			out.append(["megakit/Column_Round", Transform3D(Basis().scaled(Vector3(0.8, 0.7, 0.8)), Vector3(6 * sx, 0, 9 * sz))])
	out.append(["megakit/Column_Round", Transform3D(Basis().scaled(Vector3(3.4, 1.2, 3.4)), Vector3.ZERO)])
	for p in props():
		out.append([p[0], Transform3D(Basis(Vector3.UP, deg_to_rad(p[2])), p[1])])
	return out


## Baked accent lights: [position, color, energy, range].
static func lights() -> Array:
	var cyan := Color(0.35, 0.9, 1.0)
	var orange := Color(1.0, 0.55, 0.2)
	var out := [[Vector3(0, 7.5, 0), orange, 6.0, 16.0]]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append([Vector3(23.75 * sx, 3.1, 3 * sz), cyan, 4.5, 9.0])  # in the bays
			out.append([Vector3(6 * sx, 3.0, 9 * sz), orange, 3.0, 8.0])  # under the catwalks
			out.append([Vector3(16 * sx, 3.0, 16 * sz), orange, 1.5, 9.0])
			out.append([Vector3(9 * sx, 2.0, 2 * sz), orange, 0.8, 6.0])
	return out


## Spawn points facing the centre: bay floors and roofs, flank lanes, catwalks.
static func spawn_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			for p in [Vector3(23.5 * sx, 0.05, 3 * sz), Vector3(24 * sx, DECK + 0.05, 3 * sz),
					Vector3(17 * sx, 0.05, 12.5 * sz)]:
				out.append(Transform3D(Basis(Vector3.UP, atan2(p.x, p.z)), p))
			# Catwalk spawns look along the catwalk, towards the centre.
			out.append(Transform3D(Basis(Vector3.UP, atan2(sx, 0.0)), Vector3(4 * sx, DECK + 0.05, 9 * sz)))
	return out


## Pickup spots (PLAN §2.3): the Rail Sniper on the north catwalk, the Arc
## Launcher in the south flank lane, grenades in the mid lanes and on the
## south catwalk.
static func pickup_spots() -> Array:
	var out := [
		{"weapon": &"rail_sniper", "position": Vector3(0, DECK, -9.5), "respawn_ticks": 7200},
		{"weapon": &"arc_launcher", "position": Vector3(0, 0, 15), "respawn_ticks": 5400},
		{"weapon": &"grenade", "position": Vector3(0, DECK, 9.5), "respawn_ticks": 1200},
	]
	for s in [-1.0, 1.0]:
		out.append({"weapon": &"grenade", "position": Vector3(14 * s, 0, 0), "respawn_ticks": 1200})
	return out


## Jump pads (JumpPads): one in each flank lane, up onto the catwalk
## above it.
static func jump_pads() -> Array:
	var out := []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append({"position": Vector3(9 * sx, 0, 16.5 * sz), "target": Vector3(6 * sx, DECK, 9.3 * sz)})
	return out


## Capture-the-flag bases (west team 0, east team 1): inside the loading bays.
static func flag_bases() -> Array:
	return [Vector3(-24, 0, 0), Vector3(24, 0, 0)]


## Hash of everything the presentation is built from.
static func layout_hash() -> String:
	return var_to_str([boxes(), decor(), pieces(), lights()]).sha256_text()
