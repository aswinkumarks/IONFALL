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
## Log each frame over 50 ms with its section times (set by the match).
var hitch_log: bool = false
## Pipeline compilations by kind (Performance monitors), last frame's totals.
const PIPELINES := {"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS, "mesh": Performance.PIPELINE_COMPILATIONS_MESH,
		"surface": Performance.PIPELINE_COMPILATIONS_SURFACE, "draw": Performance.PIPELINE_COMPILATIONS_DRAW,
		"spec": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION}
var _pipelines: Dictionary = {}
var _hitches_logged: int = 0
var _last_frame_us: int = 0
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
	var ui_steps := Platform.get_user_arg("--ui")
	if not ui_steps.is_empty():
		_run_ui_steps(ui_steps)
	var shot := Platform.get_user_arg("--shot")
	if not shot.is_empty() and not Platform.user_args.has("--lighting-test"):
		await get_tree().create_timer(Platform.get_user_arg("--shot-after", "5").to_float()).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()


func _process(delta: float) -> void:
	frame_stats.add(delta * 1000.0)
	# The engine clamps `delta` on long frames; the hitch log wants the wall
	# clock (cold-cache pipeline compiles stall single frames for seconds).
	var now_us := Time.get_ticks_usec()
	var frame_ms := maxf(delta * 1000.0, (now_us - _last_frame_us) / 1000.0) if _last_frame_us > 0 else delta * 1000.0
	_last_frame_us = now_us
	# A hitch: log what the slow frame's sections took (autoloads process
	# first, so _frame_us still holds that frame's sums).
	var compiled := PackedStringArray()
	for kind: String in PIPELINES:
		var n := int(Performance.get_monitor(PIPELINES[kind]))
		if n != int(_pipelines.get(kind, n)):
			compiled.append("%s+%d" % [kind, n - int(_pipelines[kind])])
		_pipelines[kind] = n
	if frame_ms > 50.0 and hitch_log and _hitches_logged < 40:
		_hitches_logged += 1
		var parts := PackedStringArray()
		for name: String in _frame_us:
			parts.append("%s=%.1f" % [name, _frame_us[name] / 1000.0])
		Platform.perf_log("HITCH %.0f ms %s pipelines[%s]" % [frame_ms, " ".join(parts), ",".join(compiled)])
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


## Automated UI checks through real input events (dev): `-- --ui
## "wait:3,click:MENU_JOIN,type:KFS7WQ,click:MENU_CONNECT,shot:/tmp/a.png"`.
## `click` presses the visible, enabled button whose label, key or `ui_key` meta
## matches, at its on-screen centre (`click:~text`: label contains text); `type` sends key events to the focused control;
## `mouse:right:down` presses or releases a mouse button (in-game: aim, fire, middle: melee);
## `back` sends the Android back button's go-back request; `key:Escape` taps
## a key; `wheel:X:Y:N` scrolls; `shot` saves the screen; `quit` quits. Every step is logged ("UI ...").
func _run_ui_steps(spec: String) -> void:
	for step in spec.split(",", false):
		var kv := step.split(":", true, 1)
		var arg := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"wait":
				await get_tree().create_timer(arg.to_float()).timeout
			"click":
				var button := _find_button(get_tree().root, arg)
				if button == null:
					Platform.perf_log("UI click %s: no such visible button" % arg)
					continue
				var at := get_viewport().get_final_transform() * button.get_global_rect().get_center()
				for pressed: bool in [true, false]:
					var e := InputEventMouseButton.new()
					e.button_index = MOUSE_BUTTON_LEFT
					e.pressed = pressed
					e.position = at
					e.global_position = at
					Input.parse_input_event(e)
					await get_tree().process_frame
				Platform.perf_log("UI click %s at %s" % [arg, at])
			"type":
				for c in arg:
					for pressed: bool in [true, false]:
						var k := InputEventKey.new()
						k.unicode = c.unicode_at(0)
						k.keycode = OS.find_keycode_from_string(c.to_upper())
						k.pressed = pressed
						Input.parse_input_event(k)
						await get_tree().process_frame
				var focus := get_viewport().gui_get_focus_owner()
				Platform.perf_log("UI type %s into %s" % [arg, focus.name if focus else "nothing"])
			"clear":  # select all, then delete, in the focused text field
				for key: Key in [KEY_A, KEY_BACKSPACE]:
					for pressed: bool in [true, false]:
						var k := InputEventKey.new()
						k.keycode = key
						k.ctrl_pressed = key == KEY_A
						k.pressed = pressed
						Input.parse_input_event(k)
						await get_tree().process_frame
			"mouse":  # mouse:left|right|middle:down|up at the screen centre (in-game buttons)
				var parts := arg.split(":")
				var e := InputEventMouseButton.new()
				e.button_index = {"right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE}.get(parts[0], MOUSE_BUTTON_LEFT)
				e.pressed = parts.size() < 2 or parts[1] == "down"
				e.position = get_viewport().get_visible_rect().size * 0.5
				e.global_position = e.position
				Input.parse_input_event(e)
				Platform.perf_log("UI mouse %s" % arg)
			"back":  # the Android back button's go-back request
				get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
				await get_tree().process_frame
				Platform.perf_log("UI back")
			"shot":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(arg)
				Platform.perf_log("UI shot %s" % arg)
			"key":  # key:NAME taps a key (Escape, Tab, F3...)
				for pressed: bool in [true, false]:
					var k := InputEventKey.new()
					k.keycode = OS.find_keycode_from_string(arg)
					k.physical_keycode = k.keycode
					k.pressed = pressed
					Input.parse_input_event(k)
					await get_tree().process_frame
				Platform.perf_log("UI key %s" % arg)
			"wheel":  # wheel:X:Y:N scrolls N notches (negative: up) at (X, Y)
				var parts := arg.split(":")
				var n := parts[2].to_int()
				for i in absi(n):
					for pressed: bool in [true, false]:
						var e := InputEventMouseButton.new()
						e.button_index = MOUSE_BUTTON_WHEEL_DOWN if n > 0 else MOUSE_BUTTON_WHEEL_UP
						e.pressed = pressed
						e.position = Vector2(parts[0].to_float(), parts[1].to_float())
						e.global_position = e.position
						Input.parse_input_event(e)
						await get_tree().process_frame
				Platform.perf_log("UI wheel %s" % arg)
			"quit":
				Platform.perf_log("UI quit")
				get_tree().quit()


func _find_button(node: Node, label: String) -> Button:
	var b := node as Button
	if b != null and b.is_visible_in_tree() and not b.disabled:
		# Drawn cards (MenuTile) carry their label as the `ui_key` meta.
		for text: String in [b.text, str(b.get_meta("ui_key", ""))]:
			if label.begins_with("~") and tr(text).contains(label.substr(1)) or text == label or tr(text) == label:
				return b
	for child in node.get_children():
		var found := _find_button(child, label)
		if found != null:
			return found
	return null
