extends Node3D
## Main-menu backdrop: Meridian Station (baked lighting) under a slow
## orbiting camera, with a few characters running laps. Presentation only.

const RUNNERS := 4
const COLORS := [Color(0.31, 0.89, 1.0), Color(1.0, 0.6, 0.24), Color(0.36, 0.95, 0.63), Color(0.85, 0.5, 1.0)]

var _camera := Camera3D.new()
var _runners: Array[PlayerVisual] = []
var _blobs := BlobShadows.new()
var _time: float = 0.0


func _ready() -> void:
	var station := Maps.presentation(Maps.DEFAULT)
	add_child(station)
	RenderLayers.light_dynamic_with_baked_lights(station, Settings.video("lights") == true)
	Settings.apply_environment(station)
	for light in station.find_children("*", "DirectionalLight3D", true, false):
		(light as DirectionalLight3D).shadow_enabled = Settings.video("shadows")
	Events.settings_changed.connect(func(section: String, _key: String, _value: Variant) -> void:
		if section == "video" and is_inside_tree():
			Settings.apply_environment(station)
			RenderLayers.light_dynamic_with_baked_lights(station, Settings.video("lights") == true)
			for light in station.find_children("*", "DirectionalLight3D", true, false):
				(light as DirectionalLight3D).shadow_enabled = Settings.video("shadows"))
	_camera.fov = 62.0
	_camera.current = true
	add_child(_camera)
	for i in RUNNERS:
		var v := PlayerVisual.new()
		add_child(v)
		v.setup("", false, COLORS[i % COLORS.size()], i)
		v.hide_nameplate()
		_runners.append(v)
	_blobs.floor_at_feet = true
	add_child(_blobs)
	_time = randf() * 100.0
	_process(0.0)


func _process(delta: float) -> void:
	_time += delta
	# Camera: a slow half-height orbit around the ion core.
	var a := _time * 0.045
	_camera.position = Vector3(sin(a) * 23.0, 8.5 + sin(_time * 0.11) * 0.8, cos(a) * 17.0)
	# Aim right of the core so it sits beside the menu column, not under it.
	var right := Vector3(cos(a), 0.0, -sin(a))
	_camera.look_at(Vector3(0.0, 2.0, 0.0) - right * 6.0)
	# Runners lap the floor ring around the core in both directions.
	for i in _runners.size():
		var dir := 1.0 if i % 2 == 0 else -1.0
		var r := 6.5 + 1.2 * i
		var w := 5.0 / r * dir
		var t := _time * w + i * 1.7
		var s := PlayerSimState.new()
		s.position = Vector3(cos(t) * r, 0.0, sin(t) * r * 0.8)
		s.velocity = Vector3(-sin(t) * r, 0.0, cos(t) * r * 0.8) * w
		s.yaw = atan2(s.velocity.x, s.velocity.z) + PI
		s.move_state = PlayerSimState.Move.GROUND
		s.alive = true
		_runners[i].update_from(null, s, 1.0, _time)
	if _blobs.visible:
		var feet := PackedVector3Array()
		for v in _runners:
			feet.append(v.global_position)
		_blobs.show_at(feet)
