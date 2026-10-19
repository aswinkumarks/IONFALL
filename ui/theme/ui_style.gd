extends Node
## IONFALL's look (autoload `UiStyle`): palette, fonts and the project-wide
## Theme applied to the root window, so every Control inherits it. Built in
## code so colours and shapes live in one place. Also gives every Button a
## hover tick and a press click (UI bus).
##
## Theme type variations for special cases: "TitleLabel", "HeaderLabel",
## "DimLabel", "BadgeLabel", "PrimaryButton", "GhostButton", "CardPanel",
## "HudPanel".

# --- Palette ---
const BG := Color("070b12")
const PANEL := Color(0.04, 0.07, 0.11, 0.9)
const PANEL_LIGHT := Color(0.08, 0.12, 0.18, 0.92)
const LINE := Color(0.31, 0.89, 1.0, 0.22)
const ACCENT := Color("4fe3ff")
const ACCENT_DEEP := Color("1b8fb0")
const WARN := Color("ff9a3c")
const DANGER := Color("ff4d5e")
const GOOD := Color("5cf2a0")
const TEXT := Color("e6f1fa")
const TEXT_DIM := Color("8aa0b4")
const SHIELD := Color("4fe3ff")
const HEALTH := Color("f2f6fa")

const SKEW := 0.18  ## parallelogram slant of buttons and tabs

var font_body: FontVariation
var font_body_bold: FontVariation
var font_display: Font  ## Rajdhani SemiBold: headings, numbers, buttons
var font_display_bold: Font
var theme: Theme

var _hover_player: AudioStreamPlayer
var _click_player: AudioStreamPlayer


func _ready() -> void:
	if Platform.is_dedicated_server():
		return
	font_body = _variable(500)
	font_body_bold = _variable(700)
	font_display = load("res://ui/fonts/Rajdhani-SemiBold.ttf")
	font_display_bold = load("res://ui/fonts/Rajdhani-Bold.ttf")
	theme = build()
	get_tree().root.theme = theme
	_hover_player = _ui_player(-14.0)
	_click_player = _ui_player(-6.0)
	get_tree().node_added.connect(_on_node_added)


func _variable(weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load("res://ui/fonts/Exo2-Variable.ttf")
	f.variation_opentype = {"wght": weight}
	return f


# --- Style boxes ---

static func box(bg: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, skew: float = 0.0,
		margin_h: float = 16.0, margin_v: float = 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.skew = Vector2(skew, 0.0)
	s.corner_detail = 1
	s.anti_aliasing = true
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s


## Panel with a thin outline and a brighter accent edge on the left.
static func panel(bg: Color = PANEL, accent: Color = ACCENT, margin: float = 20.0) -> StyleBoxFlat:
	var s := box(bg, LINE, 1, 0.0, margin, margin)
	s.border_width_left = 3
	s.border_color = Color(accent, 0.5)
	s.set_corner_radius_all(2)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 12
	return s


## Full-screen overlay for in-game menus: dims the game, darkest on the
## left where a menu column sits. Returns the overlay and the column
## (a VBoxContainer to fill).
static func menu_overlay(column_width: float = 440.0) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(BG, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.8])
	g.colors = PackedColorArray([Color(BG, 0.95), Color(BG, 0.7), Color(BG, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 4
	tex.fill_to = Vector2(1, 0)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 72 if side == "left" else 40)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = column_width
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	return [root, column]


## A menu button; `kind` "" (default), "PrimaryButton" or "GhostButton".
static func menu_button(text: String, kind: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = kind
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 58 if kind == &"PrimaryButton" else 50)
	return b


static func label(text: String, variation: StringName = &"", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.horizontal_alignment = align
	return l


func build() -> Theme:
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 20

	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))
	_variation(t, "TitleLabel", "Label")
	t.set_font("font", "TitleLabel", font_display_bold)
	t.set_font_size("font_size", "TitleLabel", 96)
	t.set_color("font_color", "TitleLabel", TEXT)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 4)
	_variation(t, "BadgeLabel", "Label")
	t.set_font("font", "BadgeLabel", font_display_bold)
	t.set_font_size("font_size", "BadgeLabel", 34)
	t.set_color("font_color", "BadgeLabel", BG)
	t.set_stylebox("normal", "BadgeLabel", box(ACCENT, Color.WHITE, 0, SKEW, 10, 2))
	_variation(t, "HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", font_display_bold)
	t.set_font_size("font_size", "HeaderLabel", 40)
	t.set_color("font_color", "HeaderLabel", TEXT)
	_variation(t, "DimLabel", "Label")
	t.set_color("font_color", "DimLabel", TEXT_DIM)
	t.set_font_size("font_size", "DimLabel", 17)

	# Buttons: skewed dark plates; hover lights the edge, press fills.
	var normal := box(Color(0.06, 0.1, 0.15, 0.85), Color(ACCENT, 0.18), 1, SKEW, 22, 10)
	var hover := box(Color(0.09, 0.17, 0.24, 0.95), Color(ACCENT, 0.85), 1, SKEW, 22, 10)
	hover.border_width_left = 4
	var pressed := box(Color(ACCENT, 0.3), ACCENT, 1, SKEW, 22, 10)
	var disabled := box(Color(0.05, 0.07, 0.1, 0.5), Color(1, 1, 1, 0.06), 1, SKEW, 22, 10)
	var focus := box(Color.TRANSPARENT, Color(ACCENT, 0.9), 2, SKEW, 22, 10)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_font("font", type, font_display)
		t.set_font_size("font_size", type, 24)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(TEXT_DIM, 0.5))
	_variation(t, "PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(Color(ACCENT, 0.9), ACCENT, 1, SKEW, 26, 12))
	var p_hover := box(Color(0.55, 0.95, 1.0), Color.WHITE, 1, SKEW, 26, 12)
	t.set_stylebox("hover", "PrimaryButton", p_hover)
	t.set_stylebox("pressed", "PrimaryButton", box(Color(ACCENT_DEEP), ACCENT, 1, SKEW, 26, 12))
	t.set_stylebox("hover_pressed", "PrimaryButton", box(Color(ACCENT_DEEP), ACCENT, 1, SKEW, 26, 12))
	t.set_stylebox("focus", "PrimaryButton", box(Color.TRANSPARENT, Color.WHITE, 2, SKEW, 26, 12))
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "PrimaryButton", BG)
	t.set_color("font_pressed_color", "PrimaryButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "PrimaryButton", Color.WHITE)
	t.set_font("font", "PrimaryButton", font_display_bold)
	t.set_font_size("font_size", "PrimaryButton", 28)
	_variation(t, "GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, SKEW, 22, 10))
	t.set_color("font_color", "GhostButton", TEXT_DIM)

	# Panels
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	_variation(t, "CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", panel(PANEL_LIGHT, ACCENT, 16))
	_variation(t, "HudPanel", "PanelContainer")
	var hud := box(Color(0.02, 0.04, 0.07, 0.55), Color(ACCENT, 0.15), 1, SKEW, 14, 6)
	t.set_stylebox("panel", "HudPanel", hud)

	# Line edit
	var edit := box(Color(0.02, 0.04, 0.07, 0.8), Color(ACCENT, 0.25), 1, 0.0, 14, 8)
	edit.border_width_bottom = 2
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = ACCENT
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_stylebox("read_only", "LineEdit", edit)
	t.set_font("font", "LineEdit", font_display)
	t.set_font_size("font_size", "LineEdit", 24)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))

	# Tabs
	var tab := box(Color(0.05, 0.08, 0.12, 0.8), Color(ACCENT, 0.12), 1, SKEW, 20, 8)
	var tab_sel := box(Color(0.1, 0.18, 0.26, 0.95), ACCENT, 0, SKEW, 20, 8)
	tab_sel.border_width_bottom = 3
	var tab_hover := box(Color(0.08, 0.14, 0.2, 0.9), Color(ACCENT, 0.5), 1, SKEW, 20, 8)
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_hovered", "TabContainer", tab_hover)
	t.set_stylebox("tab_focus", "TabContainer", box(Color.TRANSPARENT, ACCENT, 1, SKEW))
	t.set_stylebox("panel", "TabContainer", panel(PANEL, ACCENT, 24))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_font("font", "TabContainer", font_display)
	t.set_font_size("font_size", "TabContainer", 24)
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_constant("side_margin", "TabContainer", 6)

	# Sliders
	var track := box(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 0, 0.0, 0, 3)
	var fill := box(Color(ACCENT, 0.85), Color.TRANSPARENT, 0, 0.0, 0, 3)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _diamond(22, ACCENT))
	t.set_icon("grabber_highlight", "HSlider", _diamond(26, Color.WHITE))
	t.set_icon("grabber_disabled", "HSlider", _diamond(22, TEXT_DIM))

	# Toggles (CheckButton / CheckBox)
	var on := _switch(true)
	var off := _switch(false)
	for type in ["CheckButton", "CheckBox"]:
		t.set_icon("checked" if type == "CheckBox" else "checked", type, on)
		t.set_icon("unchecked", type, off)
		t.set_icon("checked_disabled", type, on)
		t.set_icon("unchecked_disabled", type, off)
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			t.set_stylebox(s, type, box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0.0, 4, 4))
	t.set_stylebox("focus", "CheckButton", box(Color.TRANSPARENT, Color(ACCENT, 0.7), 1, 0.0, 4, 4))

	# Popups, lists, scrollbars, tooltips, progress
	t.set_stylebox("panel", "PopupMenu", panel(Color(0.04, 0.07, 0.11, 0.98), ACCENT, 8))
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.25)))
	t.set_font("font", "PopupMenu", font_display)
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "ItemList", box(Color(0.02, 0.04, 0.07, 0.6), Color(ACCENT, 0.15), 1, 0.0, 6, 6))
	t.set_stylebox("selected", "ItemList", box(Color(ACCENT, 0.25)))
	t.set_stylebox("selected_focus", "ItemList", box(Color(ACCENT, 0.35)))
	t.set_stylebox("hovered", "ItemList", box(Color(ACCENT, 0.12)))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(Color(1, 1, 1, 0.04), Color.TRANSPARENT, 0, 0.0, 3, 3))
		t.set_stylebox("grabber", bar, box(Color(ACCENT, 0.35), Color.TRANSPARENT, 0, 0.0, 3, 3))
		t.set_stylebox("grabber_highlight", bar, box(Color(ACCENT, 0.6), Color.TRANSPARENT, 0, 0.0, 3, 3))
		t.set_stylebox("grabber_pressed", bar, box(ACCENT, Color.TRANSPARENT, 0, 0.0, 3, 3))
	t.set_stylebox("panel", "TooltipPanel", panel(Color(0.04, 0.07, 0.11, 0.97), ACCENT, 8))
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 0, SKEW, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color.TRANSPARENT, 0, SKEW, 0, 0))
	t.set_font("font", "ProgressBar", font_display)
	return t


static func _variation(t: Theme, name: StringName, base: StringName) -> void:
	t.add_type(name)
	t.set_type_variation(name, base)


## Diamond slider grabber.
static func _diamond(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := absf(x - c) + absf(y - c)
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			var inner := clampf(c * 0.45 - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.lerp(BG, inner * 0.8), a))
	return ImageTexture.create_from_image(img)


## Pill toggle, 52 × 26: accent with the knob right when on.
static func _switch(on: bool) -> ImageTexture:
	var w := 52
	var h := 26
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5
	var track := Color(ACCENT, 0.85) if on else Color(1, 1, 1, 0.12)
	var knob_x := w - r if on else r
	for y in h:
		for x in w:
			var cx := clampf(x + 0.5, r, w - r)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			var col := track
			var kd := Vector2(x + 0.5 - knob_x, y + 0.5 - r).length()
			var ka := clampf(r - 4.0 - kd, 0.0, 1.0)
			col = col.lerp(Color.WHITE if on else TEXT_DIM, ka)
			img.set_pixel(x, y, Color(col, a * maxf(col.a, ka)))
	return ImageTexture.create_from_image(img)


# --- Button sounds ---

func _ui_player(volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	p.volume_db = volume
	add_child(p)
	return p


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("silent"):
		var b := node as BaseButton
		b.mouse_entered.connect(_hover_sound.bind(b))
		b.pressed.connect(_click_sound)


func _hover_sound(b: BaseButton) -> void:
	if not b.disabled and b.is_visible_in_tree():
		_play(_hover_player, "res://audio/generated/switch.wav", 1.6)


func _click_sound() -> void:
	_play(_click_player, "res://audio/generated/ui_click.wav", 1.0)


func _play(p: AudioStreamPlayer, path: String, pitch: float) -> void:
	if p.stream == null:
		p.stream = load(path)
	if p.bus != "UI" and AudioServer.get_bus_index("UI") >= 0:
		p.bus = "UI"
	p.pitch_scale = pitch
	p.play()
