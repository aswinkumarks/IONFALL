class_name ScoreTable
extends GridContainer
## A table of players (scoreboard and results). Columns are translation
## keys; rows are Arrays of cell strings. The local player's row is
## highlighted; bots are tagged by the caller.

const DENSE_ROWS := 10


## `row_colors`: optional per-row colour (TDM teams); the highlighted row is
## then marked with a leading "›".
func set_rows(headers: Array, rows: Array, highlight_row: int, row_colors: Array = []) -> void:
	columns = headers.size()
	for child in get_children():
		child.queue_free()
	# Big matches (up to 16 players) get compact rows, so the table, title
	# and footer still fit a 720 px tall screen.
	var dense := rows.size() > DENSE_ROWS
	add_theme_constant_override("h_separation", 28)
	add_theme_constant_override("v_separation", 1 if dense else 8)
	for h in headers:
		add_child(_cell(tr(h).to_upper(), UiStyle.TEXT_DIM, 17, h == headers[0]))
	for i in rows.size():
		var color := UiStyle.ACCENT if i == highlight_row else UiStyle.TEXT
		if i < row_colors.size():
			color = row_colors[i]
		for j in rows[i].size():
			var text := str(rows[i][j])
			if j == 0 and i == highlight_row and i < row_colors.size():
				text = "› " + text
			add_child(_cell(text, color, (18 if dense else 24) if j > 0 else (17 if dense else 21), j == 0))


func _cell(text: String, color: Color, size: int, left: bool) -> Label:
	var l := Label.new()
	l.text = text
	if not left or size >= 24:
		l.add_theme_font_override("font", UiStyle.font_display)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL if left else Control.SIZE_SHRINK_END
	l.custom_minimum_size.x = 220.0 if left else 56.0
	return l
