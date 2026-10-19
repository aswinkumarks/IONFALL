class_name CharacterRig
extends Node3D
## Third-person body of a player (presentation only; hitboxes come from the
## simulation). Subclasses: CapsuleRig (greybox), SkinnedRig (one skinned CC0
## character) and PartsRig (rigid parts). PLAN §4 decides between the last
## two by an on-device comparison (M2).

const STYLES := ["skinned", "parts", "capsule"]


static func create(style: String) -> CharacterRig:
	match style:
		"parts":
			return PartsRig.new()
		"capsule":
			return CapsuleRig.new()
	return SkinnedRig.new()


func setup(_color: Color) -> void:
	pass


## Called every render frame with the interpolated state; `height` is the
## smoothed standing (1.8) / crouched (1.2) height.
func animate(_state: PlayerSimState, _delta: float, _height: float) -> void:
	pass


## Spawn-protection shimmer, 0 = off.
func set_glow(_amount: float) -> void:
	pass
