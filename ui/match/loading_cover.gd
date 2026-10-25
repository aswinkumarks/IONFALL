class_name LoadingCover
extends CanvasLayer
## The loading screen over a match while it loads and warms up: the map's
## art, its name and mode, a progress bar, a spinner and a tip. Menus put it
## up before switching to the match scene and the match takes it over, so
## the screen shows it, not a frozen menu, while the map loads (that frame
## can take seconds when the driver's shader cache is cold).

const NAME := &"LoadingCover"
const TIPS := ["TIP_SLIDE", "TIP_DOUBLE_JUMP", "TIP_MANTLE", "TIP_PADS", "TIP_SCOPE", "TIP_POWER",
		"TIP_GRENADE", "TIP_CTF", "TIP_BOTS"]
const TIP_SECONDS := 6.0
## The bar's part for loading files before the match (the rest is its warm-up).
const PRELOAD_SHARE := 0.3

var _art := TextureRect.new()
var _deco := _Deco.new()
var _mode := UiStyle.label("")
var _map := UiStyle.label("", &"HeaderLabel")
var _blurb := UiStyle.label("", &"DimLabel")
var _status := UiStyle.label("LOADING_MAP", &"DimLabel")
var _percent := UiStyle.label("0%", &"HeaderLabel", HORIZONTAL_ALIGNMENT_RIGHT)
var _tip := UiStyle.label("", &"", HORIZONTAL_ALIGNMENT_RIGHT)
var _target: float = 0.0
var _shown: float = 0.0
var _time: float = 0.0
var _tip_index: int = 0
var _stage := Vector2(0.0, 1.0)


func _init() -> void:
	name = NAME
	layer = 100
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind takes input while loading
	add_child(root)
	var bg := ColorRect.new()
	bg.color = UiStyle.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.modulate = Color(0.62, 0.68, 0.75)
	root.add_child(_art)
	root.add_child(_shade(Vector2(0, 0), Vector2(0, 1), [0.0, 0.45, 1.0], [0.25, 0.35, 0.97]))  # top to bottom
	root.add_child(_shade(Vector2(0, 0), Vector2(1, 0), [0.0, 0.6], [0.75, 0.0]))  # left to right
	_deco.cover = self
	_deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_deco)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 92)  # the progress bar sits below
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var brand := UiStyle.label("MENU_TITLE", &"DimLabel")
	brand.add_theme_font_override("font", UiStyle.font_display_bold)
	brand.add_theme_font_size_override("font_size", 26)
	brand.add_theme_color_override("font_color", UiStyle.ACCENT)
	column.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var badge := PanelContainer.new()
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.ACCENT, UiStyle.ACCENT, 0, UiStyle.SKEW, 14, 2))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode.add_theme_font_override("font", UiStyle.font_display_bold)
	_mode.add_theme_font_size_override("font_size", 24)
	_mode.add_theme_color_override("font_color", UiStyle.BG)
	badge.add_child(_mode)
	column.add_child(badge)
	_map.add_theme_font_size_override("font_size", 72)
	column.add_child(_map)
	column.add_child(_blurb)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	column.add_child(gap)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 24)
	column.add_child(bottom)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_END
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	_tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip.size_flags_stretch_ratio = 1.6
	_tip.size_flags_vertical = Control.SIZE_SHRINK_END
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.add_theme_color_override("font_color", Color(UiStyle.TEXT, 0.85))
	bottom.add_child(_tip)
	_percent.add_theme_font_size_override("font_size", 30)
	_percent.add_theme_color_override("font_color", UiStyle.ACCENT)
	_percent.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_percent.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_percent.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_percent.offset_right = -144
	_percent.offset_bottom = -50
	root.add_child(_percent)
	_tip_index = randi() % TIPS.size()
	_show_tip()
	if MatchConfig.pending != null:
		show_config(MatchConfig.pending)


## The map and mode being loaded.
func show_config(config: MatchConfig) -> void:
	var info: Dictionary = Maps.LIST.get(config.map, {})
	_map.text = tr(info.get("name", config.map)).to_upper()
	_blurb.text = tr(info.get("blurb", ""))
	_blurb.visible = not _blurb.text.is_empty()
	_mode.text = tr(GameMode.NAME_KEYS[clampi(config.game_mode, 0, GameMode.NAME_KEYS.size() - 1)]).to_upper()
	var thumb: String = info.get("thumb", "")
	_art.texture = load(thumb) if not thumb.is_empty() and ResourceLoader.exists(thumb) else null


## `set_progress` fractions from here on fill the bar from `from` to `to`.
func stage(from: float, to: float) -> void:
	_stage = Vector2(from, to)


func set_progress(fraction: float) -> void:
	_target = maxf(_target, lerpf(_stage.x, _stage.y, clampf(fraction, 0.0, 1.0)))


## A first draw is slow on this device (a cold shader cache): say why.
func show_slow_note() -> void:
	_status.text = tr("LOADING_FIRST_RUN")


func _process(delta: float) -> void:
	_time += delta
	# Ease towards the target, never quite resting short of it.
	_shown = minf(_target, _shown + maxf((_target - _shown) * delta * 6.0, delta * 0.05))
	_percent.text = "%d%%" % floori(_shown * 100.0)
	# A slow push-in on the map art.
	var s := 1.0 + 0.04 * sin(_time * 0.12)
	_art.pivot_offset = _art.size * 0.5
	_art.scale = Vector2(s, s)
	if fmod(_time, TIP_SECONDS) < delta:
		_tip_index = (_tip_index + 1) % TIPS.size()
		_show_tip()
	_deco.queue_redraw()


func _show_tip() -> void:
	_tip.text = "%s  ·  %s" % [tr("LOADING_TIP"), tr(TIPS[_tip_index])]


static func _shade(from: Vector2, to: Vector2, offsets: Array, alphas: Array) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	var colors := PackedColorArray()
	for a: float in alphas:
		colors.append(Color(UiStyle.BG, a))
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4 if from.x == to.x else 256
	tex.height = 256 if from.x == to.x else 4
	tex.fill_from = from
	tex.fill_to = to
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Shows the cover, lets it reach the screen, loads the match's meshes
## (MatchPreload; the menu's 3D stops drawing meanwhile), then switches to
## `scene`.
static func change_scene(tree: SceneTree, scene: String) -> void:
	var cover := tree.root.get_node_or_null(NodePath(NAME)) as LoadingCover
	if cover == null:
		cover = LoadingCover.new()
		tree.root.add_child(cover)
	await tree.process_frame
	tree.root.disable_3d = true
	await tree.process_frame
	var map_id: String = MatchConfig.pending.map if MatchConfig.pending != null else ""
	cover.stage(0.0, PRELOAD_SHARE)
	await MatchPreload.run(tree, MatchPreload.paths(map_id), cover.set_progress)
	cover.stage(PRELOAD_SHARE, 1.0)
	tree.root.disable_3d = false
	tree.change_scene_to_file(scene)


## The cover a menu put up, moved under `owner` (freed with it), or a new one.
static func take(owner: Node, config: MatchConfig) -> LoadingCover:
	var cover := owner.get_tree().root.get_node_or_null(NodePath(NAME)) as LoadingCover
	if cover == null:
		cover = LoadingCover.new()
		owner.add_child(cover)
	else:
		cover.reparent(owner)
		cover.stage(PRELOAD_SHARE, 1.0)
	cover.show_config(config)
	return cover


## The drawn parts: corner brackets, a sweeping scan line, the spinner and
## the progress bar.
class _Deco extends Control:
	var cover: LoadingCover

	func _draw() -> void:
		var accent := UiStyle.ACCENT
		var m := 28.0
		var arm := 34.0
		for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var p := Vector2(lerpf(m, size.x - m, corner.x), lerpf(m, size.y - m, corner.y))
			var dx := arm if corner.x == 0 else -arm
			var dy := arm if corner.y == 0 else -arm
			draw_polyline(PackedVector2Array([p + Vector2(dx, 0), p, p + Vector2(0, dy)]), Color(accent, 0.5), 2.0)
		# Scan line drifting down the art.
		var y := fmod(cover._time * 70.0, size.y)
		draw_rect(Rect2(0, y, size.x, 2), Color(accent, 0.06))
		# Progress bar: a slanted track and fill along the bottom.
		var bar := Rect2(72, size.y - 64, size.x - 144 - 170, 10)
		var skew := 6.0
		draw_colored_polygon(_slant(bar, skew), Color(accent, 0.12))
		var fill := Rect2(bar.position, Vector2(bar.size.x * cover._shown, bar.size.y))
		if fill.size.x > 1.0:
			draw_colored_polygon(_slant(fill, skew), Color(accent, 0.9))
			# A bright head that pulses.
			var head := Rect2(fill.end.x - 14, bar.position.y - 3, 14, bar.size.y + 6)
			draw_colored_polygon(_slant(head, skew), Color(1, 1, 1, 0.55 + 0.35 * sin(cover._time * 8.0)))
		# Segment ticks over the track.
		for i in range(1, 20):
			var x := bar.position.x + bar.size.x * i / 20.0
			draw_line(Vector2(x, bar.position.y), Vector2(x - skew, bar.end.y), Color(UiStyle.BG, 0.6), 2.0)
		# Spinner: three arcs turning at different speeds, right of the bar.
		var c := Vector2(size.x - 72 - 26, size.y - 59)
		for i in 3:
			var r := 12.0 + i * 7.0
			var a := cover._time * (3.2 - i * 1.1) * (1.0 if i % 2 == 0 else -1.0)
			draw_arc(c, r, a, a + PI * (0.9 - i * 0.2), 24, Color(accent, 0.9 - i * 0.25), 3.0, true)

	static func _slant(r: Rect2, skew: float) -> PackedVector2Array:
		return PackedVector2Array([r.position + Vector2(skew, 0), Vector2(r.end.x + skew, r.position.y),
				Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)])
