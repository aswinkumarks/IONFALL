class_name KillFeed
extends VBoxContainer
## Server-authored kill feed (PLAN §2.6): at most 5 rows, each expires after
## 6 s. Killer, weapon, victim, plus headshot and assist markers; bots are
## tagged; rows involving the local player are highlighted.

const MAX_ROWS := 5
const ROW_SECONDS := 6.0
## Short weapon tags (translation keys) for the feed, HUD slots and timers.
const WEAPON_TAGS := {&"pulse_rifle": "TAG_PULSE", &"mag_pistol": "TAG_PISTOL", &"arc_launcher": "TAG_ARC",
		&"burst_rifle": "TAG_BURST", &"rail_sniper": "TAG_RAIL", &"scatter_gun": "TAG_SCATTER", &"frag_grenade": "TAG_FRAG",
		&"melee": "TAG_MELEE", &"flux_smg": "TAG_SMG", &"": "TAG_FALL"}


## The translated short tag of weapon `id` (its id in capitals if unknown).
static func weapon_tag(id: StringName) -> String:
	return TranslationServer.translate(WEAPON_TAGS[id]) if WEAPON_TAGS.has(id) else String(id).to_upper()


## Rows are built once and reused, oldest first: building a row's controls
## cost ~3 ms on a laptop and ~15 ms on the Mi 11X per kill (m4.md).
var _rows: Array[PanelContainer] = []
var _involved_box: StyleBoxFlat
var _scale: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 5)
	_involved_box = UiStyle.box(Color(UiStyle.ACCENT, 0.22), Color(UiStyle.ACCENT, 0.7), 1, UiStyle.SKEW, 14, 6)
	for i in MAX_ROWS:
		var row := PanelContainer.new()
		row.theme_type_variation = &"HudPanel"
		row.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.visible = false
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		for part in 4:  # killer, weapon tag, victim, assists
			var l := Label.new()
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.add_theme_font_override("font", UiStyle.font_display if part == 1 else UiStyle.font_body_bold)
			line.add_child(l)
		row.set_meta("ttl", 0.0)
		add_child(row)
		_rows.append(row)


## `name_of`: func(id) -> String (bots already tagged).
func add_death(e: Dictionary, name_of: Callable, local_id: int) -> void:
	_apply_scale(float(Settings.get_value("accessibility", "hud_scale")))
	var row: PanelContainer = get_child(0)  # the oldest (or an unused one)
	for r: PanelContainer in _rows:
		if not r.visible:
			row = r
			break
	var parts := row.get_child(0).get_children()
	var involved: bool = e.killer == local_id or e.victim == local_id
	if involved:
		row.add_theme_stylebox_override("panel", _involved_box)
	else:
		row.remove_theme_stylebox_override("panel")
	var weapon: String = weapon_tag(e.weapon)
	if e.get("environment", false):
		weapon = "FALL"
	var headshot: bool = e.get("headshot", false)
	_set_part(parts[0], "" if e.suicide else name_of.call(e.killer), _name_color(e.killer, local_id))
	_set_part(parts[1], weapon + ("  ◎" if headshot else ""), UiStyle.WARN if headshot else UiStyle.TEXT_DIM)
	_set_part(parts[2], name_of.call(e.victim), _name_color(e.victim, local_id))
	var assists: Array = e.get("assists", [])
	_set_part(parts[3], "" if e.suicide or assists.is_empty() else
			"+ " + ", ".join(assists.map(func(id: int) -> String: return name_of.call(id))), UiStyle.TEXT_DIM)
	row.set_meta("ttl", ROW_SECONDS)
	row.modulate.a = 1.0
	row.visible = true
	move_child(row, -1)


## A mode line (CTF flag takes and captures, co-op waves): `who` in its
## colour, then `what`; highlighted when it concerns us.
func add_note(who: String, what: String, color: Color, involved: bool = false) -> void:
	_apply_scale(float(Settings.get_value("accessibility", "hud_scale")))
	var row: PanelContainer = get_child(0)
	for r: PanelContainer in _rows:
		if not r.visible:
			row = r
			break
	if involved:
		row.add_theme_stylebox_override("panel", _involved_box)
	else:
		row.remove_theme_stylebox_override("panel")
	var parts := row.get_child(0).get_children()
	_set_part(parts[0], who, color)
	_set_part(parts[1], what, UiStyle.TEXT)
	_set_part(parts[2], "", UiStyle.TEXT)
	_set_part(parts[3], "", UiStyle.TEXT_DIM)
	row.set_meta("ttl", ROW_SECONDS)
	row.modulate.a = 1.0
	row.visible = true
	move_child(row, -1)


## Hides every row (e.g. after the loading-screen warm-up).
func clear() -> void:
	for row in _rows:
		row.visible = false


func _set_part(l: Label, text: String, color: Color) -> void:
	l.text = text
	l.visible = not text.is_empty()
	l.add_theme_color_override("font_color", color)


func _apply_scale(scale: float) -> void:
	if is_equal_approx(scale, _scale):
		return
	_scale = scale
	for row in _rows:
		var parts := row.get_child(0).get_children()
		var sizes := [18.0, 20.0 * 0.85, 18.0, 18.0 * 0.8]
		for i in parts.size():
			(parts[i] as Label).add_theme_font_size_override("font_size", roundi(sizes[i] * scale))


func _name_color(id: int, local_id: int) -> Color:
	return UiStyle.ACCENT if id == local_id else UiStyle.TEXT


func _process(delta: float) -> void:
	for row in _rows:
		if not row.visible:
			continue
		var ttl: float = row.get_meta("ttl") - delta
		row.set_meta("ttl", ttl)
		row.modulate.a = clampf(ttl / 0.5, 0.0, 1.0)
		if ttl <= 0.0:
			row.visible = false
