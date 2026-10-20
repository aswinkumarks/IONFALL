extends Node
## Diagnostics service: frame statistics and the debug overlay (PLAN §3.15).
##
## Toggle the overlay with F3 on desktop or a three-finger tap on touch.

const OVERLAY_SCENE := preload("res://ui/diagnostics/diagnostics_overlay.tscn")

var frame_stats := FrameStats.new(600)
## Set by the active match: func() -> String with network rows for the overlay.
var net_info: Callable
## Soak testing: the local player is driven by a bot (toggled in the overlay,
## or `--autopilot` on the command line).
var autopilot: bool = false
## Live effect particles (set by Effects; PLAN §3.10 budget: ≤ 2,000).
var live_particles: int = 0
var _overlay: CanvasLayer
## Per-frame CPU time of named code sections (PLAN §3.10 frame budget):
## name -> FrameStats of each frame's total (ms); this frame's sums in _frame_us.
var _sections: Dictionary = {}
var _frame_us: Dictionary = {}
var _touches: Dictionary = {}


func _ready() -> void:
	if Platform.is_dedicated_server():
		set_process(false)
		set_process_input(false)
		return
	autopilot = Platform.user_args.has("--autopilot")
	_overlay = OVERLAY_SCENE.instantiate()
	_overlay.visible = false
	add_child(_overlay)
	# Automated visual checks: `-- --shot file.png --shot-after 8` saves a
	# screenshot after that many seconds and quits.
	var shot := Platform.get_user_arg("--shot")
	if not shot.is_empty() and not Platform.user_args.has("--lighting-test"):
		await get_tree().create_timer(Platform.get_user_arg("--shot-after", "5").to_float()).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _process(delta: float) -> void:
	frame_stats.add(delta * 1000.0)
	for name: String in _frame_us:
		if not _sections.has(name):
			_sections[name] = FrameStats.new(7200)
		(_sections[name] as FrameStats).add(_frame_us[name] / 1000.0)
		_frame_us[name] = 0


## Adds `usec` (since `Time.get_ticks_usec()` at the start) to this frame's
## time for section `name`.
func time_section(name: String, start_usec: int) -> void:
	_frame_us[name] = int(_frame_us.get(name, 0)) + Time.get_ticks_usec() - start_usec


## "name=p50/p95 ..." for every section since the last call (ms), then resets.
func section_report() -> String:
	var parts := PackedStringArray()
	for name: String in _sections:
		var st: FrameStats = _sections[name]
		parts.append("%s=%.2f/%.2f" % [name, st.percentile(50.0), st.percentile(95.0)])
		st.clear()
	return " ".join(parts)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle_overlay()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = true
			if _touches.size() == 3:
				toggle_overlay()
		else:
			_touches.erase(event.index)


func toggle_overlay() -> void:
	if _overlay == null:
		return
	_overlay.visible = not _overlay.visible
	Events.diagnostics_toggled.emit(_overlay.visible)
