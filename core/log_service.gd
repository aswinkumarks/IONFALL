extends Node
## Runs the session log (Log): the first autoload, so it opens the file before
## anything else logs. Writes a header with the build, device, GPU, renderer
## and settings; flushes every FLUSH_SECONDS (warnings and errors at once);
## logs scene changes, app pauses, memory warnings and a performance line
## every PERF_SECONDS; and marks a clean exit, so the next start can tell a
## crash or kill from a normal close.

const FLUSH_SECONDS := 2.0
const PERF_SECONDS := 60.0

var _flush_left: float = FLUSH_SECONDS
var _perf_left: float = PERF_SECONDS
var _frames: int = 0
var _worst_ms: float = 0.0
var _last_us: int = 0


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var lvl := args.find("--log-level")
	if lvl != -1 and lvl + 1 < args.size():
		Log.level = Log.level_from_name(args[lvl + 1])
	var previous := Log.open(_android_log_dir())
	Log.i("log", "IONFALL session log %s (level %s)" % [ProjectSettings.globalize_path(Log.path) if not Log.path.is_empty()
			else "(console only)", Log.LEVEL_NAMES[Log.level]])
	if not previous.is_empty():
		if Log.ended_cleanly(previous):
			Log.i("log", "previous session: %s (closed normally)" % previous.get_file())
		else:
			Log.w("log", "previous session %s did not close normally (crash, kill, or closed from the app switcher): send that file too" % previous.get_file())


## Android: the app's external files folder (Android/data/<package>/files/
## logs), which a USB file transfer or `adb pull` reads without root, even
## after a crash; elsewhere "" (user://logs/).
static func _android_log_dir() -> String:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return ""
	var ctx: Variant = Engine.get_singleton("AndroidRuntime").call("getApplicationContext")
	if ctx == null:
		return ""
	return "/storage/emulated/0/Android/data/%s/files/logs" % ctx.call("getPackageName")


func _ready() -> void:
	# The click trail: every button press, with its text and where it is.
	get_tree().node_added.connect(func(node: Node) -> void:
		if node is BaseButton:
			(node as BaseButton).pressed.connect(_on_button.bind(node)))
	get_tree().scene_changed.connect(func() -> void:
		var scene := get_tree().current_scene
		Log.i("scene", "now %s" % (scene.scene_file_path if scene != null and not scene.scene_file_path.is_empty()
				else str(scene))))
	_system_info.call_deferred()  # after the other autoloads are ready


func _exit_tree() -> void:
	Log.close()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			Log.i("app", "window close requested")
		NOTIFICATION_APPLICATION_PAUSED:
			Log.i("app", "paused (in the background)")
			Log.flush()  # a phone may kill a paused app without notice
		NOTIFICATION_APPLICATION_RESUMED:
			Log.i("app", "resumed")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Log.d("app", "focus lost")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Log.d("app", "focus gained")
		NOTIFICATION_OS_MEMORY_WARNING:
			Log.w("app", "the OS reports low memory (%s)" % _memory())
		NOTIFICATION_CRASH:
			Log.e("app", "the engine is crashing (backtrace follows in the console / godot.log)")
			Log.flush()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_worst_ms = maxf(_worst_ms, (now - _last_us) / 1000.0)
	_last_us = now
	_frames += 1
	_flush_left -= delta
	if _flush_left <= 0.0:
		_flush_left = FLUSH_SECONDS
		Log.flush()
	_perf_left -= delta
	if _perf_left <= 0.0:
		_perf_left = PERF_SECONDS
		_perf_line()


func _on_button(button: BaseButton) -> void:
	var label := ""
	if button is Button:
		label = (button as Button).text
	if label.is_empty():
		label = button.tooltip_text
	var where := str(button.get_path()).trim_prefix("/root/")
	if button.toggle_mode:
		Log.d("ui", "toggled \"%s\" %s (%s)" % [label, "on" if button.button_pressed else "off", where])
	else:
		Log.d("ui", "pressed \"%s\" (%s)" % [label, where])


## Frame rate over the last PERF_SECONDS, frame times, memory and draw
## calls, and any adaptive step-downs.
func _perf_line() -> void:
	var stats: FrameStats = Diagnostics.frame_stats if has_node("/root/Diagnostics") else null
	var line := "%.1f fps over %.0f s, worst frame %.1f ms" % [_frames / PERF_SECONDS, PERF_SECONDS, _worst_ms]
	if stats != null and stats.count() > 0:
		line += ", recent avg %.2f / p95 %.2f / p99 %.2f ms" % [stats.average(), stats.percentile(95.0), stats.percentile(99.0)]
	var vp := get_viewport().get_viewport_rid()
	line += ", gpu %.2f ms, cpu %.2f ms" % [RenderingServer.viewport_get_measured_render_time_gpu(vp),
			RenderingServer.viewport_get_measured_render_time_cpu(vp)]
	line += ", draws %d, objects %d, nodes %d, %s" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), _memory()]
	if not Settings.adaptive.is_empty():
		line += ", adaptive %s" % Settings.adaptive
	Log.i("perf", line)
	if has_node("/root/Diagnostics") and Diagnostics.net_info.is_valid():
		var net := Diagnostics.net_info.call() as String
		if net != "NET offline":
			Log.i("perf", net.replace("\n", " | "))
	_frames = 0
	_worst_ms = 0.0


func _memory() -> String:
	return "memory %.0f MB, video %.0f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]


## The session header: what a bug report needs to know about this run.
func _system_info() -> void:
	Log.i("sys", "IONFALL %s, artifact %s, protocol %d, engine %s, %s build" % [BuildInfo.display_string(),
			BuildInfo.artifact_id, BuildInfo.protocol_version, BuildInfo.engine_version,
			"debug" if OS.is_debug_build() else "release"])
	Log.i("sys", "%s %s %s on %s, %s (%d threads), locale %s" % [OS.get_name(), OS.get_distribution_name(), OS.get_version(), OS.get_model_name(),
			OS.get_processor_name(), OS.get_processor_count(), OS.get_locale()])
	var mem := OS.get_memory_info()
	Log.i("sys", "RAM %.1f GB, %.1f GB free" % [float(mem.get("physical", -1)) / 1073741824.0,
			float(mem.get("available", -1)) / 1073741824.0])
	var adapter_types := ["other", "integrated", "dedicated", "virtual", "cpu"]
	Log.i("sys", "GPU %s (%s, %s), %s %s, renderer %s" % [RenderingServer.get_video_adapter_name(),
			RenderingServer.get_video_adapter_vendor(),
			adapter_types[clampi(RenderingServer.get_video_adapter_type(), 0, 4)],
			RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_api_version(),
			RenderingServer.get_current_rendering_method()])
	if DisplayServer.get_name() != "headless":
		var screen := DisplayServer.window_get_current_screen()
		Log.i("sys", "display %s, screen %s at %.0f Hz (scale %.2f, dpi %d), window %s, mode %d" % [
				DisplayServer.get_name(), DisplayServer.screen_get_size(screen),
				DisplayServer.screen_get_refresh_rate(screen), DisplayServer.screen_get_scale(screen),
				DisplayServer.screen_get_dpi(screen), DisplayServer.window_get_size(), DisplayServer.window_get_mode()])
	Log.i("sys", "args %s %s, user data %s" % [OS.get_cmdline_args(), OS.get_cmdline_user_args(),
			OS.get_user_data_dir()])
	Log.i("sys", "settings: quality %s, preset %s" % [Settings.get_value("video", "quality"), Settings.quality_preset()])
	for section: String in Settings.DEFAULTS:
		var values := {}
		for key: String in Settings.DEFAULTS[section]:
			if key not in ["keymap", "touch_layout"]:
				values[key] = Settings.get_value(section, key)
		Log.d("sys", "settings %s: %s" % [section, values])
	Log.flush()
