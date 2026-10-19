class_name MatchPanel
extends PanelContainer
## Centered panel used for the scoreboard (PLAN §2.6) and the end-of-match
## results screen: a title, a ScoreTable and a footer line.

var title: Label
var table: ScoreTable
var footer: Label
var footer_extra: String = ""  ## e.g. XP gained, shown above the footer


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
	footer = UiStyle.label("", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(footer)
	visible = false


## Scoreboard rows from roster entries {id, name, bot, score, kills, deaths, assists}.
func show_scoreboard(roster: Array, local_id: int, subtitle: String) -> void:
	var sorted := roster.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var rows := []
	var mine := -1
	for i in sorted.size():
		var p: Dictionary = sorted[i]
		if p.id == local_id:
			mine = i
		rows.append([("[BOT] " if p.bot else "") + p.name, p.score, p.get("kills", 0), p.get("deaths", 0), p.get("assists", 0)])
	title.text = tr("SCOREBOARD_TITLE")
	table.set_rows(["COL_PLAYER", "COL_SCORE", "COL_KILLS", "COL_DEATHS", "COL_ASSISTS"], rows, mine)
	footer.text = subtitle
	visible = true


## Results rows from a decoded RESULTS message (Protocol.decode_results).
func show_results(results: Dictionary, local_id: int) -> void:
	var rows := []
	var mine := -1
	var winner_name := ""
	for i in results.players.size():
		var p: Dictionary = results.players[i]
		if p.id == local_id:
			mine = i
		if p.id == results.winner:
			winner_name = p.name
		var accuracy := "%d%%" % roundi(100.0 * p.hits / p.shots) if p.shots > 0 else "-"
		rows.append([("[BOT] " if p.bot else "") + p.name, p.score, p.kills, p.deaths, p.assists, accuracy, p.damage_dealt])
	if results.winner == 0:
		title.text = tr("RESULTS_DRAW")
	elif results.winner == local_id:
		title.text = tr("RESULTS_VICTORY")
	else:
		title.text = tr("RESULTS_WINNER") % winner_name
	table.set_rows(["COL_PLAYER", "COL_SCORE", "COL_KILLS", "COL_DEATHS", "COL_ASSISTS", "COL_ACCURACY", "COL_DAMAGE"],
			rows, mine)
	footer.text = ""
	visible = true
