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
const CONNECT_TIMEOUT_S := 15.0
## Back from a match, the host reopens its lobby on the same socket while the
## old connection may still be closing (seen online: one attempt in ~5
## failed), so the reconnect is retried before giving up.
const HANDOVER_ATTEMPTS := 5
const HANDOVER_RETRY_S := 2.0

var config: MatchConfig
var session := LobbySession.new()
var _host: bool = false
var _leaving: bool = false
var _joined: bool = false  ## client: the first LOBBY arrived
var _starting: bool = false
var _attempt: int = 0
var _subtitle: Label
var _code_caption: Label
var _code: Label
var _map_tiles: Array[MenuTile] = []
var _mode_chips: HBoxContainer
var _duration_chips: HBoxContainer
var _slots: VBoxContainer
var _count: Label
var _start_button: Button
var _waiting: Label
var _dots: float = 0.0


func _ready() -> void:
	config = MatchConfig.pending if MatchConfig.pending != null else MatchConfig.make(MatchConfig.Mode.HOST, "Player")
	MatchConfig.pending = null
	_host = config.mode == MatchConfig.Mode.HOST
	_build_ui()
	_add_session()
	if _host:
		await _open()
	else:
		await _connect()
	_refresh()


func _add_session() -> void:
	session.name = "Lobby"
	add_child(session)
	session.changed.connect(_refresh)
	session.started.connect(_on_started)
	session.closed.connect(_on_closed)
	session.in_match.connect(_on_in_match)


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
		# Back from a match: the online game (and its code) is still open.
		var hosted: Dictionary = {"code": Online.hosting_code}
		if Online.hosting_code.is_empty():
			hosted = await Online.host(config.player_name, max_players, _online_info())
		else:
			hosted.merge(Online.serve())
			Online.update_info(_online_info())
		if hosted.has("error"):
			_fail(tr("NET_ONLINE_ERROR") % hosted.error)
			return
		err = session.host(config.player_name, max_players, -1, hosted.peer)
		_subtitle.text = tr("LOBBY_SHARE_CODE")
		_code_caption.text = tr("PAUSE_INVITE_CODE")
		_code.text = hosted.code
		Platform.perf_log("LOBBY hosting online with invite code %s" % hosted.code)
	else:
		err = session.host(config.player_name, max_players, config.port)
		_subtitle.text = tr("LOBBY_LAN_HINT")
		_code_caption.text = tr("LOBBY_LAN_CAPTION")
		_code.text = Discovery.lan_addresses()[0]
		var advertiser := Discovery.Advertiser.new()
		advertiser.beacon_source = func() -> Discovery.Beacon:
			return session.beacon(tr("NET_GAME_OF") % config.player_name, config.port)
		add_child(advertiser)
		Platform.perf_log("LOBBY hosting on port %d" % config.port)
	if err != OK:
		_fail(tr("NET_HOST_ERROR") % [config.port, error_string(err)])


## Client: connects by address, invite code or known online host.
func _connect() -> void:
	if config.from_lobby and _attempt == 0:  # back from a match: the host reopens its lobby
		_subtitle.text = tr("LOBBY_CONNECTING")
		await get_tree().create_timer(1.5).timeout
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
	var attempt := _attempt
	get_tree().create_timer(CONNECT_TIMEOUT_S).timeout.connect(func() -> void:
		# An online connection can hang instead of failing (seen when Epic's
		# services stalled for a few seconds): handled like a failure.
		if not _joined and not _leaving and attempt == _attempt:
			_on_closed("connection failed"))


func _online_info() -> Dictionary:
	return {"name": tr("NET_GAME_OF") % config.player_name, "map": session.map_id,
			"mode": GameMode.IDS[session.game_mode], "players": maxi(session.members.size(), 1),
			"max": session.max_players, "state": "lobby"}


func _refresh() -> void:
	if not _host and not session.members.is_empty() and not _joined:
		_joined = true
		_subtitle.text = tr("LOBBY_JOINED") % _host_name()
		Platform.perf_log("LOBBY joined %s's lobby" % _host_name())
	for i in _map_tiles.size():
		_map_tiles[i].selected = Maps.PLAYABLE[i] == session.map_id
	MenuKit.select_chip(_mode_chips, session.game_mode)
	MenuKit.select_chip(_duration_chips, LobbySession.DURATIONS.find(session.minutes))
	_fill_slots()
	# Unknown until the host's first update arrives.
	_count.text = tr("LOBBY_PLAYERS") % [session.members.size(), session.max_players] \
			if not session.members.is_empty() else ""
	_start_button.disabled = session.members.is_empty() or _starting
	if _host and config.online:
		Online.update_info(_online_info())
	if _host and Platform.get_user_arg("--autostart").is_valid_int() \
			and session.members.size() >= Platform.get_user_arg("--autostart").to_int():
		_start.call_deferred()


## One row per player who has joined.
func _fill_slots() -> void:
	for child in _slots.get_children():
		child.queue_free()
	var me_seen := false
	for i in session.members.size():
		var slot := PanelContainer.new()
		slot.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.09, 0.14, 0.85),
				Color(UiStyle.ACCENT, 0.25), 1, UiStyle.SKEW, 12, 4))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		slot.add_child(row)
		_slots.add_child(slot)
		var m: Dictionary = session.members[i]
		# Names aren't unique; the host is us when hosting, else our first match.
		var me: bool = (_host and m.host) or (not _host and not m.host and not me_seen and m.name == config.player_name)
		me_seen = me_seen or me
		var initial := UiStyle.label(m.name.left(1).to_upper(), &"BadgeLabel", HORIZONTAL_ALIGNMENT_CENTER)
		initial.add_theme_font_size_override("font_size", 20)
		initial.custom_minimum_size = Vector2(36, 30)
		row.add_child(initial)
		var name_label := UiStyle.label(m.name)
		name_label.add_theme_font_override("font", UiStyle.font_display_bold)
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if me:
			name_label.add_theme_color_override("font_color", UiStyle.ACCENT)
		row.add_child(name_label)
		var tags := PackedStringArray()
		if m.host:
			tags.append(tr("LOBBY_HOST_TAG"))
		if me:
			tags.append(tr("LOBBY_YOU_TAG"))
		var tag := UiStyle.label(" · ".join(tags), &"DimLabel")
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(tag)


func _process(delta: float) -> void:
	# "Waiting for the host to start…" with moving dots.
	if not _host and _joined and not _leaving and not _starting:
		_dots += delta * 2.5
		_waiting.text = tr("LOBBY_WAITING_FOR_HOST").trim_suffix("…") + ".".repeat(1 + int(_dots) % 3)


func _host_name() -> String:
	for m: Dictionary in session.members:
		if m.host:
			return m.name
	return "?"


# --- Host settings ---

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
	_starting = true
	_waiting.text = tr("LOADING")
	if _host:
		# Let START reach everyone before the lobby's connections close (the
		# members leave once they have it; a browser polls less often, and a
		# close arriving with START would win); the match then listens on the
		# same port or online socket.
		var waited := 0.0
		while waited < 0.5 or (session.members.size() > 1 and waited < 3.0):
			await get_tree().create_timer(0.1).timeout
			waited += 0.1
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
	if reason == "connection failed" and config.from_lobby and not _joined and _attempt + 1 < HANDOVER_ATTEMPTS:
		_attempt += 1
		Platform.perf_log("LOBBY reconnect attempt %d failed, retrying" % _attempt)
		session.queue_free()
		session = LobbySession.new()
		_add_session()
		await get_tree().create_timer(HANDOVER_RETRY_S).timeout
		if not _leaving:
			_connect()
		return
	match reason:
		"disconnected": _fail("LOBBY_HOST_LEFT")
		"connection failed": _fail("NET_ONLINE_UNREACHABLE" if config.online else "NET_UNREACHABLE")
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


# --- Layout: header with the invite code; map, mode and length on the left,
# the players' places on the right; Start at the bottom ---

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := Node3D.new()
	backdrop.set_script(load("res://ui/main_menu/menu_backdrop.gd"))
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(UiStyle.BG, 0.66)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# The invite code (or LAN address), big, at the top right.
	var code_box := VBoxContainer.new()
	code_box.add_theme_constant_override("separation", 0)
	_code_caption = MenuKit.section("")
	_code_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	code_box.add_child(_code_caption)
	_code = UiStyle.label("", &"HeaderLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_code.add_theme_color_override("font_color", UiStyle.ACCENT)
	_code.add_theme_font_size_override("font_size", 44)
	code_box.add_child(_code)
	root.add_child(MenuKit.header("LOBBY_TITLE", "LOBBY_LEAVE", _back, code_box))
	_subtitle = UiStyle.label("", &"DimLabel")
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_subtitle)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	root.add_child(columns)
	var settings := VBoxContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.size_flags_stretch_ratio = 1.7
	settings.add_theme_constant_override("separation", 12)
	columns.add_child(settings)
	settings.add_child(MenuKit.section("MENU_SECTION_MAP" if _host else "LOBBY_HOST_CHOOSES"))
	var maps := HBoxContainer.new()
	maps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	maps.add_theme_constant_override("separation", 14)
	settings.add_child(maps)
	for id: String in Maps.PLAYABLE:
		var tile := MenuTile.make(Maps.LIST[id].name, Maps.LIST[id].blurb, "", load(Maps.LIST[id].thumb))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.read_only = not _host
		tile.pressed.connect(func() -> void: _apply(id, session.game_mode, session.minutes))
		maps.add_child(tile)
		_map_tiles.append(tile)
	# One row each: side by side, the chips don't fit the column in longer
	# languages and would push the players list off screen.
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	settings.add_child(options)
	_mode_chips = _option(options, "MENU_SECTION_MODE", GameMode.NAME_KEYS,
			func(i: int) -> void: _apply(session.map_id, i, session.minutes))
	_duration_chips = _option(options, "MENU_SECTION_DURATION", MenuKit.duration_labels(),
			func(i: int) -> void: _apply(session.map_id, session.game_mode, LobbySession.DURATIONS[i]))

	var players := PanelContainer.new()
	players.theme_type_variation = &"CardPanel"
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(players)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	players.add_child(list)
	var heading := HBoxContainer.new()
	list.add_child(heading)
	var title := MenuKit.section("LOBBY_PLAYERS_TITLE")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_count = MenuKit.section("")
	heading.add_child(_count)
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 6)
	list.add_child(_slots)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)
	_waiting = UiStyle.label("LOBBY_HOST_BOTS_HINT" if _host else "", &"DimLabel")
	_waiting.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(_waiting)
	_start_button = UiStyle.menu_button("LOBBY_START", &"PrimaryButton")
	_start_button.custom_minimum_size = Vector2(320, 64)
	_start_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_button.pressed.connect(_start)
	_start_button.visible = _host
	_start_button.disabled = true
	actions.add_child(_start_button)
	if _host:
		_start_button.grab_focus.call_deferred()


## A captioned chip row; read-only for players.
func _option(parent: Control, caption: String, labels: Array, on_select: Callable) -> HBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	box.add_child(MenuKit.section(caption))
	var chips := MenuKit.chips(labels, 0, on_select, not _host)
	box.add_child(chips)
	return chips
