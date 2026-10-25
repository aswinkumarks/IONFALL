class_name MatchPanel
extends PanelContainer
## Centered panel used for the scoreboard (PLAN §2.6) and the end-of-match
## results screen: a title, a ScoreTable and a footer line.

var title: Label
var table: ScoreTable
var footer: Label
var footer_extra: String = ""  ## e.g. XP gained, shown above the footer
var _xp_box: VBoxContainer
var _xp_label: Label
var _xp_bar: ProgressBar


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.88), UiStyle.ACCENT, 28))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	title = UiStyle.label("", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(title)
	table = ScoreTable.new()
	box.add_child(table)
	_xp_box = VBoxContainer.new()
	_xp_box.add_theme_constant_override("separation", 4)
	_xp_box.visible = false
	box.add_child(_xp_box)
	_xp_label = UiStyle.label("", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_xp_label.add_theme_font_size_override("font_size", 26)
	_xp_box.add_child(_xp_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(420, 8)
	_xp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	_xp_box.add_child(_xp_bar)
	footer = UiStyle.label("", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(footer)
	visible = false


## Scoreboard rows from roster entries {id, name, bot, score, team, kills,
## deaths, assists}. TDM (`team_scores` given): grouped and tinted by team.
func show_scoreboard(roster: Array, local_id: int, subtitle: String, team_scores := PackedInt32Array()) -> void:
	var sorted := _sorted(roster)
	var rows := []
	var colors := []
	var mine := -1
	for i in sorted.size():
		var p: Dictionary = sorted[i]
		if p.id == local_id:
			mine = i
		rows.append([("[BOT] " if p.bot else "") + p.name, p.score, p.get("kills", 0), p.get("deaths", 0), p.get("assists", 0)])
		if not team_scores.is_empty():
			colors.append(_team_color(p.get("team", GameMode.NO_TEAM)))
	title.text = tr("SCOREBOARD_TITLE") if team_scores.is_empty() else _team_line(team_scores)
	table.set_rows(["COL_PLAYER", "COL_SCORE", "COL_KILLS", "COL_DEATHS", "COL_ASSISTS"], rows, mine, colors)
	footer.text = subtitle
	visible = true


## Results rows from a decoded RESULTS message (Protocol.decode_results).
func show_results(results: Dictionary, local_id: int) -> void:
	var tdm: bool = GameMode.is_team_mode(results.get("mode", GameMode.FFA))
	var players: Array = _sorted(results.players) if tdm else results.players
	var rows := []
	var colors := []
	var mine := -1
	var my_team := GameMode.NO_TEAM
	var winner_name := ""
	for i in players.size():
		var p: Dictionary = players[i]
		if p.id == local_id:
			mine = i
			my_team = p.get("team", GameMode.NO_TEAM)
		if p.id == results.winner:
			winner_name = p.name
		var accuracy := "%d%%" % roundi(100.0 * p.hits / p.shots) if p.shots > 0 else "-"
		rows.append([("[BOT] " if p.bot else "") + p.name, p.score, p.kills, p.deaths, p.assists, accuracy, p.damage_dealt])
		if tdm:
			colors.append(_team_color(p.get("team", GameMode.NO_TEAM)))
	title.add_theme_font_size_override("font_size", 56)
	if tdm:
		var wt: int = results.get("winner_team", GameMode.NO_TEAM)
		if wt == GameMode.NO_TEAM:
			title.text = tr("RESULTS_DRAW").to_upper()
			title.add_theme_color_override("font_color", UiStyle.TEXT)
		elif wt == my_team:
			title.text = tr("RESULTS_VICTORY").to_upper()
			title.add_theme_color_override("font_color", GameMode.team_color(wt))
		else:
			title.text = (tr("RESULTS_TEAM_WINS") % GameMode.team_name(wt)).to_upper()
			title.add_theme_color_override("font_color", GameMode.team_color(wt))
	elif results.winner == 0:
		title.text = tr("RESULTS_DRAW").to_upper()
		title.add_theme_color_override("font_color", UiStyle.TEXT)
	elif results.winner == local_id:
		title.text = tr("RESULTS_VICTORY").to_upper()
		title.add_theme_color_override("font_color", UiStyle.ACCENT)
	else:
		title.text = (tr("RESULTS_WINNER") % winner_name).to_upper()
		title.add_theme_color_override("font_color", UiStyle.WARN)
	_xp_box.visible = false
	modulate.a = 0.0
	scale = Vector2(0.96, 0.96)
	pivot_offset = size * 0.5
	var tween := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 1.0, 0.35)
	tween.tween_property(self, "scale", Vector2.ONE, 0.45)
	table.set_rows(["COL_PLAYER", "COL_SCORE", "COL_KILLS", "COL_DEATHS", "COL_ASSISTS", "COL_ACCURACY", "COL_DAMAGE"],
			rows, mine, colors)
	footer.text = _team_line(results.team_scores) if tdm else ""
	if results.get("mode", GameMode.FFA) == GameMode.WAVES:  # co-op: how far the team got
		var cleared: int = results.team_scores[GameMode.HUMANS]
		var won: bool = results.get("winner_team", GameMode.NO_TEAM) == GameMode.HUMANS
		title.text = (tr("WAVES_VICTORY") % Balance.MODES.wave_count if won else tr("WAVES_DEFEAT") % (cleared + 1)).to_upper()
		title.add_theme_color_override("font_color", UiStyle.ACCENT if won else UiStyle.WARN)
		footer.text = ""
	visible = true


## By team (TDM), then score.
static func _sorted(players: Array) -> Array:
	var out := players.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta: int = a.get("team", GameMode.NO_TEAM)
		var tb: int = b.get("team", GameMode.NO_TEAM)
		return ta < tb or (ta == tb and a.score > b.score))
	return out


static func _team_color(team: int) -> Color:
	return GameMode.team_color(team) if team < 2 else UiStyle.TEXT


## "CYAN 12 · 9 ORANGE"
func _team_line(team_scores: PackedInt32Array) -> String:
	return "%s %d  ·  %d %s" % [GameMode.team_name(0).to_upper(), team_scores[0], team_scores[1],
			GameMode.team_name(1).to_upper()]


## XP gained this match: the bar fills from the old total to the new one,
## flashing on a level up.
func show_xp(gained: int, total_xp: int) -> void:
	if gained < 0:
		return
	var before := ProfileData.level_for(total_xp - gained)
	var after := ProfileData.level_for(total_xp)
	_xp_box.visible = true
	_xp_label.text = "+%d XP" % gained
	_xp_label.add_theme_color_override("font_color", UiStyle.ACCENT)
	_xp_bar.max_value = before.needed
	_xp_bar.value = before.into
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_interval(0.5)
	if after.level > before.level:
		tween.tween_property(_xp_bar, "value", float(before.needed), 0.8)
		var unlocked := Unlocks.unlocked_between(before.level, after.level)
		tween.tween_callback(func() -> void:
			_xp_label.text = "+%d XP · %s %d" % [gained, tr("PROFILE_LEVEL").to_upper(), after.level]
			if not unlocked.is_empty():
				var names := PackedStringArray()
				for key in unlocked:
					names.append(tr(key))
				_xp_label.text += "\n" + tr("RESULTS_UNLOCKED") % ", ".join(names)
			_xp_label.add_theme_color_override("font_color", UiStyle.WARN)
			_xp_bar.max_value = after.needed
			_xp_bar.value = 0.0)
	tween.tween_property(_xp_bar, "value", float(after.into), 0.9)
