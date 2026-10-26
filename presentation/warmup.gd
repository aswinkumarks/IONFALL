class_name Warmup
extends Node3D
## Shader warm-up (PLAN §3.9; cold-start stutter, §5): at map load, every
## selectable character (with its hit and shield effects), every weapon
## model and every effect is drawn for a few frames in front of the camera,
## behind the loading cover, so their pipelines compile before play instead
## of on first use mid-fight. The release exports also pre-compile shader
## code with the shader baker; pipelines still need a first draw.
##
## With a cold driver cache (a fresh install, a driver update) a pipeline
## costs up to seconds on desktop Mesa, and a frame waits for every pipeline
## it draws: the map and the warm-up set in one frame froze the game for
## 25-40 s on the frame before the cover showed, so a join looked stuck in the
## lobby. The map and the set are held back on a render layer the camera
## skips and revealed a few materials a frame instead, under a camera that
## sees the whole map; batches grow while frames stay quick, so a warm cache
## still finishes in a few frames.

signal finished
## 0..1 through the warm-up, for the loading cover.
signal progress(fraction: float)
## A reveal frame was slow: the driver's shader cache is cold.
signal slow

const FRAMES := 8
## Held-back geometry sits on this render layer (the last one) until shown.
const HOLD_LAYER := 1 << 19
## Reveal frames faster than this double the batch; one slower frame (a cold
## cache) keeps it at one for the rest.
const QUICK_MS := 250

var _hid_3d := false


func start(camera: Camera3D, effects: Effects) -> void:
	var eye := camera.global_transform
	# The cover's first frame without 3D, so it shows before any compiling.
	get_viewport().disable_3d = true
	_hid_3d = true
	await get_tree().process_frame
	var fronts: Array[Vector3] = []
	# Two sets: one lit by an omni light, one not. Moving objects pick up
	# the map's (baked) accent lights at runtime, and on the Mobile renderer
	# an object first lit by an omni light compiles another pipeline
	# specialization (M4 hitch log, docs/perf/m4.md).
	for lit in [true, false]:
		var front := eye * Vector3(-1.6 if lit else 1.6, -0.4, -4.0)
		fronts.append(front)
		if lit:
			# Also around the camera, for the first-person arms and weapon.
			for at: Vector3 in [front + Vector3.UP, eye.origin]:
				var light := OmniLight3D.new()
				add_child(light)
				light.omni_range = 2.5
				light.light_bake_mode = Light3D.BAKE_DISABLED
				light.global_position = at
		_draw_set(front, eye.basis.x)
	await _reveal(camera)
	for front in fronts:
		effects.warm_up(front)
	for f in FRAMES:
		await get_tree().process_frame
	progress.emit(0.93)
	# The arms and weapon unlit too.
	for light in find_children("*", "OmniLight3D", false, false):
		light.queue_free()
	for f in FRAMES:
		await get_tree().process_frame
	progress.emit(1.0)
	finished.emit()
	# Stays, hidden, until the match ends: freeing the set right away froze
	# a cold-cache client for 8-15 s on its first frame of play (some
	# compile restarting once the set's last users were gone).
	visible = false


func _exit_tree() -> void:
	if _hid_3d:  # left during the first frame
		get_viewport().disable_3d = false


## Holds back every visible piece of the match (map, warm-up set) and shows
## a batch of materials a frame, seen from above through an orthographic
## camera so the whole map is in view (only what is in view gets drawn, and
## compiled). Reflection probes come last, so they capture the whole map.
func _reveal(camera: Camera3D) -> void:
	var root := get_parent()
	var groups: Dictionary = {}  # material set -> [[geometry, its layers]]
	var bounds := AABB()
	for g: GeometryInstance3D in root.find_children("*", "GeometryInstance3D", true, false):
		if (g.layers & ~HOLD_LAYER) == 0 or not g.is_visible_in_tree():
			continue
		var key := _materials_of(g)
		if not groups.has(key):
			groups[key] = []
		groups[key].append([g, g.layers])
		g.layers = HOLD_LAYER
		var box := g.global_transform * g.get_aabb()
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	var probes: Array[ReflectionProbe] = []
	for probe: ReflectionProbe in root.find_children("*", "ReflectionProbe", true, false):
		if probe.visible:
			probe.visible = false
			probes.append(probe)
	var overview := _overview(bounds, camera.cull_mask & ~HOLD_LAYER)
	add_child(overview)
	overview.make_current()
	get_viewport().disable_3d = false
	_hid_3d = false
	var pending: Array = groups.values()
	var total := maxi(pending.size(), 1)
	var batch := 1
	var cold := false
	while not pending.is_empty():
		for group: Array in pending.slice(0, batch):
			for held: Array in group:
				if is_instance_valid(held[0]):
					(held[0] as GeometryInstance3D).layers = held[1]
		pending = pending.slice(batch)
		progress.emit(0.85 * (1.0 - float(pending.size()) / total))
		var started := Time.get_ticks_msec()
		await get_tree().process_frame
		if Time.get_ticks_msec() - started >= QUICK_MS and not cold:
			cold = true  # a cold cache: one batch a frame from now on
			slow.emit()
		batch = 1 if cold else batch * 2
	for probe in probes:
		if is_instance_valid(probe):
			probe.visible = true
	await get_tree().process_frame
	camera.make_current()
	overview.queue_free()
	progress.emit(0.88)


## A camera looking straight down on `bounds`, all of it in view.
static func _overview(bounds: AABB, cull_mask: int) -> Camera3D:
	var cam := Camera3D.new()
	cam.top_level = true
	cam.cull_mask = cull_mask
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = maxf(maxf(bounds.size.x, bounds.size.z), 1.0) * 1.05
	cam.near = 0.05
	cam.far = bounds.size.y + 20.0
	var top := bounds.get_center() + Vector3.UP * (bounds.size.y * 0.5 + 10.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), top)
	return cam


## What a geometry draws with: geometries sharing one compile together.
static func _materials_of(g: GeometryInstance3D) -> String:
	var parts := PackedStringArray([g.get_class(), str(g.material_override.get_instance_id() if g.material_override else 0)])
	var mi := g as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			parts.append(str(m.get_instance_id() if m else 0))
	return ",".join(parts)


func _draw_set(front: Vector3, right: Vector3) -> void:
	var i := 0
	for style: String in CharacterRig.SELECTABLE:
		var v := PlayerVisual.new()
		add_child(v)
		v.setup("", false, GameMode.team_color(i % 2), 0, style)
		v.global_position = front + right * (i - 1) * 0.5 - Vector3.UP
		v.flash_hit(true)
		i += 1
	var w := 0
	for data: WeaponData in Weapons.ALL:
		var model := WeaponModels.instantiate(data.id)
		if model == null:
			continue
		add_child(model)
		model.global_position = front + right * (w - 3) * 0.2 + Vector3.UP * 0.8
		w += 1
	# Contact shadows (BlobShadows, when realtime shadows are off): their
	# instanced pipeline, compiled here rather than when the first one shows.
	var blobs := BlobShadows.new()
	blobs.floor_at_feet = true
	add_child(blobs)
	blobs.visible = true
	blobs.show_at(PackedVector3Array([front - Vector3.UP]))
