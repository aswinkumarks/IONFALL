class_name TestArenaLayout
extends RefCounted
## Greybox layout for the M1 test arena. Both the gameplay scene (collision)
## and the presentation scene (meshes) are generated from this data, so they
## can never disagree.
##
## Coordinates: the floor top is y = 0, the play area is roughly 40 × 40 m.

enum Kind { FLOOR, WALL, PLATFORM, RAMP, COVER, PILLAR, LEDGE, TRIM }

const RAMP_CENTER := 14.04  ## atan(2 / 8): centre platform ramps
const RAMP_SIDE := 17.35  ## atan(2.5 / 8): walkway ramps


## Each box: [kind, centre, size, rotation_x_degrees].
static func boxes() -> Array:
	return [
		[Kind.FLOOR, Vector3(0, -0.5, 0), Vector3(44, 1, 44), 0.0],
		# Outer walls
		[Kind.WALL, Vector3(0, 3, -21), Vector3(44, 6, 2), 0.0],
		[Kind.WALL, Vector3(0, 3, 21), Vector3(44, 6, 2), 0.0],
		[Kind.WALL, Vector3(21, 3, 0), Vector3(2, 6, 40), 0.0],
		[Kind.WALL, Vector3(-21, 3, 0), Vector3(2, 6, 40), 0.0],
		# Centre platform (top 2.0 m) with ramps north and south
		[Kind.PLATFORM, Vector3(0, 1, 0), Vector3(8, 2, 8), 0.0],
		[Kind.RAMP, Vector3(0, 0.757, -8), Vector3(4, 0.5, 8.25), -RAMP_CENTER],
		[Kind.RAMP, Vector3(0, 0.757, 8), Vector3(4, 0.5, 8.25), RAMP_CENTER],
		# Side walkways (top 2.5 m) with ramps
		[Kind.PLATFORM, Vector3(17.5, 1.25, 0), Vector3(5, 2.5, 24), 0.0],
		[Kind.RAMP, Vector3(17.5, 1.011, 16), Vector3(5, 0.5, 8.38), RAMP_SIDE],
		[Kind.PLATFORM, Vector3(-17.5, 1.25, 0), Vector3(5, 2.5, 24), 0.0],
		[Kind.RAMP, Vector3(-17.5, 1.011, -16), Vector3(5, 0.5, 8.38), -RAMP_SIDE],
		# Mantle test ledges: 1.0, 1.5, 1.8 m (jump + mantle), 3.2 m (needs double jump + mantle)
		[Kind.LEDGE, Vector3(-14, 0.5, 12), Vector3(2, 1.0, 2), 0.0],
		[Kind.LEDGE, Vector3(-11, 0.75, 12), Vector3(2, 1.5, 2), 0.0],
		[Kind.LEDGE, Vector3(-8, 0.9, 12), Vector3(2, 1.8, 2), 0.0],
		[Kind.LEDGE, Vector3(-5, 1.6, 12), Vector3(2, 3.2, 2), 0.0],
		# Cover
		[Kind.COVER, Vector3(8, 0.6, -10), Vector3(3, 1.2, 1), 0.0],
		[Kind.COVER, Vector3(-8, 0.6, -10), Vector3(3, 1.2, 1), 0.0],
		[Kind.COVER, Vector3(10, 0.6, 9), Vector3(1, 1.2, 3), 0.0],
		[Kind.COVER, Vector3(11, 0.6, -2), Vector3(1, 1.2, 4), 0.0],
		[Kind.COVER, Vector3(-11, 0.6, -2), Vector3(1, 1.2, 4), 0.0],
		# Pillars
		[Kind.PILLAR, Vector3(6, 2.5, 6), Vector3(1.5, 5, 1.5), 0.0],
		[Kind.PILLAR, Vector3(-6, 2.5, 6), Vector3(1.5, 5, 1.5), 0.0],
		[Kind.PILLAR, Vector3(6, 2.5, -6), Vector3(1.5, 5, 1.5), 0.0],
		[Kind.PILLAR, Vector3(-6, 2.5, -6), Vector3(1.5, 5, 1.5), 0.0],
		# Emissive trims (visual only)
		[Kind.TRIM, Vector3(0, 0.05, -19.95), Vector3(40, 0.1, 0.1), 0.0],
		[Kind.TRIM, Vector3(0, 0.05, 19.95), Vector3(40, 0.1, 0.1), 0.0],
		[Kind.TRIM, Vector3(0, 2.02, 0), Vector3(8.1, 0.06, 8.1), 0.0],
		[Kind.TRIM, Vector3(15.02, 2.52, 0), Vector3(0.06, 0.06, 24), 0.0],
		[Kind.TRIM, Vector3(-15.02, 2.52, 0), Vector3(0.06, 0.06, 24), 0.0],
	]


static func has_collision(kind: int) -> bool:
	return kind != Kind.TRIM


## Spawn points facing the arena centre.
static func spawn_points() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for p in [Vector3(12, 0.1, 17), Vector3(-12, 0.1, -17), Vector3(12, 0.1, -17), Vector3(-12, 0.1, 17),
			Vector3(0, 0.1, 15), Vector3(0, 0.1, -15), Vector3(13, 0.1, 0), Vector3(-13, 0.1, 0)]:
		var yaw := atan2(p.x, p.z)
		out.append(Transform3D(Basis(Vector3.UP, yaw), p))
	return out
