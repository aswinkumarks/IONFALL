class_name ProfilePanel
extends Control
## Profile screen (PLAN §3.13), two tabs: Customise (callsign, colour,
## character; CustomizeView) and Stats (a header card with level and XP,
## then stat tiles split vs players / vs bots, with unconfirmed results and
## read-only profiles called out). Back saves the callsign. Full-screen
## overlay in the menu's style.

signal closed

enum Tab { CUSTOMIZE, STATS }

var customize := CustomizeView.new()
var _tabs := TabContainer.new()
var _column: VBoxContainer
var _name: Label
var _badge: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _grid: GridContainer
var _notes: Label
var _back: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(UiStyle.BG, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	root.add_child(UiStyle.label("MENU_PROFILE", &"HeaderLabel"))
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	customize.name = "PROFILE_TAB_CUSTOMIZE"
	_tabs.add_child(customize)
	var scroll := ScrollContainer.new()
	scroll.name = "PROFILE_TAB_STATS"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 14)
	scroll.add_child(_column)

	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	_column.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)
	_badge = UiStyle.label("1", &"BadgeLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_badge.custom_minimum_size = Vector2(76, 64)
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badge)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	_name = UiStyle.label("", &"HeaderLabel")
	_name.add_theme_font_size_override("font_size", 32)
	info.add_child(_name)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size.y = 8
	_xp_bar.show_percentage = false
	info.add_child(_xp_bar)
	_xp_label = UiStyle.label("", &"DimLabel")
	info.add_child(_xp_label)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_column.add_child(_grid)
	_notes = UiStyle.label("", &"DimLabel")
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD
	_column.add_child(_notes)
	_back = UiStyle.menu_button("MENU_BACK", &"PrimaryButton")
	_back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back.custom_minimum_size.x = 240
	_back.size_flags_horizontal = Control.SIZE_SHRINK_END
	_back.pressed.connect(close)
	root.add_child(_back)
	visible = false


func _tile(value: String, caption: String, sub: String = "") -> Control:
	var tile := PanelContainer.new()
	tile.theme_type_variation = &"CardPanel"
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	tile.add_child(box)
	box.add_child(UiStyle.label(tr(caption).to_upper(), &"DimLabel"))
	var v := UiStyle.label(value, &"HeaderLabel")
	box.add_child(v)
	if not sub.is_empty():
		box.add_child(UiStyle.label(sub, &"DimLabel"))
	return tile


## `player_name`: the callsign in the menu's name field.
func open(player_name: String, tab: Tab = Tab.CUSTOMIZE) -> void:
	customize.load_profile(player_name)
	var d := Profile.data
	var s := d.stats()
	var lv := ProfileData.level_for(d.xp())
	_name.text = player_name
	_badge.text = str(lv.level)
	_xp_bar.max_value = lv.needed
	_xp_bar.value = lv.into
	_xp_label.text = tr("MENU_XP_PROGRESS") % [lv.level, lv.into, lv.needed]
	for c in _grid.get_children():
		c.queue_free()
	var kda := func(side: Dictionary) -> String:
		return "%d / %d / %d" % [side.kills, side.deaths, side.assists]
	var kd := func(side: Dictionary) -> String:
		return "K/D %.2f" % (float(side.kills) / maxf(side.deaths, 1))
	_grid.add_child(_tile(kda.call(s.vs_players), "PROFILE_TILE_VS_PLAYERS", kd.call(s.vs_players)))
	_grid.add_child(_tile(kda.call(s.vs_bots), "PROFILE_TILE_VS_BOTS", kd.call(s.vs_bots)))
	_grid.add_child(_tile("%d / %d" % [s.wins, s.matches], "PROFILE_TILE_WINS",
			"%s %d" % [tr("PROFILE_INCOMPLETE"), s.matches_incomplete]))
	_grid.add_child(_tile("%d%%" % roundi(100.0 * s.hits / maxf(s.shots, 1)), "PROFILE_ACCURACY"))
	_grid.add_child(_tile(str(s.headshot_kills), "PROFILE_HEADSHOT_KILLS"))
	_grid.add_child(_tile(str(s.best_streak), "PROFILE_BEST_STREAK"))
	_grid.add_child(_tile("%d min" % floori(s.seconds_played / 60.0), "PROFILE_TIME_PLAYED"))
	var notes := PackedStringArray()
	if d.data.unconfirmed_results > 0:
		notes.append(tr("PROFILE_UNCONFIRMED") % d.data.unconfirmed_results)
	if Profile.read_only:
		notes.append(tr("PROFILE_READ_ONLY"))
	_notes.text = "\n".join(notes)
	_notes.visible = not notes.is_empty()
	_tabs.current_tab = tab
	visible = true
	_back.grab_focus()


func close() -> void:
	customize.save()
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
