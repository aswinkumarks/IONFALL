extends CanvasLayer
## Debug overlay showing frame-time percentiles and build info (PLAN §3.15).
## Network and server rows are added in M1b.

@onready var _label: Label = %StatsLabel

var _refresh_timer := 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.25
	var stats := Diagnostics.frame_stats
	_label.text = "%s\n%s | %s\nFPS %d\nframe ms  p50 %.1f  p95 %.1f  p99 %.1f\ndraw calls %d  primitives %d\nvideo mem %.0f MiB" % [
		BuildInfo.display_string(),
		OS.get_name(),
		RenderingServer.get_video_adapter_name(),
		Engine.get_frames_per_second(),
		stats.percentile(50.0),
		stats.percentile(95.0),
		stats.percentile(99.0),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	]
