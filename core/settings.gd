extends Node
## Player settings stored in `user://settings.cfg` (PLAN §3.13).

const PATH := "user://settings.cfg"

const DEFAULTS := {
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
