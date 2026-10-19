class_name Hitbox
extends RefCounted
## Authoritative hitboxes as simple capsules driven by simulation state, not by
## animation (PLAN §4). Pure math, so lag compensation can rewind them from
## stored positions without touching the physics engine (PLAN §3.3.4).

enum Part { HEAD, TORSO, LEGS }

## Capsules per stance: [part, bottom height, top height, radius]. A capsule
## whose bottom equals its top is a sphere. The torso's top cap must stay below
## the head sphere's centre, or shots at the face hit the torso first
## (covered by tests/unit/test_hitbox.gd).
const SHAPES := {
	PlayerSimState.Stance.STAND: [
		[Part.HEAD, 1.62, 1.62, 0.17],
		[Part.TORSO, 1.0, 1.3, 0.28],
		[Part.LEGS, 0.2, 0.95, 0.22],
	],
	PlayerSimState.Stance.CROUCH: [
		[Part.HEAD, 1.05, 1.05, 0.17],
		[Part.TORSO, 0.55, 0.72, 0.28],
		[Part.LEGS, 0.2, 0.55, 0.24],
	],
	PlayerSimState.Stance.SLIDE: [
		[Part.HEAD, 0.85, 0.85, 0.17],
		[Part.TORSO, 0.42, 0.52, 0.28],
		[Part.LEGS, 0.2, 0.4, 0.26],
	],
}


class Hit:
	var distance: float = INF
	var part: int = Part.TORSO


## Nearest hit of the ray `from + dir * t` (t in [0, max_dist]) against the
## hitboxes of a player standing at `feet` in `stance`. `dir` must be
## normalized. Returns null on a miss.
static func intersect(feet: Vector3, stance: int, from: Vector3, dir: Vector3, max_dist: float) -> Hit:
	var best: Hit = null
	for shape in SHAPES[stance]:
		var a := feet + Vector3(0.0, shape[1], 0.0)
		var b := feet + Vector3(0.0, shape[2], 0.0)
		var t := ray_capsule(from, dir, a, b, shape[3])
		if t <= max_dist and (best == null or t < best.distance):
			best = Hit.new()
			best.distance = t
			best.part = shape[0]
	return best


## Distance along a normalized ray to a capsule (segment a-b, radius r), or INF.
static func ray_capsule(ro: Vector3, rd: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ba := b - a
	var oa := ro - a
	var baba := ba.dot(ba)
	if baba < 1e-8:
		return ray_sphere(ro, rd, a, r)
	var bard := ba.dot(rd)
	var baoa := ba.dot(oa)
	var rdoa := rd.dot(oa)
	var oaoa := oa.dot(oa)
	var qa := baba - bard * bard
	var qb := baba * rdoa - baoa * bard
	var qc := baba * oaoa - baoa * baoa - r * r * baba
	if absf(qa) > 1e-8:
		var h := qb * qb - qa * qc
		if h >= 0.0:
			var t := (-qb - sqrt(h)) / qa
			var y := baoa + t * bard
			if y > 0.0 and y < baba and t >= 0.0:
				return t
	# Caps.
	var t_a := ray_sphere(ro, rd, a, r)
	var t_b := ray_sphere(ro, rd, b, r)
	return minf(t_a, t_b)


static func ray_sphere(ro: Vector3, rd: Vector3, c: Vector3, r: float) -> float:
	var oc := ro - c
	var b := oc.dot(rd)
	var cc := oc.dot(oc) - r * r
	var h := b * b - cc
	if h < 0.0:
		return INF
	var t := -b - sqrt(h)
	if t < 0.0:
		t = -b + sqrt(h)
	return t if t >= 0.0 else INF


## Centre of mass used for splash damage and visibility checks.
static func center(feet: Vector3, stance: int) -> Vector3:
	var torso: Array = SHAPES[stance][1]
	return feet + Vector3(0.0, (torso[1] + torso[2]) * 0.5, 0.0)
