class_name MenuTile
extends Button
## A large menu card: optional picture, a drawn icon, title and subtitle.
## Hovering or focusing lifts it and lights its edge; `selected` keeps it lit
## (map choices). Drawn in code (MenuKit icons, UiStyle palette). The title
## key is also the node's `ui_key` meta, so the dev `--ui` driver can click it.

var title: String = ""
var subtitle: String = ""
var icon_kind: String = ""  ## MenuKit.draw_icon kind, "" for none
var image: Texture2D
var accent: Color = UiStyle.ACCENT
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()
## Read-only (lobby players): shown, but not clickable.
var read_only: bool = false:
	set(v):
		read_only = v
		mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE if v else Control.FOCUS_ALL
		queue_redraw()
var _hover: float = 0.0
var _tween: Tween


static func make(p_title: String, p_subtitle: String, p_icon: String = "", p_image: Texture2D = null) -> MenuTile:
	var t := MenuTile.new()
	t.title = p_title
	t.subtitle = p_subtitle
	t.icon_kind = p_icon
	t.image = p_image
	t.set_meta("ui_key", p_title)
	return t


func _ready() -> void:
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	clip_contents = false
	mouse_entered.connect(_lift.bind(true))
	mouse_exited.connect(_lift.bind(false))
	focus_entered.connect(_lift.bind(true))
	focus_exited.connect(_lift.bind(false))
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	pivot_offset = size * 0.5


func _lift(on: bool) -> void:
	if not on and (is_hovered() or has_focus()):
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(func(v: float) -> void:
		_hover = v
		scale = Vector2.ONE * (1.0 + 0.025 * v)
		queue_redraw(), _hover, 1.0 if on else 0.0, 0.18)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var lit := maxf(_hover, 1.0 if selected else 0.0)
	var dim := 0.45 if disabled or (read_only and not selected) else 1.0
	draw_rect(r, Color(0.035, 0.06, 0.1, 0.86))
	if image != null:
		# Cover the card, keeping the picture's aspect.
		var ts := image.get_size()
		var scale_by := maxf(size.x / ts.x, size.y / ts.y)
		var src := Rect2((ts - size / scale_by) * 0.5, size / scale_by)
		draw_texture_rect_region(image, r, src, Color(1, 1, 1, (0.55 + 0.4 * lit) * dim))
	# Darken towards the bottom for the text.
	var top := Color(UiStyle.BG, 0.05)
	var bottom := Color(UiStyle.BG, 0.92)
	draw_polygon(PackedVector2Array([Vector2(0, size.y * 0.3), Vector2(size.x, size.y * 0.3), size, Vector2(0, size.y)]),
			PackedColorArray([top, top, bottom, bottom]))
	# Accent: a glow line that grows along the bottom, and the outline.
	draw_rect(r, Color(accent, (0.16 + 0.7 * lit) * dim), false, 2.0 if lit > 0.5 else 1.0)
	draw_rect(Rect2(0, size.y - 4, size.x * (0.18 + 0.82 * lit), 4), Color(accent, (0.6 + 0.4 * lit) * dim))
	if selected:
		MenuKit.draw_icon(self, "check", Vector2(size.x - 26, 26), 26, accent)
	var big := size.y > 120
	# Text-only cards get their icon again, large and faint, on the right.
	if image == null and size.y >= 200 and not icon_kind.is_empty():
		MenuKit.draw_icon(self, icon_kind, Vector2(size.x - size.y * 0.42, size.y * 0.42), size.y * 0.62,
				Color(accent, (0.07 + 0.1 * lit) * dim))
	var pad := 22.0 if big else 16.0
	# Compact cards (game rows): icon on the left, text beside it.
	var icon_size := 48.0 if big else 30.0
	var text_x := pad if big or icon_kind.is_empty() else pad + icon_size + 14.0
	var y := size.y - pad
	var width := size.x - text_x - pad
	if not subtitle.is_empty():
		var sub := tr(subtitle)
		var preferred := 17 if big else 15
		var sub_size := _fit(UiStyle.font_body, sub, width, preferred)
		var sub_color := Color(UiStyle.TEXT_DIM.lerp(UiStyle.TEXT, lit * 0.5), dim)
		if UiStyle.font_body.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x > width:
			# Too long for one line even when smaller (narrow cards): two lines.
			sub_size = roundi(preferred * 0.85)
			var line := UiStyle.font_body.get_height(sub_size)
			draw_multiline_string(UiStyle.font_body, Vector2(text_x, y - line), sub, HORIZONTAL_ALIGNMENT_LEFT,
					width, sub_size, 2, sub_color, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_MANDATORY)
			y -= line
		else:
			draw_string(UiStyle.font_body, Vector2(text_x, y), sub, HORIZONTAL_ALIGNMENT_LEFT, width, sub_size, sub_color)
		y -= sub_size + 10
	var title_size := _fit(UiStyle.font_display_bold, tr(title), width, (34 if size.y >= 200 else 30) if big else 26)
	draw_string(UiStyle.font_display_bold, Vector2(text_x, y), tr(title), HORIZONTAL_ALIGNMENT_LEFT,
			width, title_size, Color(UiStyle.TEXT, dim))
	if not icon_kind.is_empty():
		var at := Vector2(pad + icon_size * 0.5, pad + icon_size * 0.5) if big \
				else Vector2(pad + icon_size * 0.5, size.y * 0.5)
		MenuKit.draw_icon(self, icon_kind, at, icon_size, Color(accent.lerp(Color.WHITE, lit * 0.4), dim))


## The largest font size up to `preferred` (down to 70% of it) at which
## `text` fits `width`; longer (translated) text then clips at that size.
static func _fit(font: Font, text: String, width: float, preferred: int) -> int:
	var fs := preferred
	while fs > roundi(preferred * 0.7) and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	return fs
