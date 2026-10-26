extends Node
## Player settings stored in `user://settings.cfg` (PLAN §3.13).

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"profile": {
		"name": "",
		"last_address": "",
		"uuid": "",
		"character": "sentinel",  ## CharacterRig.SELECTABLE
		"color": 0,  ## PlayerVisual.PALETTE index, 0 = auto
		"primary": 0,  ## Loadouts.PRIMARIES index
		"map": "station",  ## Maps.PLAYABLE, for Play and Host
		"mode": "ffa",  ## GameMode.IDS, for Play and Host
		"minutes": 10,  ## match length (LobbySession.DURATIONS), for single player and lobbies
		"friendly_fire": false,  ## TDM and CTF, single player and hosting (PLAN §2.3)
		"bot_difficulty": "normal",  ## BotBrain.DIFFICULTY_IDS
		"bots": 3,  ## bots next to you (single player, hosting), up to MatchConfig.max_bots()
		"browser_players": false,  ## LAN hosts also take browsers over WebSocket (PLAN §3.20)
		"team_names": ["", ""],  ## the host's team names ("" = the default), GameMode
		"team_colors": [0, 1],  ## the host's team colours, GameMode.TEAM_PALETTE indices
	},
	"video": {
		"display_mode": "windowed",  ## desktop: windowed / fullscreen / exclusive
		"resolution": "native",  ## "native" or "WxH" (window size, or 3D resolution when fullscreen)
		"quality": "",  ## low / medium / high / ultra / custom; "" = platform default
		"render_scale": 0.75,
		"fps_cap": 60,
		"fov": 68.0,  ## vertical degrees (≈ 100° horizontal at 16:9)
		"shadows": true,
		"glow": true,
		"effects": 1.0,  ## particle density
		"adaptive_quality": true,  ## automatic step-down when slow or hot (PLAN §3.10)
		"anti_aliasing": "auto",  ## auto (the preset's) / off / fxaa / msaa_2x / msaa_4x
	},
	"input": {
		"sensitivity_x": 1.0,
		"sensitivity_y": 1.0,
		"touch_sensitivity": 1.0,
		"invert_y": false,
		"crouch_toggle": false,
		"sprint_toggle": false,
		"aim_toggle": false,
		"aim_assist": true,  ## touch only (PLAN §3.11)
		"auto_fire": false,  ## touch only
		"touch_layout": {},  ## {v: 2, button id: [x, y, scale]} (TouchControls.DEFAULT_BUTTONS units)
		"touch_opacity": 0.8,
		"keymap": {},  ## action -> physical keycode overrides
	},
	"hud": {
		"show_stats": true,  ## FPS and latency in the top-left corner
	},
	"accessibility": {
		"hud_scale": 1.0,
		"reduce_screen_shake": false,
		"reduce_flashes": false,  ## dimmer, smaller muzzle flashes, explosions and screen tints (PLAN §3.16)
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
## Session-only step-downs from the adaptive quality governor (PLAN §3.10):
## video key -> value used instead of the setting. Never saved; cleared when
## the player changes a video setting.
var adaptive: Dictionary = {}
## `--quality <preset>[,key=value...]`: this session uses
## that preset's video values, with any overrides, without saving them, for
## performance tests. Example: `--quality medium,glow=false`.
var _quality_override: String = ""
var _override_preset: Dictionary = {}


func _ready() -> void:
	load_settings()
	var q := Platform.get_user_arg("--quality").split(",")
	if QUALITY.has(q[0]):
		_quality_override = q[0]
		_override_preset = preset_for(q[0], Platform.is_mobile()).duplicate()
		for pair in q.slice(1):
			var key := pair.get_slice("=", 0)
			if _override_preset.has(key) or DEFAULTS.video.has(key):
				_override_preset[key] = str_to_var(pair.get_slice("=", 1))
	apply_video()
	apply_audio()
	Events.settings_changed.connect(func(section: String, _key: String, _value: Variant) -> void:
		if section == "video":
			apply_video()
		elif section == "audio":
			apply_audio())


## Bus layout (PLAN §3.12): Master → Music, SFX → Weapons, Footsteps, World,
## UI, Occluded (−6 dB, 2 kHz low-pass) for sounds behind walls and Below
## (−1.5 dB, 5 kHz low-pass) for sounds from the level below: the vertical cue.
const BUSES := [["Music", "Master"], ["SFX", "Master"], ["Weapons", "SFX"], ["Footsteps", "SFX"], ["World", "SFX"],
		["UI", "SFX"], ["Occluded", "SFX"], ["Below", "SFX"]]


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
	var below := AudioServer.get_bus_index("Below")
	AudioServer.set_bus_volume_db(below, -1.5)
	# Browsers' default (Sample) playback has no bus effects: volume only.
	if not Platform.is_web():
		var lowpass := AudioEffectLowPassFilter.new()
		lowpass.cutoff_hz = 2000.0
		AudioServer.add_bus_effect(occluded, lowpass)
		var muffle := AudioEffectLowPassFilter.new()
		muffle.cutoff_hz = 5000.0
		AudioServer.add_bus_effect(below, muffle)
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
	var preset := quality_preset()
	var scale := clampf(float(video("render_scale")) * res_scale, 0.25, 1.0)
	# FSR only helps when actually upscaling; it also sharpens. The Mobile
	# renderer (phones) doesn't support it and would warn, so they get bilinear.
	if preset.upscale == "fsr" and scale < 0.99 and RenderingServer.get_current_rendering_method() == "forward_plus":
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		root.fsr_sharpness = 0.35
	else:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = scale
	# "auto" follows the preset's MSAA, or the governor's step-down of it.
	var aa := anti_aliasing_for(str(get_value("video", "anti_aliasing")), preset.merged({"msaa": video("msaa")}, true))
	root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa.x]
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa.y == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	root.anisotropic_filtering_level = preset.aniso
	root.mesh_lod_threshold = preset.lod
	RenderingServer.directional_shadow_atlas_set_size(preset.shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(preset.soft_shadows)
	RenderingServer.positional_soft_shadow_filter_set_quality(preset.soft_shadows)
	_apply_fps_cap()


## Menus and the lobby on a phone run at most MENU_FPS: their backdrop is
## full 3D, and heat is what limits a phone's match frame rate (m4.md).
const MENU_FPS := 30
var _in_menu := false


## Entering a menu (true) or a match (false).
func set_menu_mode(on: bool) -> void:
	_in_menu = on
	_apply_fps_cap()


func _apply_fps_cap() -> void:
	var cap := int(get_value("video", "fps_cap"))
	if _in_menu and Platform.is_mobile():
		cap = mini(cap, MENU_FPS) if cap > 0 else MENU_FPS
	Engine.max_fps = cap


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
	if section == "video" and not _quality_override.is_empty() and (key == "quality" or _override_preset.has(key)):
		return _quality_override if key == "quality" else _override_preset[key]
	if section == "video" and not _cfg.has_section_key(section, key):
		# Video defaults follow the platform's quality preset.
		var q := default_quality()
		if key == "quality":
			return q
		# Keys added after the file was saved follow the chosen preset.
		var preset: Dictionary = QUALITY.get(_cfg.get_value("video", "quality", q), QUALITY[q])
		if preset.has(key):
			return preset[key]
	return _cfg.get_value(section, key, DEFAULTS.get(section, {}).get(key))


## A video value as it applies now: the setting (or the preset's extra),
## unless the adaptive governor has stepped it down.
func video(key: String) -> Variant:
	if adaptive.has(key):
		return adaptive[key]
	if DEFAULTS.video.has(key):
		return get_value("video", key)
	return quality_preset().get(key)


## The governor lowers `key` for this session (AdaptiveQuality).
func set_adaptive(key: String, value: Variant) -> void:
	adaptive[key] = value
	Events.settings_changed.emit("video", key, value)


func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	if section == "video":
		adaptive.clear()
	if section == "video" and not _applying_preset:
		if key == "quality" and QUALITY.has(value):
			# A preset writes the values it controls (the screen shows them).
			_applying_preset = true
			for k: String in QUALITY[value]:
				if DEFAULTS.video.has(k):
					set_value("video", k, QUALITY[value][k])
			_applying_preset = false
		elif key in PRESET_KEYS and get_value("video", "quality") != "custom":
			_cfg.set_value("video", "quality", "custom")
			Events.settings_changed.emit("video", "quality", "custom")
	Events.settings_changed.emit(section, key, value)


## Graphics presets. "lights": short-lived dynamic lights from effects
## (muzzle flash, explosions, grenades, pickups); off on phones, where each
## surface first lit by one compiles a new pipeline mid-match (M4 hitch log).
## render_scale, shadows, glow and effects (particle density) are also
## individual settings
## (changing them by hand switches the preset to "custom"); the rest is
## applied from the preset ("custom" keeps the last preset's extras).
const QUALITY := {
	"low": {"render_scale": 0.6, "shadows": false, "glow": false, "effects": 0.4, "upscale": "bilinear", "msaa": 0,
			"fxaa": false, "shadow_size": 1024, "soft_shadows": 0, "aniso": 0, "lod": 4.0, "probe": false, "lights": false},
	## Phone default: sized to hold 60 fps on the Mi 11X (docs/perf/m2-station.md,
	## m4.md: FXAA off kept GPU frames under the vsync budget).
	"medium": {"render_scale": 0.6, "shadows": false, "glow": true, "effects": 0.7, "upscale": "fsr", "msaa": 0,
			"fxaa": false, "shadow_size": 2048, "soft_shadows": 0, "aniso": 2, "lod": 2.0, "probe": true, "lights": false},
	"high": {"render_scale": 1.0, "shadows": true, "glow": true, "effects": 1.0, "upscale": "bilinear", "msaa": 1,
			"fxaa": false, "shadow_size": 4096, "soft_shadows": 2, "aniso": 3, "lod": 1.0, "probe": true, "lights": true},
	"ultra": {"render_scale": 1.0, "shadows": true, "glow": true, "effects": 1.0, "upscale": "bilinear", "msaa": 2,
			"fxaa": false, "shadow_size": 4096, "soft_shadows": 4, "aniso": 4, "lod": 0.5, "probe": true, "lights": true},
}
## Phone-only changes to a preset's extras. The reflection probe costs the
## Mi 11X ~0.9 ms of GPU time, so phones leave it off on Medium; desktops
## keep it (m4.md). Phones get 2x MSAA on Medium: on tile-based GPUs it
## resolves in tile memory, and at 0.6 render scale the edges need it. If the
## phone can't afford it, AdaptiveQuality turns it off first (`--aa-bench`
## measures its cost on the device).
const MOBILE_EXTRAS := {"medium": {"probe": false, "msaa": 1}}
const QUALITY_NAMES := ["low", "medium", "high", "ultra", "custom"]
const PRESET_KEYS := ["render_scale", "shadows", "glow", "effects"]

var _applying_preset: bool = false


## Phones start on Medium (Mi 11X budget), browsers on Low, desktops on High.
## The Compatibility (OpenGL) renderer, used in browsers and as the fallback
## on devices without Vulkan (usually older or low-end), starts on Low.
func default_quality() -> String:
	if Platform.is_web() or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return "low"
	return "medium" if Platform.is_mobile() else "high"


## The preset whose extras apply: the chosen one, or for "custom" the
## platform default.
func quality_preset() -> Dictionary:
	if not _override_preset.is_empty():
		return _override_preset
	var q: String = get_value("video", "quality")
	return preset_for(q if QUALITY.has(q) else default_quality(), Platform.is_mobile())


## The anti-aliasing setting's choices. On tile-based phone GPUs (Adreno,
## Mali) MSAA resolves in tile memory and may cost less than FXAA's full
## screen pass (0.5 ms on the Mi 11X, m4.md); `--aa-bench` measures them
## on the device (AaBench).
const ANTI_ALIASING := ["auto", "off", "fxaa", "msaa_2x", "msaa_4x"]


## [MSAA level (0 off, 1 2x, 2 4x), FXAA (1 on)] for anti-aliasing setting
## `choice` with `preset` (QUALITY) as "auto".
static func anti_aliasing_for(choice: String, preset: Dictionary) -> Vector2i:
	match choice:
		"off":
			return Vector2i(0, 0)
		"fxaa":
			return Vector2i(0, 1)
		"msaa_2x":
			return Vector2i(1, 0)
		"msaa_4x":
			return Vector2i(2, 0)
	return Vector2i(int(preset.get("msaa", 0)), 1 if preset.get("fxaa", false) else 0)


## Preset `q`'s values on a phone (`mobile`) or elsewhere (MOBILE_EXTRAS).
static func preset_for(q: String, mobile: bool) -> Dictionary:
	if mobile and MOBILE_EXTRAS.has(q):
		return (QUALITY[q] as Dictionary).merged(MOBILE_EXTRAS[q], true)
	return QUALITY[q]


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


## Applies the quality preset's environment parts (glow) and colour grading
## (a little contrast and saturation, plus the map's LUT from its "grade"
## meta, ColorGrade) to a scene's WorldEnvironment.
func apply_environment(root: Node) -> void:
	var grade: Dictionary = root.get_meta("grade", {})
	for we in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		if env == null:
			continue
		env.glow_enabled = bool(video("glow"))
		env.adjustment_enabled = true
		env.adjustment_contrast = 1.08
		env.adjustment_saturation = 1.12
		if not grade.is_empty():
			env.adjustment_color_correction = ColorGrade.lut(grade)
