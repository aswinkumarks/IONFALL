class_name CharacterRig
extends Node3D
## Third-person body of a player (presentation only; hitboxes come from the
## simulation). Subclasses: AstronautRig (default: Quaternius astronauts),
## SkinnedRig (Kenney character in a painted suit), PartsRig (rigid parts)
## and CapsuleRig (greybox). Skinned won the on-device comparison
## (docs/decisions/0003-character-rig.md).

const STYLES := ["astronaut", "skinned", "parts", "capsule"]


static func create(style: String, variant: int = 0) -> CharacterRig:
	match style:
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
	return AstronautRig.new()


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
