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
	add_theme_constant_override("separation", 4)


## `name_of`: func(id) -> String (bots already tagged).
func add_death(e: Dictionary, name_of: Callable, local_id: int) -> void:
	var row := Label.new()
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_theme_font_size_override("font_size", roundi(18 * float(Settings.get_value("accessibility", "hud_scale"))))
	row.add_theme_constant_override("outline_size", 5)
	row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	var weapon: String = WEAPON_TAGS.get(e.weapon, String(e.weapon).to_upper())
	var victim: String = name_of.call(e.victim)
	if e.suicide:
		row.text = "%s  [%s]" % [victim, weapon if not e.get("environment", false) else "FALL"]
	else:
		var marks := ""
		if e.get("headshot", false):
			marks += " ◎"
		var assists: Array = e.get("assists", [])
		if not assists.is_empty():
			marks += " +" + ", ".join(assists.map(func(id: int) -> String: return name_of.call(id)))
		row.text = "%s  [%s%s]  %s" % [name_of.call(e.killer), weapon, marks, victim]
	var involved: bool = e.killer == local_id or e.victim == local_id
	row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if involved else Color(0.92, 0.94, 0.97))
	row.set_meta("ttl", ROW_SECONDS)
	add_child(row)
	while get_child_count() > MAX_ROWS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()


func _process(delta: float) -> void:
	for row in get_children():
		var ttl: float = row.get_meta("ttl") - delta
		row.set_meta("ttl", ttl)
		row.modulate.a = clampf(ttl / 0.5, 0.0, 1.0)
		if ttl <= 0.0:
			row.queue_free()
