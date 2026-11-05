extends Node3D
## Before/after captures for the graphics pass: each map with the four
## selectable characters in a row at 3, 8 and 15 m from the camera (and the
## map alone), at the quality given with --quality, plus the GPU time of
## each shot. Writes <out>/<quality>_<map>_<shot>.png and a timings line per
## shot to <out>/timings.txt.
##
##   godot --resolution 1920x1080 tools/look_capture/look_capture.tscn -- \
##       --quality high [--maps station,spire] [--out /some/dir]

const DISTANCES := [3.0, 8.0, 15.0]
const SPACING := 1.1  ## between the characters in the row
const WARM_FRAMES := 45  ## pipelines compile, animations settle
const MEASURE_FRAMES := 60

var _out := ""
var _quality := ""
var _camera := Camera3D.new()
var _visuals: Array[PlayerVisual] = []
var _states: Array[PlayerSimState] = []
var _time := 0.0


func _ready() -> void:
	_quality = Platform.get_user_arg("--quality").get_slice(",", 0)
	if _quality.is_empty():
		_quality = Settings.default_quality()
	_out = Platform.get_user_arg("--out")
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://look_capture")
	DirAccess.make_dir_recursive_absolute(_out)
	var maps_arg := Platform.get_user_arg("--maps")
	var maps: Array = Array(maps_arg.split(",")) if not maps_arg.is_empty() else Maps.PLAYABLE
	_camera.fov = float(Settings.video("fov"))
	_camera.current = true
	add_child(_camera)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if Platform.user_args.has("--fsr"):  # FSR 1 upscaling whatever the renderer
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		get_viewport().fsr_sharpness = 0.35
		_quality += "-fsr"
	await _run(maps)
	get_tree().quit()


func _process(delta: float) -> void:
	_time += delta
	for i in _visuals.size():
		_visuals[i].update_from(null, _states[i], 1.0, _time)


func _run(maps: Array) -> void:
	var log := FileAccess.open(_out.path_join("timings.txt"), FileAccess.READ_WRITE if FileAccess.file_exists(
			_out.path_join("timings.txt")) else FileAccess.WRITE)
	log.seek_end()
	for map_id: String in maps:
		var gameplay := Maps.gameplay(map_id)
		add_child(gameplay)
		var presentation := Maps.presentation(map_id)
		add_child(presentation)
		for light in presentation.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).shadow_enabled = Settings.video("shadows")
		for probe in presentation.find_children("*", "ReflectionProbe", true, false):
			(probe as ReflectionProbe).visible = Settings.video("probe") != false
		RenderLayers.light_dynamic_with_baked_lights(presentation, Settings.video("lights") == true)
		Settings.apply_environment(presentation)
		MapDetail.apply(presentation, map_id, MeshyRig.current_tier())
		await get_tree().physics_frame  # the map's colliders become queryable
		var spawn := _open_spawn(gameplay.spawn_points())
		var forward := -spawn.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)
		var eye := spawn.origin + Vector3.UP * 1.6
		_camera.look_at_from_position(eye, eye + forward, Vector3.UP)
		await _shot(log, map_id, "map")
		_spawn_row()
		for d: float in DISTANCES:
			for i in _states.size():
				var s := _states[i]
				s.position = _floor(spawn.origin + forward * d + right * (i - (_states.size() - 1) * 0.5) * SPACING)
				s.yaw = atan2(forward.x, forward.z)  # facing the camera
			_camera.look_at_from_position(eye, _floor(spawn.origin + forward * d) + Vector3.UP * 1.1, Vector3.UP)
			await _shot(log, map_id, "%dm" % int(d))
		for v in _visuals:
			v.queue_free()
		_visuals.clear()
		_states.clear()
		presentation.queue_free()
		gameplay.queue_free()
		await get_tree().process_frame


## The spawn and facing with the most open view: clear 16 m ahead at eye height, and
## floor at its height under each character at each shot distance (not off
## a ledge) with a line of sight to it (not behind cover).
func _open_spawn(spawns: Array[Transform3D]) -> Transform3D:
	var space := get_world_3d().direct_space_state
	var best := spawns[0]
	var best_score := -1
	var views: Array[Transform3D] = []
	for t in spawns:  # each spawn's own facing first, then turned ones
		for turn: float in [0.0, -45.0, 45.0, -90.0, 90.0, 180.0]:
			views.append(Transform3D(t.basis.rotated(Vector3.UP, deg_to_rad(turn)), t.origin))
	for t in views:
		var forward := -t.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := forward.cross(Vector3.UP)
		var eye := t.origin + Vector3.UP * 1.6
		var q := PhysicsRayQueryParameters3D.create(eye, eye + forward * (DISTANCES[-1] + 1.0))
		var score := 0 if not space.intersect_ray(q).is_empty() else 1
		for d: float in DISTANCES:
			for i in CharacterRig.SELECTABLE.size():
				var at := _floor(t.origin + forward * d + right * (i - (CharacterRig.SELECTABLE.size() - 1) * 0.5) * SPACING)
				var sight := PhysicsRayQueryParameters3D.create(eye, at + Vector3.UP * 1.2)
				if absf(at.y - t.origin.y) < 1.0 and space.intersect_ray(sight).is_empty():
					score += 1
		if score > best_score:
			best = t
			best_score = score
	print("look_capture: spawn at %s, %d/%d clear" % [best.origin, best_score, 1 + DISTANCES.size() * CharacterRig.SELECTABLE.size()])
	return best


## The floor under `at` (from up to 3 m above it), else `at`.
func _floor(at: Vector3) -> Vector3:
	var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 20.0))
	return hit.position if not hit.is_empty() else at


func _spawn_row() -> void:
	for i in CharacterRig.SELECTABLE.size():
		var v := PlayerVisual.new()
		add_child(v)
		v.setup(CharacterRig.SELECTABLE[i].capitalize(), false, PlayerVisual.color_for(i + 1, 0), 0,
				CharacterRig.SELECTABLE[i])
		v.hide_nameplate()
		var s := PlayerSimState.new()
		s.alive = true
		s.move_state = PlayerSimState.Move.GROUND
		s.init_weapons(Loadouts.make(i % Loadouts.PRIMARIES.size()))
		_visuals.append(v)
		_states.append(s)


func _shot(log: FileAccess, map_id: String, shot: String) -> void:
	for i in WARM_FRAMES:
		await get_tree().process_frame
	var gpu := 0.0
	var cpu := 0.0
	var vp := get_viewport().get_viewport_rid()
	for i in MEASURE_FRAMES:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	await RenderingServer.frame_post_draw
	var name := "%s_%s_%s" % [_quality, map_id, shot]
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	var tris := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var line := "%s gpu=%.2fms cpu=%.2fms tris=%d draws=%d scale=%.2f" % [name, gpu / MEASURE_FRAMES,
			cpu / MEASURE_FRAMES, tris, draws, get_viewport().scaling_3d_scale]
	print(line)
	log.store_line(line)
