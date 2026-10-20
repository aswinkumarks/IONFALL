class_name SimPlayer
extends CharacterBody3D
## Simulation-side player entity: the physics body used for world collision
## plus the replayable state. Presentation never reads the body directly; it
## reads `state`.

var net_id: int = 0
## Changes only when a new entity is created (a new join), so action IDs
## `(net_id, entity_gen, action_seq)` never repeat within a match (PLAN §3.2).
var entity_gen: int = 0
var is_bot: bool = false
var display_name: String = ""
var character: int = 0  ## cosmetic (CharacterRig.SELECTABLE index); presentation only
var color: int = 0  ## cosmetic (PlayerVisual.PALETTE index, 0 = auto); presentation only
var team: int = 0
var config: MovementConfig
## Issued at every spawn; pickups change the slots in `state` for this life.
var loadout: Array[WeaponData] = []
var state := PlayerSimState.new()
var last_command: PlayerCommand

var _shape := CapsuleShape3D.new()
var _shape_node := CollisionShape3D.new()
var _shape_stance: int = -1


func setup(id: int, gen: int, movement: MovementConfig, weapons: Array[WeaponData]) -> void:
	net_id = id
	entity_gen = gen
	config = movement
	loadout = weapons
	collision_layer = Sim.LAYER_PLAYER
	collision_mask = Sim.LAYER_WORLD
	_shape.radius = config.capsule_radius
	_shape_node.shape = _shape
	add_child(_shape_node)
	state.init_weapons(loadout)
	apply_stance_shape(state.stance)


## Resizes the collision capsule for a stance, keeping the feet in place.
func apply_stance_shape(stance: int) -> void:
	if stance == _shape_stance:
		return
	var h := config.height_for(stance)
	_shape.height = h
	_shape_node.position = Vector3(0.0, h * 0.5, 0.0)
	_shape_stance = stance


## Puts the body exactly where `snapshot` says (reconciliation, PLAN §3.2).
func restore(snapshot: PlayerSimState) -> void:
	state = snapshot.copy()
	apply_stance_shape(state.stance)
	global_position = state.position


func eye_position() -> Vector3:
	return state.position + Vector3(0.0, config.eye_for(state.stance), 0.0)


func current_weapon() -> WeaponData:
	return state.weapon()
