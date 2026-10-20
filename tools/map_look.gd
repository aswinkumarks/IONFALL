extends RefCounted
## Finishing steps shared by the map builders (PLAN §3.9): the per-map
## colour grade (built into a LUT at load, ColorGrade) and one box-projected
## ReflectionProbe over the play space, updated once at load.


## Adds the grade (ColorGrade) and the probe to a built presentation `root`.
static func finish(root: Node3D, grade: Dictionary) -> void:
	root.set_meta("grade", grade)
	var bounds := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", false, false):
		var box := mi.transform * mi.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var probe := ReflectionProbe.new()
	probe.name = "ReflectionProbe"
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.box_projection = true
	probe.position = bounds.get_center()
	probe.size = bounds.size + Vector3.ONE
	probe.max_distance = bounds.size.length()
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED  # the lightmap provides ambient light
	root.add_child(probe)
