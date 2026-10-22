extends Control
## Main menu. Every visible string is a translation key (PLAN §3.16).
##
## Nested pages: Play → Single player (map, mode, duration) or Multiplayer →
## Host (LAN or online) opens a lobby, Join lists LAN and online games and
## takes an address or invite code. Back and Escape go up one page.
##
## Quick test launches (desktop): `-- --play`, `-- --host` (straight into a
## hosted match), `-- --lobby [--online]` (a hosted lobby), `-- --join
## <address or code>` and `-- --name <name>` skip the menu;
## `--open-settings` / `--open-profile` open those screens (`--open-stats`:
## the profile's Stats tab).

const MATCH := "res://game/match.tscn"
const LOBBY := "res://ui/lobby/lobby.tscn"
const OFFLINE_DUMMIES := 3
const HOST_DUMMIES := 2
const ONLINE_LIST_INTERVAL_S := 5.0

enum Page { MAIN, PLAY, SOLO, MULTI, HOST, JOIN }
const PARENT := {Page.PLAY: Page.MAIN, Page.SOLO: Page.PLAY, Page.MULTI: Page.PLAY, Page.HOST: Page.MULTI,
		Page.JOIN: Page.MULTI}

@onready var _version_label: Label = %VersionLabel
@onready var _storage_warning: Label = %StorageWarning
@onready var _quit_button: Button = %QuitButton
@onready var _play_button: Button = %PlayButton
@onready var _join_panel: Control = %JoinPanel
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _connect_button: Button = %ConnectButton
@onready var _back_button: Button = %BackButton
@onready var _name_edit: LineEdit = %NameEdit
@onready var _status: Label = %StatusLabel
@onready var _games_label: Label = %GamesLabel
@onready var _game_list: VBoxContainer = %GameList

static var _quick_launched: bool = false
var _page: int = Page.MAIN
var _pages: Dictionary = {}  ## Page -> Control
var _first: Dictionary = {}  ## Page -> the button focused on entry
var _opener: Dictionary = {}  ## Page -> the button that opens it (focused on Back)
var _map_button: Button
var _mode_button: Button
var _duration_button: Button
var _browser: Discovery.Browser
var _online_games: Array = []
var _online_error: String = ""
var _listing: bool = false
var _profile_panel := ProfilePanel.new()
var _settings := SettingsMenu.new()


func _ready() -> void:
	var music := AudioStreamPlayer.new()
	music.stream = load("res://audio/generated/menu_theme.wav")
	music.bus = "Music"
	music.volume_db = -8.0
	add_child(music)
	music.play()
	_version_label.text = BuildInfo.display_string()
	_storage_warning.visible = not Platform.storage_available
	# Browsers and mobile apps are closed by the OS, not by an in-game button.
	_quit_button.visible = not (Platform.is_web() or Platform.is_mobile())
	_quit_button.pressed.connect(get_tree().quit)
	_name_edit.text = Platform.get_user_arg("--name", MatchConfig.profile_name())
	var last: Variant = Settings.get_value("profile", "last_address")
	_address_edit.text = last if last is String else ""
	_build_pages()
	_back_button.pressed.connect(_go_back)
	_connect_button.pressed.connect(_join_manual)
	_address_edit.text_submitted.connect(func(_t: String) -> void: _join_manual())
	add_child(_profile_panel)
	add_child(_settings)
	%SettingsButton.pressed.connect(_settings.open)
	_settings.closed.connect(func() -> void: %SettingsButton.grab_focus())
	_profile_panel.closed.connect(func() -> void:
		_name_edit.text = MatchConfig.profile_name()
		%ProfileButton.grab_focus())
	%ProfileButton.pressed.connect(func() -> void: _profile_panel.open(_name_edit.text))
	if not MatchConfig.last_error.is_empty():
		_status.text = tr(MatchConfig.last_error)
		_status.visible = true
		MatchConfig.last_error = ""
	_offer_rejoin()
	_update_player_card()
	Profile.changed.connect(_update_player_card)
	_play_button.grab_focus()
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
		_profile_panel.open(_name_edit.text)
	elif Platform.user_args.has("--open-stats"):
		_profile_panel.open(_name_edit.text, ProfilePanel.Tab.STATS)
	elif Platform.user_args.has("--play"):
		_start_solo.call_deferred()
	elif Platform.user_args.has("--host"):
		_host_match.call_deferred(Platform.user_args.has("--online"))
	elif Platform.user_args.has("--lobby"):
		_host_lobby.call_deferred(Platform.user_args.has("--online"))
	elif Platform.user_args.has("--join") and not Platform.user_args.has("--test-clients"):
		_address_edit.text = Platform.get_user_arg("--join", "127.0.0.1")
		_join_manual.call_deferred()


# --- Pages ---

## Builds the sub-pages (the main page and the join panel are in the scene).
func _build_pages() -> void:
	_pages[Page.MAIN] = %MainPage
	_pages[Page.JOIN] = _join_panel
	_first[Page.MAIN] = _play_button
	_play_button.pressed.connect(_show.bind(Page.PLAY))
	_opener[Page.PLAY] = _play_button
	# Web builds can't host or use ENet (PLAN §3.20); they get a WebSocket transport later.
	var play := _page_box(Page.PLAY, "MENU_PLAY")
	_opener[Page.SOLO] = _add_button(play, Page.PLAY, "MENU_SINGLE_PLAYER", _show.bind(Page.SOLO), &"PrimaryButton")
	_opener[Page.MULTI] = _add_button(play, Page.PLAY, "MENU_MULTIPLAYER", _show.bind(Page.MULTI))
	_opener[Page.MULTI].visible = not Platform.is_web()
	_add_button(play, Page.PLAY, "MENU_BACK", _go_back, &"GhostButton")

	var solo := _page_box(Page.SOLO, "MENU_SINGLE_PLAYER")
	_map_button = _add_button(solo, Page.SOLO, "", _next_map)
	_mode_button = _add_button(solo, Page.SOLO, "", _next_mode)
	_duration_button = _add_button(solo, Page.SOLO, "", _next_duration)
	_add_button(solo, Page.SOLO, "MENU_START", _start_solo, &"PrimaryButton")
	_add_button(solo, Page.SOLO, "MENU_BACK", _go_back, &"GhostButton")
	_first[Page.SOLO] = solo.get_child(solo.get_child_count() - 2)  # Start
	_update_solo_buttons()

	var multi := _page_box(Page.MULTI, "MENU_MULTIPLAYER")
	# Internet play (decision 0005) only where the EOS backend is available;
	# elsewhere Host opens a LAN lobby directly.
	_opener[Page.HOST] = _add_button(multi, Page.MULTI, "MENU_HOST",
			_show.bind(Page.HOST) if Online.available() else _host_lobby.bind(false), &"PrimaryButton")
	_opener[Page.JOIN] = _add_button(multi, Page.MULTI, "MENU_JOIN", _show.bind(Page.JOIN))
	_add_button(multi, Page.MULTI, "MENU_BACK", _go_back, &"GhostButton")

	var host := _page_box(Page.HOST, "MENU_HOST")
	_add_button(host, Page.HOST, "MENU_HOST_LAN", _host_lobby.bind(false), &"PrimaryButton")
	_add_button(host, Page.HOST, "MENU_HOST_ONLINE", _host_lobby.bind(true))
	_add_button(host, Page.HOST, "MENU_BACK", _go_back, &"GhostButton")
	_first[Page.JOIN] = _address_edit
	_show(Page.MAIN)


## A page: a column under the player card with a small heading.
func _page_box(page: int, heading: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	box.add_child(UiStyle.label(heading, &"DimLabel"))
	%MainPage.add_sibling(box)
	_pages[page] = box
	return box


func _add_button(box: VBoxContainer, page: int, text: String, action: Callable, kind: StringName = &"") -> Button:
	var b := UiStyle.menu_button(text, kind)
	b.pressed.connect(action)
	box.add_child(b)
	if not _first.has(page):
		_first[page] = b
	return b


func _show(page: int) -> void:
	_page = page
	for p: int in _pages:
		(_pages[p] as Control).visible = p == page
	_status.visible = _status.visible and page != Page.JOIN
	_set_browsing(page == Page.JOIN)
	if page == Page.SOLO:
		_update_solo_buttons()
	(_first[page] as Control).grab_focus.call_deferred()


func _go_back() -> void:
	if _page == Page.MAIN:
		return
	var from := _page
	_show(PARENT[from])
	if _opener.has(from):  # focus the button that led here
		(_opener[from] as Control).grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _page != Page.MAIN and not _settings.visible \
			and not _profile_panel.visible:
		get_viewport().set_input_as_handled()
		_go_back()


# --- Single player: map, mode and duration (saved for next time) ---

func _next_map() -> void:
	var i := Maps.PLAYABLE.find(Maps.from_args(Settings.get_value("profile", "map")))
	_save_choice("map", Maps.PLAYABLE[(i + 1) % Maps.PLAYABLE.size()])


func _next_mode() -> void:
	var i := GameMode.from_id(str(Settings.get_value("profile", "mode")))
	_save_choice("mode", GameMode.IDS[(i + 1) % GameMode.IDS.size()])


func _next_duration() -> void:
	var i := LobbySession.DURATIONS.find(MatchConfig.make(MatchConfig.Mode.OFFLINE, "").minutes)
	_save_choice("minutes", LobbySession.DURATIONS[(i + 1) % LobbySession.DURATIONS.size()])


func _save_choice(key: String, value: Variant) -> void:
	Settings.set_value("profile", key, value)
	Settings.save_settings()
	_update_solo_buttons()


func _update_solo_buttons() -> void:
	var c := MatchConfig.make(MatchConfig.Mode.OFFLINE, "")
	_map_button.text = tr("MENU_MAP") % tr(Maps.LIST[c.map].name)
	_mode_button.text = tr("MENU_MODE") % tr(GameMode.NAME_KEYS[c.game_mode])
	_duration_button.text = tr("MENU_DURATION") % c.minutes


## After a match was lost to the network, a button rejoins it with our
## token while the server keeps our place (PLAN §3.4: 60 s).
func _offer_rejoin() -> void:
	var offer := MatchConfig.open_rejoin()
	if offer.is_empty():
		return
	var button := UiStyle.menu_button("MENU_REJOIN", &"PrimaryButton")
	button.custom_minimum_size.y = 50
	_status.get_parent().add_child(button)
	_status.get_parent().move_child(button, _status.get_index() + 1)
	button.pressed.connect(func() -> void:
		var config: MatchConfig = offer.config
		config.reconnect_token = offer.token
		config.map_retried = false
		config.from_lobby = false
		MatchConfig.rejoin = {}
		MatchConfig.pending = config
		get_tree().change_scene_to_file(MATCH))
	get_tree().create_timer((int(offer.until_ms) - Time.get_ticks_msec()) / 1000.0).timeout.connect(func() -> void:
		if is_instance_valid(button):
			button.queue_free())
	button.grab_focus.call_deferred()


## Level badge and XP progress from the local profile (PLAN §3.13).
func _update_player_card() -> void:
	var lv := ProfileData.level_for(Profile.data.xp())
	%LevelBadge.text = str(lv.level)
	%XpBar.max_value = lv.needed
	%XpBar.value = lv.into
	%XpLabel.text = tr("MENU_XP_PROGRESS") % [lv.level, lv.into, lv.needed]


## Entrance: the column slides in from the left and its rows fade in one
## after another.
func _animate_in() -> void:
	var margin: MarginContainer = $Margin
	var tween := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(v: float) -> void: margin.add_theme_constant_override("margin_left", roundi(v)), 24.0, 72.0, 0.6)
	%TitleBar.custom_minimum_size.x = 0.0
	tween.tween_property(%TitleBar, "custom_minimum_size:x", 96.0, 0.7).set_delay(0.2)
	var i := 0
	for row: Control in %Center.get_children():
		row.modulate.a = 0.0
		tween.tween_property(row, "modulate:a", 1.0, 0.35).set_delay(0.05 + i * 0.04)
		i += 1


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

## While the join page is open, LAN beacons are heard and online games are
## listed every few seconds (PLAN §3.6). The page replaces the menu column,
## so on phones the address field sits above the on-screen keyboard.
func _set_browsing(on: bool) -> void:
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
		var listed: Dictionary = await Online.list_games(ServerSession.sanitize_name(_name_edit.text))
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
		_games_label.text = tr("MENU_GAMES_SEARCHING") if count == 0 else tr("MENU_GAMES")
	if not _online_error.is_empty():
		_games_label.text += "\n" + tr("NET_ONLINE_ERROR") % _online_error
	for b: Discovery.Beacon in lan:
		var row := _game_row("MENU_TAG_LAN", b.name, b.mode, b.map, b.combatants, b.max_combatants,
				b.flags & Discovery.FLAG_LOBBY != 0)
		if not b.compatible():
			row.text += " · " + tr("MENU_LAN_OTHER_VERSION") % b.build
			row.disabled = true
		var address := b.address
		var port := b.game_port
		var lobby := b.flags & Discovery.FLAG_LOBBY != 0
		var map := b.map
		row.pressed.connect(func() -> void:
			var config := _config(MatchConfig.Mode.JOIN)
			config.address = address
			config.port = port
			if Maps.has(map):
				config.map = map
			_go(LOBBY if lobby else MATCH, config))
	for g: Dictionary in _online_games:
		var lobby: bool = g.get("state", "") == "lobby"
		var row := _game_row("MENU_TAG_ONLINE", str(g.get("name", g.code)), str(g.get("mode", "ffa")),
				str(g.get("map", "")), int(g.get("players", 0)), int(g.get("max", 0)), lobby)
		var host_id: String = g.host_id
		var code: String = g.code
		var map := str(g.get("map", ""))
		row.pressed.connect(func() -> void:
			var config := _config(MatchConfig.Mode.JOIN)
			config.online = true
			config.online_code = code
			config.online_host = host_id
			if Maps.has(map):
				config.map = map
			_go(LOBBY if lobby else MATCH, config))


## A browser row, two lines: "Name's game · 2/8 · In lobby" over
## "LAN · Mode · Map".
func _game_row(tag: String, title: String, mode: String, map: String, players: int, max_players: int,
		lobby: bool) -> Button:
	var row := Button.new()
	var map_name := tr(Maps.LIST[map].name) if Maps.has(map) else map
	var mode_name := tr(GameMode.NAME_KEYS[GameMode.from_id(mode)])
	var top := PackedStringArray([title])
	if max_players > 0:
		top.append("%d/%d" % [players, max_players])
	top.append(tr("MENU_IN_LOBBY" if lobby else "MENU_IN_MATCH"))
	row.text = " · ".join(top) + "\n" + " · ".join(PackedStringArray([tr(tag), mode_name, map_name]))
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_game_list.add_child(row)
	return row


## Address (optionally :port) or invite code from the field: into the
## host's lobby (or its match, if it already started).
func _join_manual() -> void:
	var config := _config(MatchConfig.Mode.JOIN)
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
		if not address.is_valid_ip_address():
			_status.text = tr("MENU_BAD_ADDRESS")
			_status.visible = true
			return
		config.address = address
		Settings.set_value("profile", "last_address", address)
	Settings.save_settings()
	_go(LOBBY, config)


# --- Starting ---

func _start_solo() -> void:
	_go(MATCH, _config(MatchConfig.Mode.OFFLINE, OFFLINE_DUMMIES))


func _host_lobby(online: bool) -> void:
	var config := _config(MatchConfig.Mode.HOST, HOST_DUMMIES)
	config.online = online
	_go(LOBBY, config)


## Dev quick launch: a hosted match without a lobby (soak tests).
func _host_match(online: bool) -> void:
	var config := _config(MatchConfig.Mode.HOST, HOST_DUMMIES)
	config.online = online
	_go(MATCH, config)


## A config for this player; a typed name is saved (a dev `--name` is for
## this session only).
func _config(mode: int, bots: int = 0) -> MatchConfig:
	var player_name := ServerSession.sanitize_name(_name_edit.text)
	if player_name != MatchConfig.profile_name() and not Platform.user_args.has("--name"):
		Settings.set_value("profile", "name", player_name)
		Settings.save_settings()
	return MatchConfig.make(mode, player_name, bots)


func _go(scene: String, config: MatchConfig) -> void:
	MatchConfig.pending = config
	get_tree().change_scene_to_file(scene)
