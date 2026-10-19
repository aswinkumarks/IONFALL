extends Node
## Player settings stored in `user://settings.cfg` (PLAN §3.13).

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"profile": {
		"name": "",
		"last_address": "",
		"uuid": "",
	},
	"video": {
		"render_scale": 0.75,
		"fps_cap": 60,
	},
	"input": {
		"sensitivity_x": 1.0,
		"sensitivity_y": 1.0,
		"invert_y": false,
	},
	"accessibility": {
		"hud_scale": 1.0,
		"reduce_screen_shake": false,
	},
	"audio": {
		"master": 1.0,
		"music": 0.7,
		"sfx": 1.0,
	},
}

var _cfg := ConfigFile.new()


func _ready() -> void:
	load_settings()
	apply_video()
	Events.settings_changed.connect(func(section: String, _key: String, _value: Variant) -> void:
		if section == "video":
			apply_video())


## Render scale (bilinear on the Mobile renderer, PLAN §3.9) and fps cap.
func apply_video() -> void:
	if Platform.is_dedicated_server():
		return
	var root := get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = clampf(float(get_value("video", "render_scale")), 0.5, 1.0)
	Engine.max_fps = int(get_value("video", "fps_cap"))


func get_value(section: String, key: String) -> Variant:
	return _cfg.get_value(section, key, DEFAULTS.get(section, {}).get(key))


func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	Events.settings_changed.emit(section, key, value)


func load_settings() -> void:
	_cfg = ConfigFile.new()
	var text := AtomicFile.read_text(PATH, func(t: String) -> bool:
		return ConfigFile.new().parse(t) == OK)
	if not text.is_empty():
		_cfg.parse(text)


func save_settings() -> Error:
	if not Platform.storage_available:
		return ERR_UNAVAILABLE
	return AtomicFile.write_text(PATH, _cfg.encode_to_text())
