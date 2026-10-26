extends Control
## Main menu, full screen over the station backdrop. Every visible string is
## a translation key (PLAN §3.16).
##
## Home: the title, the player card with Settings and Quit at the top, and
## three big cards along the bottom: Single Player, Host Game, Join Game.
## Each opens its own screen: Single Player picks map, mode and duration;
## Host picks LAN or internet and opens the lobby; Join lists LAN and online
## games next to a box for an address or invite code. Back and Escape return
## home.
##
## Quick test launches (desktop): `-- --play`, `-- --host` (straight into a
## hosted match), `-- --lobby [--online]` (a hosted lobby), `-- --join
## <address or code>` and `-- --name <name>` skip the menu;
## `--open-settings` / `--open-profile` open those screens (`--open-stats`:
## the profile's Stats tab).

const MATCH := "res://game/match.tscn"
const LOBBY := "res://ui/lobby/lobby.tscn"
const ONLINE_LIST_INTERVAL_S := 5.0
const MARGIN := Vector2(56, 40)
## Card sizes: full-width rows for thumbs on phones; fixed, smaller cards
## with a mouse on a desktop screen.
const CARD_DESKTOP := Vector2(300, 150)
const HOST_CARD_DESKTOP := Vector2(380, 190)

enum Page { HOME, SOLO, HOST, JOIN }

@onready var _version_label: Label = %VersionLabel

static var _quick_launched: bool = false
var _page: int = Page.HOME
var _pages: Dictionary = {}  ## Page -> Control
var _first: Dictionary = {}  ## Page -> the control focused on entry
var _opener: Dictionary = {}  ## Page -> the home card that opens it
var _dim := ColorRect.new()
var _status: Label
var _notices: VBoxContainer
var _badge: Label
var _chip_name: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _map_tiles: Array[MenuTile] = []
var _mode_chips: HBoxContainer
var _solo_hint: Label
var _duration_chips: HBoxContainer
var _bot_stepper: Stepper
var _difficulty_chips: HBoxContainer
var _ff_chips: HBoxContainer
var _address_edit: LineEdit
var _watch_toggle: CheckButton
var _games_label: Label
var _game_list: VBoxContainer
var _join_status: Label
var _browser: Discovery.Browser
var _online_games: Array = []
var _online_error: String = ""
var _listing: bool = false
var _profile_panel := ProfilePanel.new()
var _settings := SettingsMenu.new()
var _quit_panel: Control  ## "Quit IONFALL?", from Back on the home page


func _ready() -> void:
	Settings.set_menu_mode(true)
	var music := AudioStreamPlayer.new()
	music.stream = load("res://audio/generated/menu_theme.wav")
	music.bus = "Music"
	music.volume_db = -14.0  # a quiet bed under the menu
	add_child(music)
	music.play()
	_version_label.text = BuildInfo.display_string()
	# Sub-screens dim the backdrop so their content reads well.
	_dim.color = UiStyle.BG
	_dim.modulate.a = 0.0
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_build_home()
	_build_solo()
	_build_host()
	_build_join()
	move_child(_version_label, -1)
	add_child(_profile_panel)
	add_child(_settings)
	_quit_panel = _make_quit_panel()
	add_child(_quit_panel)
	_settings.closed.connect(func() -> void: (_first[Page.HOME] as Control).grab_focus())
	_profile_panel.closed.connect(func() -> void:
		_update_player_card()
		(_first[Page.HOME] as Control).grab_focus())
	if not MatchConfig.last_error.is_empty():
		_show_status(tr(MatchConfig.last_error))
		MatchConfig.last_error = ""
	_offer_rejoin()
	_update_player_card()
	Profile.changed.connect(_update_player_card)
	_show(Page.HOME, false)
	_animate_in()
	if _try_join_link():
		return
	# Quick-launch flags act once per session: coming back to the menu (e.g.
	# after a failed join) must not start the same match again.
	if _quick_launched:
		return
	_quick_launched = true
	if Platform.user_args.has("--open-settings"):
		_settings.open()
	elif Platform.user_args.has("--open-profile"):
		_profile_panel.open(_player_name())
	elif Platform.user_args.has("--open-stats"):
		_profile_panel.open(_player_name(), ProfilePanel.Tab.STATS)
	elif Platform.user_args.has("--play"):
		_start_solo.call_deferred()
	elif Platform.user_args.has("--host"):
		_host_match.call_deferred(Platform.user_args.has("--online"))
	elif Platform.user_args.has("--lobby"):
		_host_lobby.call_deferred(Platform.user_args.has("--online"))
	elif Platform.user_args.has("--join") and not Platform.user_args.has("--test-clients"):
		_address_edit.text = Platform.get_user_arg("--join", "127.0.0.1")
		_join_manual.call_deferred()


# --- Screens ---

## A full-screen page with the menu's margins; returns its content column.
func _page_root(page: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(MARGIN.x))
	margin.add_theme_constant_override("margin_right", int(MARGIN.x))
	margin.add_theme_constant_override("margin_top", int(MARGIN.y))
	margin.add_theme_constant_override("margin_bottom", int(MARGIN.y))
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_pages[page] = margin
	return column


func _build_home() -> void:
	var column := _page_root(Page.HOME)
	# Top: player card, Settings, Quit.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(top)
	top.add_child(_player_card())
	var settings := MenuKit.icon_button("gear", "", _settings.open)
	settings.set_meta("ui_key", "MENU_SETTINGS")
	settings.tooltip_text = "MENU_SETTINGS"
	top.add_child(settings)
	var quit := MenuKit.icon_button("power", "", get_tree().quit)
	quit.set_meta("ui_key", "MENU_QUIT")
	quit.tooltip_text = "MENU_QUIT"
	# Browsers close the tab instead.
	quit.visible = not Platform.is_web()
	top.add_child(quit)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var title := UiStyle.label("MENU_TITLE", &"TitleLabel")
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 112)
	column.add_child(title)
	var bar := ColorRect.new()
	bar.name = "TitleBar"
	bar.color = UiStyle.ACCENT
	bar.custom_minimum_size = Vector2(120, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(bar)
	# The browser build is single player only: no LAN or internet play there.
	var tagline := UiStyle.label("MENU_TAGLINE_WEB" if Platform.is_web() else "MENU_TAGLINE", &"DimLabel")
	tagline.add_theme_font_size_override("font_size", 20)
	column.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 18
	column.add_child(gap)
	# Errors, the profile warning and the rejoin offer, just above the cards.
	_notices = VBoxContainer.new()
	_notices.add_theme_constant_override("separation", 6)
	column.add_child(_notices)
	_status = UiStyle.label("")
	_status.add_theme_color_override("font_color", UiStyle.DANGER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	_notices.add_child(_status)
	var storage := UiStyle.label("MENU_PROFILE_NOT_SAVED")
	storage.add_theme_color_override("font_color", UiStyle.WARN)
	storage.visible = not Platform.storage_available
	_notices.add_child(storage)

	var cards := HBoxContainer.new()
	cards.name = "Cards"
	cards.add_theme_constant_override("separation", 18)
	cards.custom_minimum_size.y = 220 if Platform.is_mobile() else CARD_DESKTOP.y
	column.add_child(cards)
	var solo := _card(cards, "MENU_SINGLE_PLAYER", "MENU_SINGLE_PLAYER_SUB", "solo", _show.bind(Page.SOLO))
	_opener[Page.SOLO] = solo
	_first[Page.HOME] = solo
	# Web builds can't host (PLAN §3.20); they join a native host that also
	# serves browsers over WebSocket.
	if not Platform.is_web():
		# Internet play (decision 0005) only where the EOS backend is
		# available; elsewhere Host opens a LAN lobby directly.
		var host := _card(cards, "MENU_HOST", "MENU_HOST_SUB" if Online.available() else "MENU_HOST_LAN_SUB",
				"host", _show.bind(Page.HOST) if Online.available() else _host_lobby.bind(false))
		host.accent = UiStyle.GOOD
		_opener[Page.HOST] = host
	var join := _card(cards, "MENU_JOIN", "MENU_JOIN_SUB_WEB" if Platform.is_web() else "MENU_JOIN_SUB", "join",
			_show.bind(Page.JOIN))
	join.accent = UiStyle.WARN
	_opener[Page.JOIN] = join


func _card(row: HBoxContainer, title: String, subtitle: String, icon: String, action: Callable) -> MenuTile:
	var tile := MenuTile.make(title, subtitle, icon)
	if Platform.is_mobile():
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		tile.custom_minimum_size = CARD_DESKTOP
	tile.pressed.connect(action)
	row.add_child(tile)
	return tile


## Level badge, name and XP; opens the profile.
func _player_card() -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(320, 76)
	card.set_meta("ui_key", "MENU_PROFILE")
	card.tooltip_text = "MENU_PROFILE"
	card.pressed.connect(func() -> void: _profile_panel.open(_player_name()))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var pad := Control.new()
	pad.custom_minimum_size.x = 8
	row.add_child(pad)
	_badge = UiStyle.label("1", &"BadgeLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_badge.custom_minimum_size = Vector2(54, 48)
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badge)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	_chip_name = UiStyle.label("")
	_chip_name.add_theme_font_override("font", UiStyle.font_display_bold)
	_chip_name.add_theme_font_size_override("font_size", 24)
	info.add_child(_chip_name)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(200, 5)
	_xp_bar.show_percentage = false
	info.add_child(_xp_bar)
	_xp_label = UiStyle.label("", &"DimLabel")
	_xp_label.add_theme_font_size_override("font_size", 14)
	info.add_child(_xp_label)
	var end := Control.new()
	end.custom_minimum_size.x = 14
	row.add_child(end)
	for c: Control in [row, info, pad, end, _badge, _chip_name, _xp_bar, _xp_label]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _build_solo() -> void:
	var column := _page_root(Page.SOLO)
	column.add_child(MenuKit.header("MENU_SINGLE_PLAYER", "MENU_BACK", _go_back))
	var c := MatchConfig.make(MatchConfig.Mode.OFFLINE, "", MatchConfig.profile_bots())
	column.add_child(MenuKit.section("MENU_SECTION_MAP"))
	var maps := HBoxContainer.new()
	maps.add_theme_constant_override("separation", 18)
	maps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(maps)
	for id: String in Maps.PLAYABLE:
		var tile := MenuTile.make(Maps.LIST[id].name, Maps.LIST[id].blurb, "", load(Maps.LIST[id].thumb))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.selected = id == c.map
		tile.pressed.connect(_save_choice.bind("map", id))
		maps.add_child(tile)
		_map_tiles.append(tile)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 40)
	column.add_child(options)
	_mode_chips = _option(options, "MENU_SECTION_MODE", GameMode.CHIP_KEYS, c.game_mode,
			func(i: int) -> void: _save_choice("mode", GameMode.IDS[i]))
	_duration_chips = _option(options, "MENU_SECTION_DURATION", MenuKit.duration_labels(),
			LobbySession.DURATIONS.find(c.minutes),
			func(i: int) -> void: _save_choice("minutes", LobbySession.DURATIONS[i]))
	var bot_options := HBoxContainer.new()
	bot_options.add_theme_constant_override("separation", 40)
	column.add_child(bot_options)
	_bot_stepper = _stepper(bot_options, "MENU_SECTION_BOTS", Stepper.new(1, c.max_bots(), c.clamp_bots(c.bots, false)),
			func(n: int) -> void: _save_choice("bots", n))
	_difficulty_chips = _option(bot_options, "MENU_SECTION_BOT_DIFFICULTY", MenuKit.difficulty_labels(),
			c.bot_difficulty, func(i: int) -> void: _save_choice("bot_difficulty", BotBrain.DIFFICULTY_IDS[i]))
	_ff_chips = _option(bot_options, "MENU_SECTION_FRIENDLY_FIRE", ["MENU_OFF", "MENU_ON"], 1 if c.friendly_fire else 0,
			func(i: int) -> void: _save_choice("friendly_fire", i == 1))
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	var hint := UiStyle.label("", &"DimLabel")
	_solo_hint = hint
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(hint)
	# Spectator mode: the same match with bots only, watched from their eyes.
	var watch := UiStyle.menu_button("MENU_WATCH", &"GhostButton")
	watch.custom_minimum_size = Vector2(220, 64)
	watch.alignment = HORIZONTAL_ALIGNMENT_CENTER
	watch.pressed.connect(_start_solo.bind(true))
	bottom.add_child(watch)
	var start := UiStyle.menu_button("MENU_START", &"PrimaryButton")
	start.custom_minimum_size = Vector2(320, 64)
	start.alignment = HORIZONTAL_ALIGNMENT_CENTER
	start.pressed.connect(_start_solo)
	bottom.add_child(start)
	_first[Page.SOLO] = start
	_update_solo()


## A captioned chip row in `parent`.
func _option(parent: Control, caption: String, labels: Array, selected: int, on_select: Callable) -> HBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	box.add_child(MenuKit.section(caption))
	var chips := MenuKit.chips(labels, selected, on_select)
	box.add_child(chips)
	return chips


## A captioned stepper in `parent`; `on_change(value)`.
func _stepper(parent: Control, caption: String, stepper: Stepper, on_change: Callable) -> Stepper:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	box.add_child(MenuKit.section(caption))
	box.add_child(stepper)
	stepper.changed.connect(on_change)
	return stepper


func _build_host() -> void:
	var column := _page_root(Page.HOST)
	column.add_child(MenuKit.header("MENU_HOST", "MENU_BACK", _go_back))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.custom_minimum_size.y = 300 if Platform.is_mobile() else HOST_CARD_DESKTOP.y
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	var lan := _card(row, "MENU_HOST_LAN", "MENU_HOST_LAN_SUB", "lan", _host_lobby.bind(false))
	lan.accent = UiStyle.GOOD
	var online := _card(row, "MENU_HOST_ONLINE", "MENU_HOST_ONLINE_SUB", "online", _host_lobby.bind(true))
	if not Platform.is_mobile():
		lan.custom_minimum_size = HOST_CARD_DESKTOP
		online.custom_minimum_size = HOST_CARD_DESKTOP
	_first[Page.HOST] = lan
	var after := Control.new()
	after.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(after)
	column.add_child(UiStyle.label("MENU_HOST_HINT", &"DimLabel"))


func _build_join() -> void:
	var column := _page_root(Page.JOIN)
	column.add_child(MenuKit.header("MENU_JOIN", "MENU_BACK", _go_back))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	# Left: every game we can see.
	var games := PanelContainer.new()
	games.theme_type_variation = &"CardPanel"
	games.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games.size_flags_stretch_ratio = 1.8
	row.add_child(games)
	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 10)
	games.add_child(list_box)
	_games_label = MenuKit.section("MENU_GAMES_SEARCHING")
	list_box.add_child(_games_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box.add_child(scroll)
	_game_list = VBoxContainer.new()
	_game_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_game_list)
	# Right: join by address or invite code.
	var direct := PanelContainer.new()
	direct.theme_type_variation = &"CardPanel"
	direct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	direct.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(direct)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	direct.add_child(box)
	box.add_child(MenuKit.section("MENU_JOIN_DIRECT"))
	var hint_key := "MENU_JOIN_DIRECT_HINT" if Online.available() else "MENU_JOIN_DIRECT_HINT_LAN"
	var hint := UiStyle.label("MENU_JOIN_DIRECT_HINT_WEB" if Platform.is_web() else hint_key, &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	_address_edit = LineEdit.new()
	_address_edit.placeholder_text = "MENU_ADDRESS_PLACEHOLDER" if Online.available() else "MENU_ADDRESS_PLACEHOLDER_LAN"
	_address_edit.select_all_on_focus = true
	_address_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_address_edit.custom_minimum_size.y = 52
	var last: Variant = Settings.get_value("profile", "last_address")
	_address_edit.text = last if last is String else ""
	if Platform.is_web() and _address_edit.text.is_empty():
		# The page usually comes from the host itself.
		var page_host: Variant = JavaScriptBridge.eval("location.hostname")
		_address_edit.text = page_host if page_host is String else ""
	_address_edit.text_submitted.connect(func(_t: String) -> void: _join_manual())
	box.add_child(_address_edit)
	var connect := UiStyle.menu_button("MENU_CONNECT", &"PrimaryButton")
	connect.alignment = HORIZONTAL_ALIGNMENT_CENTER
	connect.pressed.connect(_join_manual)
	box.add_child(connect)
	# Spectate: games already playing are joined as a watcher.
	_watch_toggle = CheckButton.new()
	_watch_toggle.text = "MENU_JOIN_WATCH"
	_watch_toggle.button_pressed = Platform.user_args.has("--spectate")
	_watch_toggle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_watch_toggle)
	_join_status = UiStyle.label("")
	_join_status.add_theme_color_override("font_color", UiStyle.DANGER)
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_join_status)
	_first[Page.JOIN] = _address_edit


## Shows a page with a short slide-in; sub-pages dim the backdrop.
func _show(page: int, animate: bool = true) -> void:
	_page = page
	for p: int in _pages:
		(_pages[p] as Control).visible = p == page
	_set_browsing(page == Page.JOIN)
	if page == Page.SOLO:
		_update_solo()
	var root: Control = _pages[page]
	var tween := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_dim, "modulate:a", 0.0 if page == Page.HOME else 0.62, 0.3)
	if animate:
		# Slide by the margin: moving an anchored page would break its size.
		root.modulate.a = 0.0
		tween.tween_property(root, "modulate:a", 1.0, 0.25)
		tween.tween_method(func(v: float) -> void: root.add_theme_constant_override("margin_left", roundi(v)),
				MARGIN.x + 48.0, MARGIN.x, 0.3)
	(_first[page] as Control).grab_focus.call_deferred()


func _go_back() -> void:
	if _page == Page.HOME:
		return
	var from := _page
	_show(Page.HOME)
	if _opener.has(from):  # focus the card that led here
		(_opener[from] as Control).grab_focus.call_deferred()


## Escape / Android back: up to the home page, then asks to quit.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _settings.visible or _profile_panel.visible:
		return
	get_viewport().set_input_as_handled()
	if _quit_panel.visible:
		_quit_panel.visible = false
		(_first[Page.HOME] as Control).grab_focus()
	elif _page != Page.HOME:
		_go_back()
	elif not Platform.is_web():
		_quit_panel.visible = true


func _make_quit_panel() -> Control:
	var parts := UiStyle.menu_overlay()
	var root: Control = parts[0]
	var box: VBoxContainer = parts[1]
	root.visible = false
	var text := UiStyle.label("QUIT_CONFIRM", &"HeaderLabel")
	text.add_theme_font_size_override("font_size", 30)
	box.add_child(text)
	var stay := UiStyle.menu_button("LEAVE_CONFIRM_NO", &"PrimaryButton")
	stay.pressed.connect(func() -> void:
		root.visible = false
		(_first[Page.HOME] as Control).grab_focus())
	box.add_child(stay)
	var quit := UiStyle.menu_button("MENU_QUIT")
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)
	root.visibility_changed.connect(func() -> void:
		if root.visible:
			stay.grab_focus())
	return root


## Entrance: the title slides in and the cards fade up one after another.
func _animate_in() -> void:
	var home: Control = _pages[Page.HOME]
	var title: Control = home.find_child("Title", true, false)
	var bar: Control = home.find_child("TitleBar", true, false)
	var cards: Control = home.find_child("Cards", true, false)
	var tween := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	title.modulate.a = 0.0
	tween.tween_property(title, "modulate:a", 1.0, 0.5)
	tween.tween_method(func(v: float) -> void: home.add_theme_constant_override("margin_left", roundi(v)),
			MARGIN.x - 40.0, MARGIN.x, 0.6)
	bar.custom_minimum_size.x = 0.0
	tween.tween_property(bar, "custom_minimum_size:x", 120.0, 0.7).set_delay(0.2)
	var i := 0
	for card: Control in cards.get_children():
		card.modulate.a = 0.0
		tween.tween_property(card, "modulate:a", 1.0, 0.4).set_delay(0.15 + i * 0.08)
		i += 1


func _show_status(text: String) -> void:
	_status.text = text
	_status.visible = true
	_join_status.text = text if _page == Page.JOIN else ""


# --- Player card ---

## Level badge and XP progress from the local profile (PLAN §3.13).
func _update_player_card() -> void:
	var lv := ProfileData.level_for(Profile.data.xp())
	_badge.text = str(lv.level)
	_chip_name.text = _player_name()
	_xp_bar.max_value = lv.needed
	_xp_bar.value = lv.into
	_xp_label.text = tr("MENU_XP_PROGRESS") % [lv.level, lv.into, lv.needed]


## The profile name, or a dev `--name` for this session.
func _player_name() -> String:
	return ServerSession.sanitize_name(Platform.get_user_arg("--name", MatchConfig.profile_name()))


# --- Single player: map, mode, duration and bots (saved for next time) ---

func _save_choice(key: String, value: Variant) -> void:
	Settings.set_value("profile", key, value)
	Settings.save_settings()
	_update_solo()


func _update_solo() -> void:
	var c := MatchConfig.make(MatchConfig.Mode.OFFLINE, "", MatchConfig.profile_bots())
	for i in _map_tiles.size():
		_map_tiles[i].selected = Maps.PLAYABLE[i] == c.map
	MenuKit.select_chip(_mode_chips, c.game_mode)
	var bots := c.clamp_bots(c.bots, false)
	if c.game_mode == GameMode.WAVES:
		_solo_hint.text = tr("MENU_SOLO_HINT_WAVES")
	else:
		_solo_hint.text = tr("MENU_SOLO_HINT_ONE") if bots == 1 else tr("MENU_SOLO_HINT") % bots
	MenuKit.select_chip(_duration_chips, LobbySession.DURATIONS.find(c.minutes))
	_bot_stepper.set_value(bots)
	MenuKit.select_chip(_difficulty_chips, c.bot_difficulty)
	MenuKit.select_chip(_ff_chips, 1 if c.friendly_fire else 0)
	# Co-op waves bring their own bots; friendly fire needs teams.
	_bot_stepper.set_enabled(c.game_mode != GameMode.WAVES)
	MenuKit.set_chips_enabled(_ff_chips, MatchConfig.friendly_fire_applies(c.game_mode))


## After a match was lost to the network, a button rejoins it with our
## token while the server keeps our place (PLAN §3.4: 60 s).
func _offer_rejoin() -> void:
	var offer := MatchConfig.open_rejoin()
	if offer.is_empty():
		return
	var button := UiStyle.menu_button("MENU_REJOIN", &"PrimaryButton")
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.custom_minimum_size = Vector2(320, 54)
	_notices.add_child(button)
	button.pressed.connect(func() -> void:
		var config: MatchConfig = offer.config
		config.reconnect_token = offer.token
		config.map_retried = false
		config.from_lobby = false
		MatchConfig.rejoin = {}
		MatchConfig.pending = config
		LoadingCover.change_scene(get_tree(), MATCH))
	get_tree().create_timer((int(offer.until_ms) - Time.get_ticks_msec()) / 1000.0).timeout.connect(func() -> void:
		if is_instance_valid(button):
			button.queue_free())
	_first[Page.HOME] = button


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_try_join_link()


## ionfall://join?host=…&port=… (PLAN §3.6): from the command line or an
## Android intent.
func _try_join_link() -> bool:
	var link := Platform.take_join_link()
	if link.is_empty():
		return false
	var config := _config(MatchConfig.Mode.JOIN)
	config.address = link.host
	config.port = link.port
	_go(LOBBY, config)
	return true


# --- Join: LAN and online games, or an address / invite code ---

## While the join screen is open, LAN beacons are heard and online games are
## listed every few seconds (PLAN §3.6).
func _set_browsing(on: bool) -> void:
	if Platform.is_web():
		_games_label.text = tr("MENU_LAN_UNAVAILABLE_WEB")  # no UDP broadcast in browsers
		return
	if on and _browser == null:
		_browser = Discovery.Browser.new()
		_browser.changed.connect(_refresh_games)
		add_child(_browser)
		_refresh_games()
		if Online.available():
			_list_online()
	elif not on and _browser != null:
		_browser.queue_free()
		_browser = null


func _list_online() -> void:
	if _listing:
		return
	_listing = true
	while _browser != null and is_inside_tree():
		var listed: Dictionary = await Online.list_games(_player_name())
		if not is_inside_tree():
			return
		_online_games = listed.get("games", [])
		_online_error = listed.get("error", "")
		_refresh_games()
		await get_tree().create_timer(ONLINE_LIST_INTERVAL_S).timeout
	_listing = false


func _refresh_games() -> void:
	for child in _game_list.get_children():
		child.queue_free()
	var lan := _browser.sorted() if _browser != null else []
	var count := lan.size() + _online_games.size()
	if _browser != null and not _browser.listening and _online_games.is_empty():
		_games_label.text = tr("MENU_LAN_UNAVAILABLE")
	else:
		_games_label.text = tr("MENU_GAMES_SEARCHING") if count == 0 else tr("MENU_GAMES") % count
	if not _online_error.is_empty():
		_games_label.text += " · " + tr("NET_ONLINE_ERROR") % _online_error
	if count == 0:
		var empty := UiStyle.label("MENU_GAMES_EMPTY", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.y = 160
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_game_list.add_child(empty)
	for b: Discovery.Beacon in lan:
		var lobby := b.flags & Discovery.FLAG_LOBBY != 0
		var row := _game_row("lan", b.name, b.mode, b.map, b.combatants, b.max_combatants, lobby)
		if not b.compatible():
			row.subtitle += " · " + tr("MENU_LAN_OTHER_VERSION") % b.build
			row.disabled = true
		var address := b.address
		var port := b.game_port
		var map := b.map
		row.pressed.connect(func() -> void:
			var config := _config(MatchConfig.Mode.JOIN)
			config.address = address
			config.port = port
			config.spectate = _watch_toggle.button_pressed and not lobby
			if Maps.has(map):
				config.map = map
			_go(LOBBY if lobby else MATCH, config))
	for g: Dictionary in _online_games:
		var lobby: bool = g.get("state", "") == "lobby"
		var row := _game_row("online", str(g.get("name", g.code)), str(g.get("mode", "ffa")),
				str(g.get("map", "")), int(g.get("players", 0)), int(g.get("max", 0)), lobby)
		var host_id: String = g.host_id
		var code: String = g.code
		var map := str(g.get("map", ""))
		row.pressed.connect(func() -> void:
			var config := _config(MatchConfig.Mode.JOIN)
			config.online = true
			config.online_code = code
			config.online_host = host_id
			config.spectate = _watch_toggle.button_pressed and not lobby
			if Maps.has(map):
				config.map = map
			_go(LOBBY if lobby else MATCH, config))


## A game card over its map's picture: "Name's game · 2/8" above
## "LAN · In lobby · Mode · Map"; green while in the lobby, orange playing.
func _game_row(kind: String, title: String, mode: String, map: String, players: int, max_players: int,
		lobby: bool) -> MenuTile:
	var map_name := tr(Maps.LIST[map].name) if Maps.has(map) else map
	var mode_name := tr(GameMode.NAME_KEYS[GameMode.from_id(mode)])
	var heading := title + ("  ·  %d/%d" % [players, max_players] if max_players > 0 else "")
	var details := " · ".join(PackedStringArray([tr("MENU_TAG_LAN" if kind == "lan" else "MENU_TAG_ONLINE"),
			tr("MENU_IN_LOBBY" if lobby else "MENU_IN_MATCH"), mode_name, map_name]))
	var thumb: Texture2D = load(Maps.LIST[map].thumb) if Maps.has(map) and Maps.LIST[map].has("thumb") else null
	var row := MenuTile.make(heading, details, kind, thumb)
	row.set_meta("ui_key", heading + " · " + details)
	row.accent = UiStyle.GOOD if lobby else UiStyle.WARN
	row.custom_minimum_size.y = 96
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_list.add_child(row)
	return row


## Address (optionally :port) or invite code from the field: into the
## host's lobby (or its match, if it already started).
func _join_manual() -> void:
	var config := _config(MatchConfig.Mode.JOIN)
	config.spectate = _watch_toggle.button_pressed
	var code := Online.parse_code(_address_edit.text)
	if not code.is_empty() and Online.available():
		config.online = true
		config.online_code = code
		Settings.set_value("profile", "last_address", code)
	else:
		var address := _address_edit.text.strip_edges()
		var colon := address.rfind(":")
		if colon > 0 and address.count(":") == 1 and address.substr(colon + 1).is_valid_int():
			config.port = clampi(address.substr(colon + 1).to_int(), 1, 65535)
			address = address.left(colon)
		# Browsers resolve names themselves (the page's own host is prefilled).
		var web_name := Platform.is_web() and not address.is_empty() and not " " in address
		if not address.is_valid_ip_address() and not web_name:
			_show_status(tr("MENU_BAD_ADDRESS"))
			return
		config.address = address
		Settings.set_value("profile", "last_address", address)
	Settings.save_settings()
	_go(LOBBY, config)


# --- Starting ---

## `watch`: spectator mode, bots only (a bot fills our place).
func _start_solo(watch: bool = false) -> void:
	var config := _config(MatchConfig.Mode.OFFLINE, MatchConfig.profile_bots())
	config.bots = config.clamp_bots(config.bots, false)
	config.spectate = watch or Platform.user_args.has("--spectate")
	_go(MATCH, config)


func _host_lobby(online: bool) -> void:
	var config := _config(MatchConfig.Mode.HOST, MatchConfig.profile_bots())
	config.online = online
	config.bots = config.clamp_bots(config.bots, true)
	_go(LOBBY, config)


## Dev quick launch: a hosted match without a lobby (soak tests).
func _host_match(online: bool) -> void:
	var config := _config(MatchConfig.Mode.HOST, MatchConfig.profile_bots())
	config.online = online
	config.bots = config.clamp_bots(config.bots, true)
	_go(MATCH, config)


func _config(mode: int, bots: int = 0) -> MatchConfig:
	return MatchConfig.make(mode, _player_name(), bots)


func _go(scene: String, config: MatchConfig) -> void:
	MatchConfig.pending = config
	if scene == MATCH:
		LoadingCover.change_scene(get_tree(), scene)
	else:
		get_tree().change_scene_to_file(scene)
