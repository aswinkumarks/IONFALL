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
		"display_mode": "windowed",  ## desktop: windowed / fullscreen / exclusive
		"resolution": "native",  ## "native" or "WxH" (window size, or 3D resolution when fullscreen)
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
	var mode: String = get_value("video", "display_mode")
	var res := parse_resolution(get_value("video", "resolution"))
	var desktop := has_window_modes()
	if desktop and [mode, res] != _applied_window:
		_applied_window = [mode, res]
		match mode:
			"fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"exclusive":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			_:
				if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				if res != Vector2i.ZERO:
					var screen := DisplayServer.screen_get_usable_rect()
					var size := Vector2i(mini(res.x, screen.size.x), mini(res.y, screen.size.y))
					DisplayServer.window_set_size(size)
					DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	# Fullscreen (and phones): the resolution picks the 3D render resolution.
	var res_scale := 1.0
	var windowed := desktop and mode == "windowed"
	if not windowed and res != Vector2i.ZERO:
		res_scale = clampf(float(res.y) / maxf(DisplayServer.window_get_size().y, 1.0), 0.25, 1.0)
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = clampf(float(get_value("video", "render_scale")) * res_scale, 0.25, 1.0)
	Engine.max_fps = int(get_value("video", "fps_cap"))


var _applied_window: Array = []


## Desktop windows can change mode and size; phones, browsers and headless
## runs can't.
func has_window_modes() -> bool:
	return not (Platform.is_mobile() or Platform.is_web()) and DisplayServer.get_name() != "headless"


static func parse_resolution(v: Variant) -> Vector2i:
	var parts := str(v).split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(parts[0].to_int(), parts[1].to_int())


## Choices for the resolution setting: "native" plus standard heights up to
## the screen's. Desktop windows use 16:9; fullscreen/phones follow the
## screen's aspect ratio.
func resolution_options() -> Array:
	var screen := DisplayServer.screen_get_size()
	var aspect := 16.0 / 9.0 if has_window_modes() and get_value("video", "display_mode") == "windowed" \
			else float(screen.x) / maxf(screen.y, 1.0)
	var out: Array = ["native"]
	for h: int in [2160, 1440, 1080, 900, 720, 540]:
		var w := roundi(h * aspect / 2.0) * 2
		if h <= screen.y and w <= screen.x:
			out.append("%dx%d" % [w, h])
	var current: String = get_value("video", "resolution")
	if not out.has(current):
		out.append(current)
	return out


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
