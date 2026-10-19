class_name Maps
extends RefCounted
## Map registry. A map is a gameplay scene (collision + spawn_points(); all
## the dedicated server loads) and a presentation scene (meshes, lights,
## baked lightmap; clients only), PLAN §3.1.

const DEFAULT := "station"
const LIST := {
	"station": {
		"name": "MAP_STATION",
		"gameplay": "res://maps/station/gameplay.tscn",
		"presentation": "res://maps/station/presentation.tscn",
	},
	"test_arena": {
		"name": "MAP_TEST_ARENA",
		"gameplay": "res://maps/test_arena/gameplay.tscn",
		"presentation": "res://maps/test_arena/presentation.tscn",
	},
}


static func has(id: String) -> bool:
	return LIST.has(id)


static func gameplay(id: String) -> Node3D:
	return (load(LIST[id].gameplay) as PackedScene).instantiate()


static func presentation(id: String) -> Node3D:
	return (load(LIST[id].presentation) as PackedScene).instantiate()


## `--map ID` from the command line if valid, else DEFAULT.
static func from_args() -> String:
	var id := Platform.get_user_arg("--map", DEFAULT)
	return id if has(id) else DEFAULT
