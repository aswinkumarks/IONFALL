class_name Nameplates
extends Control
## Other players' names, shield/health bars and team shapes, drawn in 2D
## over the 3D view from each PlayerVisual's nameplate fields. They were
## Label3D and Sprite3D: about four draw calls per player (text, outline,
## bar, team marker), which with 16 players broke the draw budget (m4.md);
## the canvas batches these into a few. Like the 3D ones they shrink with
## distance, fade out past PlayerVisual.NAMEPLATE_RANGE and don't show
## through walls: a line-of-sight ray per player, every SIGHT_SECONDS.

## Text and bar sizes in metres, as the 3D nameplates had (font 40 and a
## 120 x 13 texel bar at 0.005 m per pixel; the team shape 48 at 0.0045).
const TEXT_METRES := 0.2
const BAR_METRES := Vector2(0.6, 0.065)
const SHAPE_METRES := 0.22
const MIN_TEXT := 11
const MAX_TEXT := 30
const FADE_METRES := 4.0
const SIGHT_SECONDS := 0.1
const FADE_PER_SECOND := 8.0

var visuals: Dictionary = {}  ## net id -> PlayerVisual (Match._visuals)
var _sight := {}  ## PlayerVisual -> [in sight, next check (s), shown alpha]
var _lines := {}  ## text -> {size -> TextLine}, shaped once
var _shapes := {}  ## team -> ImageTexture
var _time := 0.0
var _delta := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	_delta = delta
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if _sight.size() > visuals.size() + 8:  # players who left
		for v in _sight.keys():
			if not is_instance_valid(v):
				_sight.erase(v)
	var eye := camera.global_position
	var px_per_metre := get_viewport_rect().size.y / (2.0 * tan(deg_to_rad(camera.fov) * 0.5))
	var shown: Array = []  ## [distance, visual, anchor]
	for v: PlayerVisual in visuals.values():
		if not is_instance_valid(v) or not v.visible or not v.nameplate_shown:
			continue
		var anchor := v.nameplate_anchor()
		var d := eye.distance_to(anchor)
		if d > PlayerVisual.NAMEPLATE_RANGE + FADE_METRES or camera.is_position_behind(anchor):
			_fade(v, false)
			continue
		var alpha := _fade(v, _in_sight(v, camera, anchor, d))
		alpha *= clampf((PlayerVisual.NAMEPLATE_RANGE + FADE_METRES - d) / FADE_METRES, 0.0, 1.0)
		if alpha > 0.01:
			shown.append([d, v, anchor, alpha])
	# Far first, so nearer plates draw over them.
	shown.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for s: Array in shown:
		_draw_plate(s[1], camera.unproject_position(s[2]), px_per_metre / maxf(s[0], 0.5), s[3])


func _draw_plate(v: PlayerVisual, at: Vector2, scale: float, alpha: float) -> void:
	var size := clampi(roundi(TEXT_METRES * scale), MIN_TEXT, MAX_TEXT)
	var k := float(size) / (TEXT_METRES * scale)  ## the clamp's effect, applied to the rest too
	var line := _line(v.nameplate_text, size)
	var text_size := line.get_size()
	var text_at := at - Vector2(text_size.x * 0.5, text_size.y)
	var color := Color(v.nameplate_color, v.nameplate_color.a * alpha)
	line.draw_outline(get_canvas_item(), text_at, maxi(3, size / 4), Color(0, 0, 0, alpha))
	line.draw(get_canvas_item(), text_at, color)
	# The bar under the name: shield while it holds, then health.
	var bar := (BAR_METRES * scale * k).max(Vector2(24.0, 3.0))
	var bar_at := at + Vector2(-bar.x * 0.5, 2.0)
	draw_rect(Rect2(bar_at, bar), Color(0, 0, 0, 0.6 * alpha))
	if v.bar_fraction > 0.0:
		var fill := Rect2(bar_at + Vector2.ONE, Vector2((bar.x - 2.0) * v.bar_fraction, bar.y - 2.0))
		draw_rect(fill, Color(UiStyle.SHIELD if v.bar_on_shield else UiStyle.DANGER, alpha))
	# TDM: the team's shape above the name (never colour alone, PLAN §3.16).
	if v.nameplate_team >= 0 and v.nameplate_team < GameMode.TEAM_SHAPES.size():
		if not _shapes.has(v.nameplate_team):
			_shapes[v.nameplate_team] = UiStyle.team_shape_texture(v.nameplate_team)
		var side := SHAPE_METRES * scale * k
		draw_texture_rect(_shapes[v.nameplate_team], Rect2(at - Vector2(side * 0.5, text_size.y + side + 2.0),
				Vector2(side, side)), false, Color(v.nameplate_color, alpha))


## The shaped text for `text` at `size`, shaped once.
func _line(text: String, size: int) -> TextLine:
	var sizes: Dictionary = _lines.get(text, {})
	if not sizes.has(size):
		var line := TextLine.new()
		line.add_string(text, UiStyle.font_body_bold, size)
		sizes[size] = line
		_lines[text] = sizes
	return sizes[size]


## Whether `v`'s nameplate isn't behind a wall, rechecked every SIGHT_SECONDS
## (staggered by player).
func _in_sight(v: PlayerVisual, camera: Camera3D, anchor: Vector3, d: float) -> bool:
	var s: Array = _sight.get(v, [true, 0.0, 0.0])
	var eye := camera.global_position
	if _time >= s[1]:
		var hit := camera.get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(eye, anchor, Sim.LAYER_WORLD))
		s[0] = hit.is_empty() or eye.distance_to(hit.position) > d - 0.3
		s[1] = _time + SIGHT_SECONDS * (0.75 + 0.5 * float(v.get_instance_id() % 7) / 7.0)
	_sight[v] = s
	return s[0]


## Eases `v`'s shown alpha towards on or off; returns it.
func _fade(v: PlayerVisual, on: bool) -> float:
	var s: Array = _sight.get(v, [true, 0.0, 0.0])
	s[2] = move_toward(s[2], 1.0 if on else 0.0, _delta * FADE_PER_SECOND)
	_sight[v] = s
	return s[2]
