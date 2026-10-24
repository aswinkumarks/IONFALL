extends Node3D
## Gameplay half of Halcyon Spire: world collision, jump pads and spawn points only.
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
	for pad in SpireLayout.jump_pads():
		add_child(JumpPads.make_area(pad))


func spawn_points() -> Array[Transform3D]:
	return SpireLayout.spawn_points()


func pickup_spots() -> Array:
	return SpireLayout.pickup_spots()


func flag_bases() -> Array:
	return SpireLayout.flag_bases()


func jump_pads() -> Array:
	return SpireLayout.jump_pads()
