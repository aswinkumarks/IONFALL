class_name MenuKit
extends RefCounted
## Building blocks shared by the menu screens and the lobby: screen headers,
## option chips, section labels, icon buttons and the line icons they draw.

const ICON_WIDTH := 2.5
const CHIP_FONT_SIZE := 21  ## UiStyle "ChipButton"
const CHIP_MAX_MIN_WIDTH := 170.0


## "‹ Back   Title" across the top of a screen; `right` (optional) sits at
## the far end.
static func header(title: String, back_text: String, on_back: Callable, right: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var back := icon_button("back", back_text, on_back)
	back.set_meta("ui_key", back_text)
	row.add_child(back)
	var heading := UiStyle.label(title, &"HeaderLabel")
	heading.add_theme_font_size_override("font_size", 46)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(heading)
	if right != null:
		row.add_child(right)
	return row


## A small dim caption above a group of options.
static func section(text: String) -> Label:
	var l := UiStyle.label(text, &"DimLabel")
	l.uppercase = true
	l.add_theme_font_size_override("font_size", 15)
	return l


## A row of toggle chips, one selected. `on_select(index)`; read-only rows
## show the choice but can't be changed (lobby players).
static func chips(labels: Array, selected: int, on_select: Callable, read_only: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.theme_type_variation = &"ChipButton"
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Wide enough for its label, up to a cap; longer (translated) labels
		# shorten with "…" instead of pushing the layout off screen.
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var label_width := UiStyle.font_display.get_string_size(TranslationServer.translate(labels[i]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_FONT_SIZE).x
		b.custom_minimum_size.x = minf(label_width + 44.0, CHIP_MAX_MIN_WIDTH)
		if read_only:
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.focus_mode = Control.FOCUS_NONE
			b.modulate.a = 1.0 if i == selected else 0.45
		b.pressed.connect(func() -> void: on_select.call(i))
		row.add_child(b)
	return row


## "5 min", "10 min", … for LobbySession.DURATIONS.
static func duration_labels() -> Array:
	return LobbySession.DURATIONS.map(func(m: int) -> String: return TranslationServer.translate("MENU_MINUTES") % m)


## The bot count as shown on steppers: "None" for 0, else the number.
static func bot_label(n: int) -> String:
	return TranslationServer.translate("MENU_BOTS_NONE") if n == 0 else str(n)


## "Easy", "Normal", "Hard", "Insane" for BotBrain.DIFFICULTY_IDS.
static func difficulty_labels() -> Array:
	return BotBrain.DIFFICULTY_IDS.map(func(id: String) -> String: return "SETTING_VALUE_" + id.to_upper())


## Greys out a chip row that doesn't apply (friendly fire outside team modes).
static func set_chips_enabled(row: HBoxContainer, enabled: bool) -> void:
	row.modulate.a = 1.0 if enabled else 0.4
	for b: Button in row.get_children():
		b.disabled = not enabled


## Selects chip `index` in a row from `chips` without emitting.
static func select_chip(row: HBoxContainer, index: int) -> void:
	for i in row.get_child_count():
		var b := row.get_child(i) as Button
		b.set_pressed_no_signal(i == index)
		if b.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			b.modulate.a = 1.0 if i == index else 0.45


## A flat button with a line icon and optional text.
static func icon_button(kind: String, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"GhostButton"
	b.custom_minimum_size = Vector2(52, 52)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not text.is_empty():
		# Room for the icon before the text.
		b.add_theme_constant_override("h_separation", 0)
		b.add_theme_stylebox_override("normal", UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0.0, 52, 10))
		b.add_theme_stylebox_override("hover", UiStyle.box(Color(UiStyle.ACCENT, 0.12), Color.TRANSPARENT, 0, UiStyle.SKEW, 52, 10))
		b.add_theme_stylebox_override("focus", UiStyle.box(Color.TRANSPARENT, Color(UiStyle.ACCENT, 0.8), 1, UiStyle.SKEW, 52, 10))
		# Pressed too: the theme's pressed plate has the usual margin, so the
		# text jumped left onto the icon while held.
		var pressed := UiStyle.box(Color(UiStyle.ACCENT, 0.3), UiStyle.ACCENT, 1, UiStyle.SKEW, 52, 10)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("hover_pressed", pressed)
		b.add_theme_stylebox_override("disabled", UiStyle.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0.0, 52, 10))
	b.draw.connect(func() -> void:
		var c := Color.WHITE if b.is_hovered() or b.has_focus() else UiStyle.TEXT_DIM
		var at := Vector2(26, b.size.y * 0.5) if not text.is_empty() else b.size * 0.5
		draw_icon(b, kind, at, 22, c))
	b.pressed.connect(action)
	return b


## Line icons, drawn at `center`, about `s` across.
static func draw_icon(ci: CanvasItem, kind: String, center: Vector2, s: float, c: Color) -> void:
	var w := maxf(ICON_WIDTH * s / 40.0, 1.6)
	var h := s * 0.5
	match kind:
		"solo":  # crosshair
			ci.draw_arc(center, h * 0.72, 0, TAU, 40, c, w, true)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(center + d * h * 0.35, center + d * h, c, w, true)
			ci.draw_circle(center, w * 0.9, c)
		"host":  # a beacon broadcasting
			ci.draw_circle(center + Vector2(0, h * 0.1), w * 1.6, c)
			for k in [0.45, 0.85]:
				ci.draw_arc(center + Vector2(0, h * 0.1), h * k, -PI * 0.8, -PI * 0.2, 16, c, w, true)
			ci.draw_line(center + Vector2(0, h * 0.1), center + Vector2(0, h), c, w, true)
		"join":  # arrow into a bracket
			ci.draw_line(center + Vector2(-h, 0), center + Vector2(h * 0.25, 0), c, w, true)
			ci.draw_polyline(PackedVector2Array([center + Vector2(-h * 0.15, -h * 0.4), center + Vector2(h * 0.25, 0),
					center + Vector2(-h * 0.15, h * 0.4)]), c, w, true)
			ci.draw_polyline(PackedVector2Array([center + Vector2(h * 0.35, -h), center + Vector2(h, -h),
					center + Vector2(h, h), center + Vector2(h * 0.35, h)]), c, w, true)
		"lan":  # three linked nodes
			var a := center + Vector2(0, -h * 0.7)
			var b := center + Vector2(-h * 0.8, h * 0.6)
			var d := center + Vector2(h * 0.8, h * 0.6)
			ci.draw_polyline(PackedVector2Array([a, b, d, a]), c, w, true)
			for p: Vector2 in [a, b, d]:
				ci.draw_circle(p, w * 2.0, c)
		"online":  # globe
			ci.draw_arc(center, h * 0.9, 0, TAU, 40, c, w, true)
			ci.draw_line(center + Vector2(-h * 0.9, 0), center + Vector2(h * 0.9, 0), c, w, true)
			var pts := PackedVector2Array()
			for i in 33:
				var t := TAU * i / 32.0
				pts.append(center + Vector2(cos(t) * h * 0.4, sin(t) * h * 0.9))
			ci.draw_polyline(pts, c, w, true)
		"gear":
			ci.draw_arc(center, h * 0.42, 0, TAU, 32, c, w, true)
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0)
				ci.draw_line(center + d * h * 0.62, center + d * h * 0.92, c, w * 1.6, true)
			ci.draw_arc(center, h * 0.66, 0, TAU, 32, c, w, true)
		"power":
			ci.draw_arc(center, h * 0.75, -PI * 0.5 + 0.6, PI * 1.5 - 0.6, 32, c, w, true)
			ci.draw_line(center + Vector2(0, -h * 0.95), center + Vector2(0, -h * 0.15), c, w, true)
		"back":
			ci.draw_polyline(PackedVector2Array([center + Vector2(h * 0.25, -h * 0.6), center + Vector2(-h * 0.35, 0),
					center + Vector2(h * 0.25, h * 0.6)]), c, w * 1.2, true)
		"check":
			ci.draw_circle(center, h, c)
			ci.draw_polyline(PackedVector2Array([center + Vector2(-h * 0.45, 0), center + Vector2(-h * 0.1, h * 0.35),
					center + Vector2(h * 0.5, -h * 0.35)]), UiStyle.BG, w * 1.3, true)
		"user":
			ci.draw_arc(center + Vector2(0, -h * 0.3), h * 0.38, 0, TAU, 28, c, w, true)
			ci.draw_arc(center + Vector2(0, h * 0.95), h * 0.75, -PI * 0.92, -PI * 0.08, 24, c, w, true)
