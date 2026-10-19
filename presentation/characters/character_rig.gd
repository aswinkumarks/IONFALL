class_name CharacterRig
extends Node3D
## Third-person body of a player (presentation only; hitboxes come from the
## simulation). Subclasses: SentinelRig (default: Meshy Cybernetic Sentinel
## on the animation-library clips), ArmoredRig (armoured soldier on the
## Quaternius animation-library mannequin), AstronautRig (Quaternius astronauts),
## SkinnedRig (Kenney character in a painted suit), PartsRig (rigid parts)
## and CapsuleRig (greybox). Skinned won the on-device comparison
## (docs/decisions/0003-character-rig.md).

const STYLES := ["sentinel", "armored", "astronaut", "skinned", "parts", "capsule"]
## Characters a player can pick (profile "character"), with their name keys.
## Sent as an index in the handshake and roster; indices wrap, so bots can
## take any number.
const SELECTABLE := ["sentinel", "armored", "skinned"]
const SELECTABLE_KEYS := ["CHAR_SENTINEL", "CHAR_VANGUARD", "CHAR_OPERATIVE"]


static func selectable_index(style: String) -> int:
	return maxi(SELECTABLE.find(style), 0)


static func selectable_style(index: int) -> String:
	return SELECTABLE[posmod(index, SELECTABLE.size())]


static func create(style: String, variant: int = 0) -> CharacterRig:
	match style:
		"sentinel":
			return SentinelRig.new()
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
	return SentinelRig.new()


func setup(_color: Color) -> void:
	pass


## Called every render frame with the interpolated state; `height` is the
## smoothed standing (1.8) / crouched (1.2) height.
func animate(_state: PlayerSimState, _delta: float, _height: float) -> void:
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
## rig's space) and the left hand to `support` (a point, same space).
func pose_first_person(_weapon: Transform3D, _support: Vector3) -> void:
	pass
