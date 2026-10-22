extends Node3D
## Gameplay half of Meridian Station: world collision and spawn points only.
## The dedicated server loads just this scene (PLAN §3.1).


func _ready() -> void:
	var body := StaticBody3D.new()
	body.name = "World"
	body.collision_layer = Sim.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for b in StationLayout.boxes():
		var shape := BoxShape3D.new()
		shape.size = b[2]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(b[3])), b[1])
		body.add_child(cs)


func spawn_points() -> Array[Transform3D]:
	return StationLayout.spawn_points()


func pickup_spots() -> Array:
	return StationLayout.pickup_spots()


func flag_bases() -> Array:
	return StationLayout.flag_bases()
