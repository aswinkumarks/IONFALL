extends Node3D
## Gameplay half of Halcyon Spire: world collision and spawn points only.
## The dedicated server loads just this scene (PLAN §3.1).


func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "World"
	body.collision_layer = Sim.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for b in SpireLayout.boxes():
		var shape := BoxShape3D.new()
		shape.size = b[2]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		var rot: Vector3 = b[3]
		cs.transform = Transform3D(Basis.from_euler(rot * (PI / 180.0)), b[1])
		body.add_child(cs)


func spawn_points() -> Array[Transform3D]:
	return SpireLayout.spawn_points()
