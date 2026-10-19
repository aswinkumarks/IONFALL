extends Node
## Diagnostics service: frame statistics and the debug overlay (PLAN §3.15).
##
## Toggle the overlay with F3 on desktop or a three-finger tap on touch.

const OVERLAY_SCENE := preload("res://ui/diagnostics/diagnostics_overlay.tscn")

var frame_stats := FrameStats.new(600)
## Set by the active match: func() -> String with network rows for the overlay.
var net_info: Callable
var _overlay: CanvasLayer
var _touches: Dictionary = {}


func _ready() -> void:
	if Platform.is_dedicated_server():
		set_process(false)
		set_process_input(false)
		return
	_overlay = OVERLAY_SCENE.instantiate()
	_overlay.visible = false
	add_child(_overlay)


func _process(delta: float) -> void:
	frame_stats.add(delta * 1000.0)


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
