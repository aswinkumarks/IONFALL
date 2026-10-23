extends Node3D
## Gameplay half of the test arena: world collision and spawn points only.
## The dedicated server loads just this scene (PLAN §3.1).


func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "World"
	body.collision_layer = Sim.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for b in TestArenaLayout.boxes():
		if not TestArenaLayout.has_collision(b[0]):
			continue
		var shape := BoxShape3D.new()
		shape.size = b[2]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(b[3])), b[1])
		body.add_child(cs)


func spawn_points() -> Array[Transform3D]:
	return TestArenaLayout.spawn_points()


func pickup_spots() -> Array:
	return []


## CTF tests: open floor near the west and east walkways.
func flag_bases() -> Array:
	return [Vector3(-12, 0, 0), Vector3(12, 0, 0)]
