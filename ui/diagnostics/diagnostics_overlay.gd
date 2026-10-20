extends CanvasLayer
## Debug overlay showing frame-time percentiles and build info (PLAN §3.15).
## The active match adds network rows through `Diagnostics.net_info`.

@onready var _label: Label = %StatsLabel

var _refresh_timer := 0.0
var _replay_result: String = ""


func _ready() -> void:
	# Cross-platform determinism check (PLAN §3.2): results go to the log
	# (`adb logcat -s godot` on Android) and are summarized here.
	var button := Button.new()
	button.text = "Replay check"
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	button.pressed.connect(func() -> void:
		button.disabled = true
		_replay_result = "replay check running…"
		var check := ReplayCheck.new()
		check.finished.connect(func(summary: String) -> void:
			_replay_result = summary
			button.disabled = false)
		get_tree().root.add_child(check))
	add_child(button)
	var pilot := Button.new()
	pilot.text = "Autopilot: " + ("on" if Diagnostics.autopilot else "off")
	pilot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	pilot.position.x += 190
	pilot.pressed.connect(func() -> void:
		Diagnostics.autopilot = not Diagnostics.autopilot
		pilot.text = "Autopilot: " + ("on" if Diagnostics.autopilot else "off"))
	add_child(pilot)
	var lighting := Button.new()
	lighting.text = "Lighting test"
	lighting.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	lighting.position.x += 380
	lighting.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://maps/lighting_test/lighting_test.tscn"))
	add_child(lighting)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.25
	var stats := Diagnostics.frame_stats
	_label.text = "%s\n%s | %s\nFPS %d\nframe ms  p50 %.1f  p95 %.1f  p99 %.1f\ndraw calls %d  primitives %d  particles %d\nvideo mem %.0f MiB" % [
		BuildInfo.display_string(),
		OS.get_name(),
		RenderingServer.get_video_adapter_name(),
		Engine.get_frames_per_second(),
		stats.percentile(50.0),
		stats.percentile(95.0),
		stats.percentile(99.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Diagnostics.live_particles,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	]
	if not _replay_result.is_empty():
		_label.text += "\n" + _replay_result
	if Diagnostics.net_info.is_valid():
		_label.text += "\n" + str(Diagnostics.net_info.call())
