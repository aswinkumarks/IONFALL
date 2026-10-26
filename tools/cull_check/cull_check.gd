extends Node
## Which double-sided map materials actually show back faces? Renders every
## spawn point in four directions with culling as built, then with back-face
## culling on all of them and on each material in turn, and prints the share
## of pixels that change (saving the worst view of "ALL"). Materials that
## change nothing (ignore view 0: the first frames differ anyway) can go in
## MapMaterials.CULL_BACK. Needs a display:
##
##   xvfb-run godot --rendering-driver opengl3 --resolution 640x360 \
##       res://tools/cull_check/cull_check.tscn -- spire /tmp/cull

var _cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id: String = args[0]
	var out: String = args[1]
	await get_tree().process_frame
	var gameplay := Maps.gameplay(map_id)
	add_child(gameplay)
	var pres := Maps.presentation(map_id)
	add_child(pres)
	Settings.apply_environment(pres)
	var mats := {}  ## material -> true
	for mi: MeshInstance3D in pres.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as BaseMaterial3D
			if m != null and m.cull_mode == BaseMaterial3D.CULL_DISABLED:
				mats[m] = true
	var by_name := {}
	for m: BaseMaterial3D in mats:
		if not by_name.has(m.resource_name):
			by_name[m.resource_name] = []
		by_name[m.resource_name].append(m)
	_cam = Camera3D.new()
	_cam.fov = 75
	add_child(_cam)
	_cam.current = true
	var views: Array[Transform3D] = []
	var spawns: Array = gameplay.call("spawn_points")
	for sp: Transform3D in spawns:
		for turn in [0.0, PI * 0.5, PI, PI * 1.5]:
			var eye := sp.origin + Vector3(0, 1.6, 0)
			views.append(Transform3D(Basis(Vector3.UP, sp.basis.get_euler().y + turn), eye))
	print("views %d, cull-disabled materials %s" % [views.size(), by_name.keys()])
	var base: Array[Image] = []
	for v in views:
		base.append(await _shot(v))
	var groups: Array = [["ALL", mats.keys()]]
	for n: String in by_name:
		groups.append([n, by_name[n]])
	for g: Array in groups:
		for m: BaseMaterial3D in g[1]:
			m.cull_mode = BaseMaterial3D.CULL_BACK
		var changed := 0
		var worst := 0.0
		var worst_view := -1
		for k in views.size():
			var img := await _shot(views[k])
			var d := _diff(base[k], img)
			changed += 1 if d > 0.0005 else 0
			if d > worst:
				worst = d
				worst_view = k
				if g[0] == "ALL":
					img.save_png("%s_%s_cull_view%d.png" % [out, map_id, k])
					base[k].save_png("%s_%s_base_view%d.png" % [out, map_id, k])
		print("%s %-20s views changed %d/%d, worst %.3f%% of pixels (view %d)" % [map_id, g[0], changed, views.size(), worst * 100.0, worst_view])
		for m: BaseMaterial3D in g[1]:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
	get_tree().quit()


func _shot(xf: Transform3D) -> Image:
	_cam.global_transform = xf
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Share of pixels that differ noticeably.
func _diff(a: Image, b: Image) -> float:
	var n := 0
	var w := a.get_width()
	var h := a.get_height()
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				n += 1
	return float(n) / float((w / 2) * (h / 2))
