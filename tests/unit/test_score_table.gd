extends GutTest
## ScoreTable is set every frame while the scoreboard shows: unchanged rows
## keep their labels, changed values retext them, a new shape rebuilds.

const HEADERS := ["COL_PLAYER", "COL_SCORE"]


func _table() -> ScoreTable:
	var t := ScoreTable.new()
	add_child_autofree(t)
	return t


func _ids(t: ScoreTable) -> Array:
	return t.get_children().map(func(c: Node) -> int: return c.get_instance_id())


func test_same_rows_keep_their_labels() -> void:
	var t := _table()
	t.set_rows(HEADERS, [["Ada", 3], ["Bo", 1]], 0)
	var before := _ids(t)
	assert_eq(before.size(), 6, "two headers and two rows of two")
	t.set_rows(HEADERS, [["Ada", 3], ["Bo", 1]], 0)
	assert_eq(_ids(t), before, "nothing rebuilt")


func test_new_values_retext_the_same_labels() -> void:
	var t := _table()
	t.set_rows(HEADERS, [["Ada", 3], ["Bo", 1]], 0)
	var before := _ids(t)
	t.set_rows(HEADERS, [["Bo", 4], ["Ada", 3]], 1)
	assert_eq(_ids(t), before, "same labels")
	assert_eq((t.get_child(2) as Label).text, "Bo")
	assert_eq((t.get_child(3) as Label).text, "4")
	assert_eq((t.get_child(4) as Label).get_theme_color("font_color"), UiStyle.ACCENT, "the highlight moved")
	assert_eq((t.get_child(2) as Label).get_theme_color("font_color"), UiStyle.TEXT)


func test_more_rows_rebuild() -> void:
	var t := _table()
	t.set_rows(HEADERS, [["Ada", 3]], 0)
	t.set_rows(HEADERS, [["Ada", 3], ["Bo", 1]], 0)
	assert_eq(t.get_child_count(), 6)
	assert_eq((t.get_child(4) as Label).text, "Bo")


func test_team_rows_mark_the_highlight() -> void:
	var t := _table()
	t.set_rows(HEADERS, [["Ada", 3], ["Bo", 1]], 1, [Color.RED, Color.BLUE])
	assert_eq((t.get_child(4) as Label).text, "› Bo")
	assert_eq((t.get_child(4) as Label).get_theme_color("font_color"), Color.BLUE)
