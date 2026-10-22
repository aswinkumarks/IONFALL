extends Control
## Multiplayer lobby: the host picks map, mode and duration and sees who has
## joined; players see the same, read-only. The host's Start sends everyone
## into the match (LobbySession). Reached from the menu with
## `MatchConfig.pending` in HOST or JOIN mode (LAN address, invite code, or
## an online host from the browser).
##
## Dev: `-- --lobby [--online] --autostart N` hosts and starts once N
## players are in.

const MATCH := "res://game/match.tscn"
const MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
const CONNECT_TIMEOUT_S := 20.0

var config: MatchConfig
var session := LobbySession.new()
var _host: bool = false
var _leaving: bool = false
var _joined: bool = false  ## client: the first LOBBY arrived
var _starting: bool = false
var _subtitle: Label
var _map_button: Button
var _mode_button: Button
var _duration_button: Button
var _players: VBoxContainer
var _count: Label
var _start_button: Button
var _waiting: Label
var _status: Label


func _ready() -> void:
	config = MatchConfig.pending if MatchConfig.pending != null else MatchConfig.make(MatchConfig.Mode.HOST, "Player")
	MatchConfig.pending = null
	_host = config.mode == MatchConfig.Mode.HOST
	_build_ui()
	session.name = "Lobby"
	add_child(session)
	session.changed.connect(_refresh)
	session.started.connect(_on_started)
	session.closed.connect(_on_closed)
	session.in_match.connect(_on_in_match)
	if _host:
		await _open()
	else:
		await _connect()
	_refresh()


func _exit_tree() -> void:
	# Leaving to the menu closes the online game; into the match keeps it.
	if _host and config.online and _leaving:
		Online.stop_hosting()


## Host: listens on the LAN port or opens an online game with an invite code.
func _open() -> void:
	var max_players := config.max_combatants()
	session.configure(config.map, config.game_mode, config.minutes)
	var err := OK
	if config.online:
		_subtitle.text = tr("NET_ONLINE_SIGNING_IN")
		var hosted: Dictionary = await Online.host(config.player_name, max_players, _online_info())
		if hosted.has("error"):
			_fail(tr("NET_ONLINE_ERROR") % hosted.error)
			return
		err = session.host(config.player_name, max_players, -1, hosted.peer)
		_subtitle.text = tr("LOBBY_INVITE_CODE") % hosted.code
		Platform.perf_log("LOBBY hosting online with invite code %s" % hosted.code)
	else:
		err = session.host(config.player_name, max_players, config.port)
		_subtitle.text = tr("LOBBY_LAN") % ", ".join(Discovery.lan_addresses())
		var advertiser := Discovery.Advertiser.new()
		advertiser.beacon_source = func() -> Discovery.Beacon:
			return session.beacon(tr("NET_GAME_OF") % config.player_name, config.port)
		add_child(advertiser)
		Platform.perf_log("LOBBY hosting on port %d" % config.port)
	if err != OK:
		_fail(tr("NET_HOST_ERROR") % [config.port, error_string(err)])


## Client: connects by address, invite code or known online host.
func _connect() -> void:
	var peer: MultiplayerPeer = null
	if config.online:
		_subtitle.text = tr("NET_ONLINE_JOINING") % config.online_code if config.online_host.is_empty() \
				else tr("LOBBY_CONNECTING")
		var joined: Dictionary = await Online.connect_to(config.player_name, config.online_host) \
				if not config.online_host.is_empty() else await Online.join(config.player_name, config.online_code)
		if joined.has("error"):
			match joined.error:
				"not_found": _fail(tr("NET_ONLINE_NOT_FOUND") % config.online_code)
				"version": _fail("NET_ONLINE_VERSION")
				_: _fail(tr("NET_ONLINE_ERROR") % joined.error)
			return
		peer = joined.peer
		config.online_host = joined.host_id
	else:
		_subtitle.text = tr("NET_CONNECTING") % config.address
	var err := session.join(config.address, config.port, config.player_name, MatchConfig.profile_uuid(), peer)
	if err != OK:
		_fail(tr("NET_CONNECT_ERROR") % error_string(err))
		return
	get_tree().create_timer(CONNECT_TIMEOUT_S).timeout.connect(func() -> void:
		if not _joined and not _leaving:
			_fail("NET_UNREACHABLE"))


func _online_info() -> Dictionary:
	return {"name": tr("NET_GAME_OF") % config.player_name, "map": session.map_id,
			"mode": GameMode.IDS[session.game_mode], "players": maxi(session.members.size(), 1),
			"max": session.max_players, "state": "lobby"}


func _refresh() -> void:
	if not _host and not session.members.is_empty() and not _joined:
		_joined = true
		_subtitle.text = tr("LOBBY_JOINED") % _host_name()
		Platform.perf_log("LOBBY joined %s's lobby" % _host_name())
	_map_button.text = tr("MENU_MAP") % tr(Maps.LIST[session.map_id].name)
	_mode_button.text = tr("MENU_MODE") % tr(GameMode.NAME_KEYS[session.game_mode])
	_duration_button.text = tr("MENU_DURATION") % session.minutes
	if not _host:  # read-only: no "›" cycling hint
		for b: Button in [_map_button, _mode_button, _duration_button]:
			b.text = b.text.trim_suffix("›").strip_edges()
	for child in _players.get_children():
		child.queue_free()
	var me_seen := false
	for m: Dictionary in session.members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := UiStyle.label(m.name)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var tags := PackedStringArray()
		if m.host:
			tags.append(tr("LOBBY_HOST_TAG"))
		# Names aren't unique; the host is us when hosting, else our first match.
		if (_host and m.host) or (not _host and not m.host and not me_seen and m.name == config.player_name):
			me_seen = true
			tags.append(tr("LOBBY_YOU_TAG"))
			name_label.add_theme_color_override("font_color", UiStyle.ACCENT)
		row.add_child(UiStyle.label(" · ".join(tags), &"DimLabel"))
		_players.add_child(row)
	_count.text = tr("LOBBY_PLAYERS") % [session.members.size(), session.max_players]
	_start_button.disabled = session.members.is_empty() or _starting
	if _host and config.online:
		Online.update_info(_online_info())
	if _host and Platform.get_user_arg("--autostart").is_valid_int() \
			and session.members.size() >= Platform.get_user_arg("--autostart").to_int():
		_start.call_deferred()


func _host_name() -> String:
	for m: Dictionary in session.members:
		if m.host:
			return m.name
	return "?"


# --- Host settings ---

func _cycle_map() -> void:
	var i := Maps.PLAYABLE.find(session.map_id)
	_apply(Maps.PLAYABLE[(i + 1) % Maps.PLAYABLE.size()], session.game_mode, session.minutes)


func _cycle_mode() -> void:
	_apply(session.map_id, (session.game_mode + 1) % GameMode.IDS.size(), session.minutes)


func _cycle_duration() -> void:
	var i := LobbySession.DURATIONS.find(session.minutes)
	_apply(session.map_id, session.game_mode, LobbySession.DURATIONS[(i + 1) % LobbySession.DURATIONS.size()])


## Applies and remembers the host's choices (the next lobby starts with them).
func _apply(map_id: String, mode: int, minutes: int) -> void:
	session.configure(map_id, mode, minutes)
	Settings.set_value("profile", "map", session.map_id)
	Settings.set_value("profile", "mode", GameMode.IDS[session.game_mode])
	Settings.set_value("profile", "minutes", session.minutes)
	Settings.save_settings()


func _start() -> void:
	if not _host or _leaving or _starting or session.members.is_empty():
		return
	_starting = true
	_start_button.disabled = true
	Platform.perf_log("LOBBY starting with %d players" % session.members.size())
	session.start()


# --- Into the match, or back to the menu ---

func _on_started(settings: Dictionary) -> void:
	config.map = settings.map
	config.game_mode = settings.mode
	config.minutes = settings.minutes
	config.from_lobby = true
	_waiting.text = tr("LOADING")
	if _host:
		# Let START reach everyone before the lobby's connections close; the
		# match then listens on the same port or online socket.
		await get_tree().create_timer(0.5).timeout
		session.leave()
		Online.update_info({"state": "playing"})
	_go(MATCH)


## The host was already playing when we connected: join the match.
func _on_in_match(map_id: String) -> void:
	Platform.perf_log("LOBBY the host is playing %s: joining the match" % map_id)
	if Maps.has(map_id):
		config.map = map_id
	_go(MATCH)


func _on_closed(reason: String) -> void:
	match reason:
		"disconnected": _fail("LOBBY_HOST_LEFT")
		"connection failed": _fail("NET_UNREACHABLE")
		_: _fail(reason)


func _fail(reason: String) -> void:
	if _leaving:
		return
	Platform.perf_log("LOBBY left: %s" % tr(reason))
	MatchConfig.last_error = reason
	_back()


func _back() -> void:
	_leaving = true
	session.leave()
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU)


func _go(scene: String) -> void:
	MatchConfig.pending = config
	get_tree().change_scene_to_file.call_deferred(scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


# --- Layout: header, settings card and players card side by side ---

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := Node3D.new()
	backdrop.set_script(load("res://ui/main_menu/menu_backdrop.gd"))
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(UiStyle.BG, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	root.add_child(UiStyle.label("LOBBY_TITLE", &"HeaderLabel"))
	_subtitle = UiStyle.label("", &"DimLabel")
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_subtitle)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	root.add_child(columns)
	var settings := _card(columns, "LOBBY_SETTINGS")
	_map_button = _setting(settings, _cycle_map)
	_mode_button = _setting(settings, _cycle_mode)
	_duration_button = _setting(settings, _cycle_duration)
	if not _host:
		settings.add_child(UiStyle.label("LOBBY_HOST_CHOOSES", &"DimLabel"))
	var players := _card(columns, "LOBBY_PLAYERS_TITLE")
	_count = UiStyle.label("", &"DimLabel")
	players.add_child(_count)
	_players = VBoxContainer.new()
	_players.add_theme_constant_override("separation", 8)
	players.add_child(_players)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)
	var leave := UiStyle.menu_button("LOBBY_LEAVE", &"GhostButton")
	leave.custom_minimum_size = Vector2(200, 52)
	leave.pressed.connect(_back)
	actions.add_child(leave)
	_waiting = UiStyle.label("LOBBY_WAITING_FOR_HOST", &"DimLabel")
	_waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(_waiting)
	_start_button = UiStyle.menu_button("LOBBY_START", &"PrimaryButton")
	_start_button.custom_minimum_size = Vector2(260, 52)
	_start_button.pressed.connect(_start)
	_start_button.visible = _host
	_start_button.disabled = true
	actions.add_child(_start_button)
	_waiting.text = "" if _host else tr("LOBBY_WAITING_FOR_HOST")
	_status = UiStyle.label("", &"DimLabel")
	root.add_child(_status)
	(_start_button if _host else leave).grab_focus.call_deferred()


func _card(parent: Control, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(UiStyle.label(title, &"DimLabel"))
	return box


## A setting row: the host cycles it, players only see it.
func _setting(parent: Control, cycle: Callable) -> Button:
	var b := UiStyle.menu_button("")
	b.custom_minimum_size.y = 50
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not _host
	b.pressed.connect(cycle)
	parent.add_child(b)
	return b
