class_name ProfilePanel
extends PanelContainer
## Profile and stats screen (PLAN §3.13): level and XP, then stats split
## vs players / vs bots, with unconfirmed results called out.

signal closed

var _text: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.08, 0.96)
	style.border_color = Color(0.35, 0.9, 1.0, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 20)
	box.add_child(_text)
	var back := Button.new()
	back.text = "MENU_BACK"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	box.add_child(back)
	visible = false


func open(player_name: String) -> void:
	var d := Profile.data
	var s := d.stats()
	var lv := ProfileData.level_for(d.xp())
	var kd := func(side: Dictionary) -> String:
		return "%d / %d / %d  (K/D %.2f)" % [side.kills, side.deaths, side.assists, float(side.kills) / maxf(side.deaths, 1)]
	var lines := PackedStringArray([
		"%s  ·  %s %d  ·  %d / %d XP" % [player_name, tr("PROFILE_LEVEL"), lv.level, lv.into, lv.needed],
		"",
		"%s  %s" % [tr("PROFILE_VS_PLAYERS"), kd.call(s.vs_players)],
		"%s  %s" % [tr("PROFILE_VS_BOTS"), kd.call(s.vs_bots)],
		"%s  %d / %d  (%s %d)" % [tr("PROFILE_WINS_MATCHES"), s.wins, s.matches, tr("PROFILE_INCOMPLETE"), s.matches_incomplete],
		"%s  %d%%  ·  %s %d  ·  %s %d" % [tr("PROFILE_ACCURACY"), roundi(100.0 * s.hits / maxf(s.shots, 1)),
				tr("PROFILE_HEADSHOT_KILLS"), s.headshot_kills, tr("PROFILE_BEST_STREAK"), s.best_streak],
		"%s  %d min" % [tr("PROFILE_TIME_PLAYED"), floori(s.seconds_played / 60.0)],
	])
	if d.data.unconfirmed_results > 0:
		lines.append(tr("PROFILE_UNCONFIRMED") % d.data.unconfirmed_results)
	if Profile.read_only:
		lines.append(tr("PROFILE_READ_ONLY"))
	_text.text = "\n".join(lines)
	visible = true
