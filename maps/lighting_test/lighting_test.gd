extends Node3D
## Lighting validation scene (PLAN §3.9, M1c): baked floor and walls
## (LightmapGI, Static accent lights) with a Dynamic sun casting realtime
## character shadows. Shows the numbers the plan asks for: lightmap texture
## format and memory, frame time, and the cost of the sun's shadow pass.
##
## Desktop: `godot -- --lighting-test`. Android: the diagnostics overlay.
## Bake in the editor (select LightmapGI → Bake Lightmaps) after changing
## geometry or lights; the .lmbake/.exr go to Git LFS.

const RUNNERS := 4

@onready var _sun: DirectionalLight3D = $Sun
@onready var _lightmap: LightmapGI = $LightmapGI
@onready var _camera: Camera3D = $Camera
@onready var _label: Label = %Info

var _runners: Array[PlayerVisual] = []
var _time: float = 0.0
var _stats := FrameStats.new(600)
var _base_texture_mem: float = -1.0


func _ready() -> void:
	for i in RUNNERS:
		var v := PlayerVisual.new()
		add_child(v)
		v.setup("Runner %d" % (i + 1), false, [Color(0.55, 0.45, 1.0), Color(0.3, 0.85, 0.5), Color(0.95, 0.4, 0.6), Color(0.95, 0.5, 0.2)][i])
		_runners.append(v)
	%ShadowsButton.pressed.connect(func() -> void: _sun.shadow_enabled = not _sun.shadow_enabled)
	%LightmapButton.pressed.connect(func() -> void: _lightmap.visible = not _lightmap.visible)
	%BackButton.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://ui/main_menu/main_menu.tscn"))
	print("LIGHTING %s" % lightmap_report())
	var shot := Platform.get_user_arg("--shot")
	if not shot.is_empty():
		await get_tree().create_timer(3.0).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		print("LIGHTING %s" % _label.text.replace("\n", " | "))
		get_tree().quit()


func _process(delta: float) -> void:
	_time += delta
	_stats.add(delta * 1000.0)
	for i in _runners.size():
		var a := _time * 0.6 + i * TAU / _runners.size()
		var r := 4.0 + 2.0 * (i % 2)
		var s := PlayerSimState.new()
		s.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
		s.yaw = -a
		s.alive = true
		_runners[i].update_from(null, s, 1.0, _time)
	_camera.position = Vector3(sin(_time * 0.1) * 9.0, 5.0, cos(_time * 0.1) * 9.0)
	_camera.look_at(Vector3(0, 1, 0))
	_label.text = "LIGHTING TEST  fps %d  frame p50 %.1f p95 %.1f ms\nsun shadows %s  lightmap %s  draw calls %d\n%s" % [
		Engine.get_frames_per_second(), _stats.percentile(50.0), _stats.percentile(95.0),
		"on" if _sun.shadow_enabled else "off", "on" if _lightmap.visible else "off",
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), lightmap_report()]


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
