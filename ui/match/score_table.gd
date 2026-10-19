class_name ScoreTable
extends GridContainer
## A table of players (scoreboard and results). Columns are translation
## keys; rows are Arrays of cell strings. The local player's row is
## highlighted; bots are tagged by the caller.


func set_rows(headers: Array, rows: Array, highlight_row: int) -> void:
	columns = headers.size()
	for child in get_children():
		child.queue_free()
	add_theme_constant_override("h_separation", 28)
	add_theme_constant_override("v_separation", 6)
	for h in headers:
		add_child(_cell(tr(h), Color(0.35, 0.9, 1.0), 16, h == headers[0]))
	for i in rows.size():
		var color := Color(1.0, 0.85, 0.4) if i == highlight_row else Color(0.92, 0.94, 0.97)
		for j in rows[i].size():
			add_child(_cell(str(rows[i][j]), color, 20, j == 0))


func _cell(text: String, color: Color, size: int, left: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if left else Control.SIZE_SHRINK_END
	l.custom_minimum_size.x = 220.0 if left else 56.0
	return l
