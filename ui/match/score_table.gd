class_name ScoreTable
extends GridContainer
## A table of players (scoreboard and results). Columns are translation
## keys; rows are Arrays of cell strings. The local player's row is
## highlighted; bots are tagged by the caller.

const DENSE_ROWS := 10

## The last set_rows arguments, and the table's shape (columns, rows): the
## scoreboard is set every frame while shown, so unchanged rows cost
## nothing and changed values only retext the labels (building a row of
## controls costs milliseconds on a phone, m4.md).
var _last: Array = []
var _shape := Vector2i(-1, -1)


## `row_colors`: optional per-row colour (TDM teams); the highlighted row is
## then marked with a leading "›".
func set_rows(headers: Array, rows: Array, highlight_row: int, row_colors: Array = []) -> void:
	var args := [headers, rows, highlight_row, row_colors]
	if args == _last:
		return
	var same_headers: bool = not _last.is_empty() and _last[0] == headers
	_last = args.duplicate(true)
	var shape := Vector2i(headers.size(), rows.size())
	if shape == _shape and same_headers:
		var cells := get_children()
		for i in rows.size():
			var color := _row_color(i, highlight_row, row_colors)
			for j in rows[i].size():
				var l: Label = cells[headers.size() + i * headers.size() + j]
				l.text = _text(rows, i, j, highlight_row, row_colors)
				l.add_theme_color_override("font_color", color)
		return
	_shape = shape
	columns = headers.size()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	# Big matches (up to 16 players) get compact rows, so the table, title
	# and footer still fit a 720 px tall screen.
	var dense := rows.size() > DENSE_ROWS
	add_theme_constant_override("h_separation", 28)
	add_theme_constant_override("v_separation", 1 if dense else 8)
	for h in headers:
		add_child(_cell(tr(h).to_upper(), UiStyle.TEXT_DIM, 17, h == headers[0]))
	for i in rows.size():
		var color := _row_color(i, highlight_row, row_colors)
		for j in rows[i].size():
			add_child(_cell(_text(rows, i, j, highlight_row, row_colors), color,
					(18 if dense else 24) if j > 0 else (17 if dense else 21), j == 0))


func _row_color(i: int, highlight_row: int, row_colors: Array) -> Color:
	if i < row_colors.size():
		return row_colors[i]
	return UiStyle.ACCENT if i == highlight_row else UiStyle.TEXT


func _text(rows: Array, i: int, j: int, highlight_row: int, row_colors: Array) -> String:
	var text := str(rows[i][j])
	if j == 0 and i == highlight_row and i < row_colors.size():
		text = "› " + text
	return text


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
