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
		"fov": 68.0,  ## vertical degrees (≈ 100° horizontal at 16:9)
		"shadows": true,
	},
	"input": {
		"sensitivity_x": 1.0,
		"sensitivity_y": 1.0,
		"touch_sensitivity": 1.0,
		"invert_y": false,
		"crouch_toggle": false,
		"sprint_toggle": false,
		"aim_toggle": false,
		"keymap": {},  ## action -> physical keycode overrides
	},
	"accessibility": {
		"hud_scale": 1.0,
		"reduce_screen_shake": false,
		"vignette": 1.0,  ## low-health vignette intensity
		"captions": true,
	},
	"audio": {
		"master": 1.0,
		"music": 0.7,
		"sfx": 1.0,
		"night_mode": false,  ## compressed dynamic range (PLAN §3.12)
	},
}

var _cfg := ConfigFile.new()


func _ready() -> void:
	load_settings()
	apply_video()
	apply_audio()
	Events.settings_changed.connect(func(section: String, _key: String, _value: Variant) -> void:
		if section == "video":
			apply_video()
		elif section == "audio":
			apply_audio())


## Bus layout (PLAN §3.12): Master → Music, SFX → Weapons, Footsteps, World,
## UI, and Occluded (−6 dB, 2 kHz low-pass) for sounds behind walls.
const BUSES := [["Music", "Master"], ["SFX", "Master"], ["Weapons", "SFX"], ["Footsteps", "SFX"], ["World", "SFX"],
		["UI", "SFX"], ["Occluded", "SFX"]]


func _ensure_buses() -> void:
	if AudioServer.get_bus_index("SFX") != -1:
		return
	for b in BUSES:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, b[0])
		AudioServer.set_bus_send(idx, b[1])
	var occluded := AudioServer.get_bus_index("Occluded")
	AudioServer.set_bus_volume_db(occluded, -6.0)
	# Browsers' default (Sample) playback has no bus effects: volume only.
	if not Platform.is_web():
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = 2000.0
		AudioServer.add_bus_effect(occluded, lowpass)
		var night := AudioEffectCompressor.new()
		night.threshold = -20.0
		night.ratio = 6.0
		night.gain = 6.0
		AudioServer.add_bus_effect(0, night)


func apply_audio() -> void:
	_ensure_buses()
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]:
		var v := clampf(float(get_value("audio", pair[1])), 0.0, 1.0)
		var idx := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.0)
	if AudioServer.get_bus_effect_count(0) > 0:
		AudioServer.set_bus_effect_enabled(0, 0, bool(get_value("audio", "night_mode")))


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
