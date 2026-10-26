@tool
class_name CharacterRig
extends Node3D
## Third-person body of a player (presentation only; hitboxes come from the
## simulation). Subclasses: MeshyRig (the selectable characters, Meshy
## models on the animation-library clips), ArmoredRig (armoured soldier on the
## Quaternius animation-library mannequin), AstronautRig (Quaternius astronauts),
## SkinnedRig (Kenney character in a painted suit), PartsRig (rigid parts)
## and CapsuleRig (greybox). Skinned won the on-device comparison
## (docs/decisions/0003-character-rig.md).

const STYLES := ["sentinel", "vanguard", "operative", "spacer", "armored", "astronaut", "skinned", "parts", "capsule"]
## Characters a player can pick (profile "character"), with their name keys.
## Sent as an index in the handshake and roster; indices wrap, so bots can
## take any number.
const SELECTABLE := ["sentinel", "vanguard", "operative", "spacer"]
const SELECTABLE_KEYS := ["CHAR_SENTINEL", "CHAR_VANGUARD", "CHAR_OPERATIVE", "CHAR_SPACER"]
## Profiles saved before the Meshy characters name the old rigs.
const LEGACY := {"armored": "vanguard", "skinned": "operative", "astronaut": "spacer"}


static func selectable_index(style: String) -> int:
	return maxi(SELECTABLE.find(LEGACY.get(style, style)), 0)


static func selectable_style(index: int) -> String:
	return SELECTABLE[posmod(index, SELECTABLE.size())]


static func create(style: String, variant: int = 0) -> CharacterRig:
	match style:
		"sentinel", "vanguard", "operative", "spacer":
			return MeshyRig.new(style)
		"armored":
			return ArmoredRig.new()
		"astronaut":
			var a := AstronautRig.new()
			a.variant = variant
			return a
		"skinned":
			return SkinnedRig.new()
		"parts":
			return PartsRig.new()
		"capsule":
			return CapsuleRig.new()
	return MeshyRig.new()


func setup(_color: Color) -> void:
	pass


## Called every render frame with the interpolated state; `height` is the
## smoothed standing (1.8) / crouched (1.2) height.
func animate(_state: PlayerSimState, _delta: float, _height: float) -> void:
	pass


## Animation detail for characters far away or off screen (PlayerVisual):
## `ik` off skips pose fixes after the clips; the clips advance every
## `anim_every` frames (0: paused), `phase` spreading them across characters.
func set_detail(_ik: bool, _anim_every: int, _phase: int = 0) -> void:
	pass


## Spawn-protection shimmer, 0 = off.
func set_glow(_amount: float) -> void:
	pass


## Brief white hit flash, 0..1.
func flash(_amount: float) -> void:
	pass


## The weapon shown in the character's hands (rigs without hands ignore it).
func set_weapon(_id: StringName) -> void:
	pass


## The character fired (upper-body recoil where supported).
func on_fire() -> void:
	pass


## Two-bone IK in skeleton space for rigs without weapon clips: `chain` is
## [upper arm, forearm, hand]; the arm bends towards `pole` so the wrist lands
## on `target`. The hand keeps the forearm's direction.
static func reach(sk: Skeleton3D, chain: Array, target: Vector3, pole: Vector3) -> void:
	var u := sk.find_bone(chain[0])
	var f := sk.find_bone(chain[1])
	var h := sk.find_bone(chain[2])
	if u < 0 or f < 0 or h < 0:
		return
	var rest_u := sk.get_bone_global_rest(u)
	var rest_f := sk.get_bone_global_rest(f)
	var rest_h := sk.get_bone_global_rest(h)
	var l1 := rest_u.origin.distance_to(rest_f.origin)
	var l2 := rest_f.origin.distance_to(rest_h.origin)
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(u))
	var shoulder := parent * sk.get_bone_rest(u).origin
	var to_target := target - shoulder
	var d := clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to_target.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * a + bend * sqrt(maxf(l1 * l1 - a * a, 0.0))
	var wrist := shoulder + dir * d
	var swing_u := Quaternion((rest_f.origin - rest_u.origin).normalized(), (elbow - shoulder).normalized())
	var upper := Basis(swing_u) * rest_u.basis.orthonormalized()
	sk.set_bone_pose_rotation(u, (parent.basis.orthonormalized().inverse() * upper).get_rotation_quaternion())
	var fore_dir := Basis(swing_u) * (rest_h.origin - rest_f.origin).normalized()
	var swing_f := Quaternion(fore_dir, (wrist - elbow).normalized())
	var fore := Basis(swing_f) * Basis(swing_u) * rest_f.basis.orthonormalized()
	sk.set_bone_pose_rotation(f, (upper.inverse() * fore).get_rotation_quaternion())
	sk.set_bone_pose_rotation(h, sk.get_bone_rest(h).basis.get_rotation_quaternion())


## World position of the held weapon's muzzle, or Vector3.INF without one.
func muzzle_position() -> Vector3:
	return Vector3.INF


## Turns this body into first-person arms: only the arms are kept, in the
## rest pose, casting no shadow; pose them with pose_first_person(). False if
## the rig can't.
func make_first_person() -> bool:
	return false


## First person: the head's position in this rig's space (the camera sits
## just in front of it).
func head_position() -> Vector3:
	return Vector3(0.0, 1.6, 0.0)


## First person: reach the right hand to grip `weapon` (its transform in this
## rig's space), whose handle is at `handle`, and the left hand to `support`
## (points, same space).
func pose_first_person(_weapon: Transform3D, _handle: Vector3, _support: Vector3) -> void:
	pass
