class_name KillFeed
extends VBoxContainer
## Server-authored kill feed (PLAN §2.6): at most 5 rows, each expires after
## 6 s. Killer, weapon, victim, plus headshot and assist markers; bots are
## tagged; rows involving the local player are highlighted.

const MAX_ROWS := 5
const ROW_SECONDS := 6.0
const WEAPON_TAGS := {&"pulse_rifle": "PULSE", &"mag_pistol": "PISTOL", &"arc_launcher": "ARC",
		&"burst_rifle": "BURST", &"rail_sniper": "RAIL", &"": "FALL"}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 5)


## `name_of`: func(id) -> String (bots already tagged).
func add_death(e: Dictionary, name_of: Callable, local_id: int) -> void:
	var scale: float = Settings.get_value("accessibility", "hud_scale")
	var involved: bool = e.killer == local_id or e.victim == local_id
	var row := PanelContainer.new()
	row.theme_type_variation = &"HudPanel"
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if involved:
		row.add_theme_stylebox_override("panel", UiStyle.box(Color(UiStyle.ACCENT, 0.22), Color(UiStyle.ACCENT, 0.7), 1, UiStyle.SKEW, 14, 6))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	row.add_child(line)
	var weapon: String = WEAPON_TAGS.get(e.weapon, String(e.weapon).to_upper())
	if e.get("environment", false):
		weapon = "FALL"
	if not e.suicide:
		line.add_child(_part(name_of.call(e.killer), _name_color(e.killer, local_id), scale))
	var tag := weapon
	if e.get("headshot", false):
		tag += "  ◎"
	line.add_child(_part(tag, UiStyle.WARN if e.get("headshot", false) else UiStyle.TEXT_DIM, scale * 0.85, true))
	line.add_child(_part(name_of.call(e.victim), _name_color(e.victim, local_id), scale))
	var assists: Array = e.get("assists", [])
	if not e.suicide and not assists.is_empty():
		line.add_child(_part("+ " + ", ".join(assists.map(func(id: int) -> String: return name_of.call(id))),
				UiStyle.TEXT_DIM, scale * 0.8))
	row.set_meta("ttl", ROW_SECONDS)
	add_child(row)
	while get_child_count() > MAX_ROWS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()


func _name_color(id: int, local_id: int) -> Color:
	return UiStyle.ACCENT if id == local_id else UiStyle.TEXT


func _part(text: String, color: Color, scale: float, display: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiStyle.font_display if display else UiStyle.font_body_bold)
	l.add_theme_font_size_override("font_size", roundi((20 if display else 18) * scale))
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _process(delta: float) -> void:
	for row in get_children():
		var ttl: float = row.get_meta("ttl") - delta
		row.set_meta("ttl", ttl)
		row.modulate.a = clampf(ttl / 0.5, 0.0, 1.0)
		if ttl <= 0.0:
			row.queue_free()
