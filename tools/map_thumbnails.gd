extends Node3D
## Dev tool: renders a 640×360 thumbnail of every playable map for the menu
## cards (ui/maps/<id>.png). Run windowed:
## `godot --path . res://tools/map_thumbnails.tscn`

const OUT := "res://ui/maps/%s.png"


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var camera := Camera3D.new()
	camera.fov = 55.0
	add_child(camera)
	camera.current = true
	for id: String in Maps.PLAYABLE:
		var map := Maps.presentation(id)
		add_child(map)
		Settings.apply_environment(map)
		var box := AABB()
		var first := true
		for m in map.find_children("*", "MeshInstance3D", true, false):
			var b := (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		var center := box.get_center()
		var extent := maxf(box.size.x, box.size.z)
		# High three-quarter view from a corner, looking at the middle.
		camera.position = center + Vector3(extent * 0.42, extent * 0.3, extent * 0.5)
		camera.look_at(center + Vector3(0, -box.size.y * 0.15, 0))
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		img.save_png(OUT % id)
		print("saved ", OUT % id, " box ", box)
		map.free()
	get_tree().quit()
