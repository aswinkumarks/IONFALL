extends Node3D
## Lighting validation scene (PLAN §3.9, M1c): baked floor and walls
## (LightmapGI, Static accent lights) with a Dynamic sun casting realtime
## character shadows. Shows the numbers the plan asks for: lightmap texture
## format and memory, frame time, and the cost of the sun's shadow pass.
##
## Desktop: `godot -- --lighting-test`. Android: the diagnostics overlay.
## Bake in the editor (select LightmapGI → Bake Lightmaps) after changing
## geometry or lights; the .lmbake/.exr go to Git LFS.

const RUNNER_COUNTS := [4, 8, 16]
const COLORS := [Color(0.55, 0.45, 1.0), Color(0.3, 0.85, 0.5), Color(0.95, 0.4, 0.6), Color(0.95, 0.5, 0.2)]

@onready var _sun: DirectionalLight3D = $Sun
@onready var _lightmap: LightmapGI = $LightmapGI
@onready var _camera: Camera3D = $Camera
@onready var _label: Label = %Info

var _runners: Array[PlayerVisual] = []
var _time: float = 0.0
var _stats := FrameStats.new(600)
var _gpu_ms := FrameStats.new(300)
var _runner_count: int = 4
var _bench_report: String = ""
var _bicubic: bool = ProjectSettings.get_setting_with_override("rendering/lightmapping/lightmap_gi/use_bicubic_filter")


func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var rig_arg := Platform.get_user_arg("--rig")
	if rig_arg in CharacterRig.STYLES:
		PlayerVisual.style = rig_arg
	var count_arg := Platform.get_user_arg("--runners")
	if count_arg.is_valid_int():
		_runner_count = int(count_arg)
	_spawn_runners()
	_add_button("Rig", func() -> void:
		PlayerVisual.style = CharacterRig.STYLES[(CharacterRig.STYLES.find(PlayerVisual.style) + 1) % CharacterRig.STYLES.size()]
		_spawn_runners())
	_add_button("Count", func() -> void:
		_runner_count = RUNNER_COUNTS[(RUNNER_COUNTS.find(_runner_count) + 1) % RUNNER_COUNTS.size()]
		_spawn_runners())
	_add_button("Rig bench", rig_bench)
	if Platform.user_args.has("--rig-bench"):
		await rig_bench()
		get_tree().quit()
		return
	%ShadowsButton.pressed.connect(func() -> void:
		_sun.shadow_enabled = not _sun.shadow_enabled
		_gpu_ms.clear())
	%LightmapButton.pressed.connect(func() -> void:
		_lightmap.visible = not _lightmap.visible
		_gpu_ms.clear())
	%BicubicButton.pressed.connect(func() -> void:
		_bicubic = not _bicubic
		RenderingServer.lightmaps_set_bicubic_filter(_bicubic)
		_gpu_ms.clear())
	%MaskButton.pressed.connect(func() -> void:
		_lightmap.shadowmask_mode = LightmapGIData.SHADOWMASK_MODE_OVERLAY \
				if _lightmap.shadowmask_mode == LightmapGIData.SHADOWMASK_MODE_NONE else LightmapGIData.SHADOWMASK_MODE_NONE
		_gpu_ms.clear())
	%ScaleButton.pressed.connect(func() -> void:
		var root := get_tree().root
		root.scaling_3d_scale = 1.0 if root.scaling_3d_scale < 0.99 else 0.75
		_gpu_ms.clear())
	%BackButton.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/main_menu/main_menu.tscn"))
	print("LIGHTING %s" % lightmap_report())
	var shot := Platform.get_user_arg("--shot")
	if not shot.is_empty():
		await get_tree().create_timer(3.0).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		print("LIGHTING %s" % _label.text.replace("\n", " | "))
		get_tree().quit()


## Runs every rig style at 8 and 16 runners (2 s warm-up, 10 s measured)
## and prints one RIGBENCH line each: the PLAN §4 on-device comparison.
func rig_bench() -> void:
	var results := PackedStringArray()
	for style: String in ["skinned", "parts"]:
		for count: int in [8, 16]:
			PlayerVisual.style = style
			_runner_count = count
			_spawn_runners()
			await get_tree().create_timer(2.0).timeout
			_stats.clear()
			_gpu_ms.clear()
			var draws := FrameStats.new(600)
			var t_end := Time.get_ticks_msec() + 10000
			while Time.get_ticks_msec() < t_end:
				await get_tree().process_frame
				draws.add(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			var line := "RIGBENCH %s x%d  frame p50 %.2f p95 %.2f ms  GPU p50 %.2f p95 %.2f ms  draws p50 %d  shadows %s" % [
					style, count, _stats.percentile(50.0), _stats.percentile(95.0),
					_gpu_ms.percentile(50.0), _gpu_ms.percentile(95.0), draws.percentile(50.0),
					"on" if _sun.shadow_enabled else "off"]
			print(line)
			results.append(line)
	_bench_report = "\n" + "\n".join(results)


## Character comparison bench (PLAN §4, M2): N runners in the current rig style.
func _spawn_runners() -> void:
	for v in _runners:
		v.queue_free()
	_runners.clear()
	for i in _runner_count:
		var v := PlayerVisual.new()
		add_child(v)
		v.setup("Runner %d" % (i + 1), false, COLORS[i % COLORS.size()], i)
		_runners.append(v)
	_stats.clear()
	_gpu_ms.clear()


func _add_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = %BackButton.custom_minimum_size
	b.pressed.connect(action)
	%BackButton.get_parent().add_child(b)
	%BackButton.get_parent().move_child(b, %BackButton.get_index())


func _process(delta: float) -> void:
	_time += delta
	_stats.add(delta * 1000.0)
	_gpu_ms.add(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	for i in (_runners.size() if _runner_count > 1 else 0):
		# Alternate rings run in opposite directions; every third runner
		# backpedals and every fourth jumps, to exercise all clips.
		var dir := 1.0 if i % 2 == 0 else -1.0
		var r := 3.0 + 1.5 * (i % 3)
		var w := 5.5 / r * dir
		var a := _time * w + i * TAU / _runners.size()
		var s := PlayerSimState.new()
		s.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		s.velocity = Vector3(-sin(a), 0.0, cos(a)) * r * w
		s.yaw = atan2(s.velocity.x, s.velocity.z) + PI + (PI if i % 3 == 2 else 0.0)
		s.move_state = PlayerSimState.Move.AIR if i % 4 == 3 and fmod(_time + i, 3.0) < 0.6 else PlayerSimState.Move.GROUND
		s.position.y = sin(fmod(_time + i, 3.0) / 0.6 * PI) * 0.9 if s.move_state == PlayerSimState.Move.AIR else 0.0
		s.alive = true
		s.weapons = PackedInt32Array([[Weapons.PULSE, Weapons.SCATTER, Weapons.RAIL][i % 3]])
		_runners[i].update_from(null, s, 1.0, _time)
	if _runner_count == 1:
		# Character close-up: one figure idling (or jogging with --jog), slow orbit.
		var spot := Vector3(-4.0, 0.0, 2.5)
		var s1 := PlayerSimState.new()
		s1.position = spot
		s1.alive = true
		s1.move_state = PlayerSimState.Move.GROUND
		s1.yaw = 0.0
		s1.weapons = PackedInt32Array([Weapons.PULSE])
		if Platform.user_args.has("--jog"):
			s1.velocity = Vector3(0, 0, -4.5)
		_runners[0].update_from(null, s1, 1.0, _time)
		var a := _time * 0.25 + float(Platform.get_user_arg("--angle", "0.6"))
		_camera.position = spot + Vector3(sin(a) * 2.2, 1.45, -cos(a) * 2.2)
		_camera.look_at(spot + Vector3(0, 1.05, 0))
	else:
		_camera.position = Vector3(sin(_time * 0.1) * 9.0, 5.0, cos(_time * 0.1) * 9.0)
		_camera.look_at(Vector3(0, 1, 0))
	_label.text = "LIGHTING TEST  fps %d  frame p50 %.1f p95 %.1f ms  GPU p50 %.2f p95 %.2f ms\nrig %s x%d  sun shadows %s  lightmap %s  bicubic %s  shadowmask %s  scale %.2f  draw calls %d\n%s" % [
		Engine.get_frames_per_second(), _stats.percentile(50.0), _stats.percentile(95.0),
		_gpu_ms.percentile(50.0), _gpu_ms.percentile(95.0), PlayerVisual.style, _runners.size(),
		"on" if _sun.shadow_enabled else "off", "on" if _lightmap.visible else "off", "on" if _bicubic else "off",
		"on" if _lightmap.shadowmask_mode != LightmapGIData.SHADOWMASK_MODE_NONE else "off", get_tree().root.scaling_3d_scale,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), lightmap_report()] + _bench_report


## Lightmap atlas format and size (what the plan's 32 MiB budget is measured
## against) plus total texture memory.
func lightmap_report() -> String:
	var tex_mem := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var data := _lightmap.light_data
	if data == null:
		return "not baked  texture mem %.1f MiB" % tex_mem
	var parts := PackedStringArray()
	for t: TextureLayered in data.lightmap_textures:
		if t != null:
			parts.append("%dx%dx%d %s mips=%s" % [t.get_width(), t.get_height(), t.get_layers(),
					_format_name(t.get_format()), t.has_mipmaps()])
	return "lightmap [%s]  texture mem %.1f MiB" % [", ".join(parts), tex_mem]


static func _format_name(f: int) -> String:
	match f:
		Image.FORMAT_RGBA8: return "RGBA8"
		Image.FORMAT_RGBAH: return "RGBAH"
		Image.FORMAT_RGBAF: return "RGBAF"
		Image.FORMAT_RGBE9995: return "RGBE9995"
		Image.FORMAT_BPTC_RGBFU: return "BC6H"
		Image.FORMAT_ASTC_4x4_HDR: return "ASTC4x4_HDR"
		Image.FORMAT_ETC2_RGBA8: return "ETC2_RGBA8"
		Image.FORMAT_DXT5: return "DXT5"
	return "format %d" % f
