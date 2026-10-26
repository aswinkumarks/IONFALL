extends Control
## Multiplayer lobby: the host picks map, mode and duration and sees who has
## joined; players see the same, read-only. In the team modes the players
## list shows the two teams, each with Join for whoever isn't on it; the host
## names the teams and picks their colours (Edit, by the team's name) and can
## remove a player (press Remove twice). The host's Start sends everyone
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
const KICK_CONFIRM_S := 3.0  ## the host's second press on Remove must come within this

var config: MatchConfig
var session := LobbySession.new()
var _host: bool = false
var _leaving: bool = false
var _to_match: bool = false  ## on the way into the match
var _joined: bool = false  ## client: the first LOBBY arrived
var _starting: bool = false
var _attempt: int = 0
var _subtitle: Label
var _code_caption: Label
var _code: Label
var _map_tiles: Array[MenuTile] = []
var _mode_chips: HBoxContainer
var _duration_chips: HBoxContainer
var _bot_stepper: Stepper
var _difficulty_chips: HBoxContainer
var _ff_chips: HBoxContainer
var _slots: VBoxContainer
var _players_card: Control
## Team modes: one card per team, edged in its colour, instead of _players_card.
var _team_cards: Array[PanelContainer] = []
var _team_heads: Array[HBoxContainer] = []
var _team_slots: Array[VBoxContainer] = []
var _ping_labels: Dictionary = {}  ## member id -> its ping Label
var _slots_key: String = ""  ## what the rows show, but the pings
var _count: Label
var _start_button: Button
var _waiting: Label
var _team_editor: Control
var _editing_team: int = 0
var _team_name_edit: LineEdit
var _swatches: HBoxContainer
var _swatch_pick: int = 0
var _dots: float = 0.0


func _ready() -> void:
	Settings.set_menu_mode(true)
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
	session.team_plan = config.team_plan
	session.host_uuid = MatchConfig.profile_uuid()
	session.team_names = config.team_names
	session.team_colors = config.team_colors
	session.configure(config.map, config.game_mode, config.minutes, config.bots, config.bot_difficulty,
			config.friendly_fire)
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
		var web_port := session.transport.host_web_port()
		if err == OK and web_port > 0:
			_subtitle.text += "\n" + tr("LOBBY_BROWSER_HINT") % web_port
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
	_bot_stepper.set_value(session.bots)
	MenuKit.select_chip(_difficulty_chips, session.bot_difficulty)
	MenuKit.select_chip(_ff_chips, 1 if session.friendly_fire else 0)
	# Co-op waves bring their own bots; friendly fire needs teams.
	if _host:
		_bot_stepper.set_enabled(session.game_mode != GameMode.WAVES)
		MenuKit.set_chips_enabled(_ff_chips, MatchConfig.friendly_fire_applies(session.game_mode))
	else:
		_bot_stepper.modulate.a = 1.0 if session.game_mode != GameMode.WAVES else 0.4
		_ff_chips.modulate.a = 1.0 if MatchConfig.friendly_fire_applies(session.game_mode) else 0.4
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


## One row per player who has joined; in the team modes, in their team's card.
## Only the pings changed (every second): just those labels.
func _fill_slots() -> void:
	var rows := session.members.map(func(m: Dictionary) -> Array: return [m.id, m.name, m.host, m.team])
	var key := str([rows, session.game_mode, session.team_names, session.team_colors, _starting])
	if key == _slots_key:
		for m: Dictionary in session.members:
			if _ping_labels.has(m.id):
				_set_ping(_ping_labels[m.id], m.get("ping", 0))
		return
	_slots_key = key
	_ping_labels.clear()
	for box: Control in [_slots] + _team_slots + _team_heads:
		for child in box.get_children():
			child.queue_free()
	var teams := LobbySession.has_teams(session.game_mode)
	_players_card.visible = not teams
	for card in _team_cards:
		card.visible = teams
	if not teams:
		for m: Dictionary in session.members:
			_add_slot(_slots, m)
		return
	var mine := session.team_of(session.my_id())
	for team in 2:
		var on_team := session.members.filter(func(m: Dictionary) -> bool: return m.team == team)
		var color := GameMode.team_color(team, session.team_colors)
		_team_cards[team].add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PANEL_LIGHT, color, 16))
		var heading := _team_heads[team]
		var shape := TextureRect.new()
		shape.texture = UiStyle.team_shape_texture(team, 20)
		shape.modulate = color
		shape.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		heading.add_child(shape)
		var title := MenuKit.section(tr("LOBBY_TEAM") % [GameMode.team_name(team, session.team_names).to_upper(),
				on_team.size(), session.team_cap()])
		title.add_theme_color_override("font_color", color)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(title)
		if _host:
			var edit := _chip("LOBBY_EDIT_TEAM")
			edit.disabled = _starting
			edit.pressed.connect(_open_team_editor.bind(team))
			heading.add_child(edit)
		if mine != team:
			var join := _chip("LOBBY_JOIN_TEAM")
			join.disabled = _starting or on_team.size() >= session.team_cap()
			join.pressed.connect(session.set_team.bind(session.my_id(), team))
			heading.add_child(join)
		for m: Dictionary in on_team:
			_add_slot(_team_slots[team], m, color)


func _chip(text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ChipButton"
	b.text = text
	b.custom_minimum_size.y = 40
	return b


## A player's row in `list`, outlined in its team's `color` (or the accent).
func _add_slot(list: VBoxContainer, m: Dictionary, color: Color = UiStyle.ACCENT) -> void:
	var slot := PanelContainer.new()
	slot.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.09, 0.14, 0.85),
			Color(color, 0.35), 1, UiStyle.SKEW, 12, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	slot.add_child(row)
	list.add_child(slot)
	var me: bool = m.id == session.my_id()
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
	if not m.host:
		var ping := UiStyle.label("", &"DimLabel")
		ping.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ping.custom_minimum_size.x = 64
		_set_ping(ping, m.get("ping", 0))
		_ping_labels[m.id] = ping
		row.add_child(ping)
	if _host and not m.host:
		row.add_child(_kick_button(m.id))


## A member's round trip to the host ("…" until measured): green when
## quick, amber, then red.
func _set_ping(l: Label, ms: int) -> void:
	l.text = tr("LOBBY_PING") % ms if ms > 0 else "…"
	l.add_theme_color_override("font_color", UiStyle.TEXT_DIM if ms <= 0
			else (UiStyle.GOOD if ms < 60 else (UiStyle.WARN if ms < 120 else UiStyle.DANGER)))


## Host: Remove, then Confirm within KICK_CONFIRM_S, removes player `id`.
func _kick_button(id: int) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"ChipButton"
	b.text = tr("LOBBY_KICK")
	b.disabled = _starting
	b.pressed.connect(func() -> void:
		if b.has_meta("armed"):
			session.kick(id)
			return
		b.set_meta("armed", true)
		b.text = tr("LOBBY_KICK_CONFIRM")
		for c: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			b.add_theme_color_override(c, UiStyle.DANGER)
		get_tree().create_timer(KICK_CONFIRM_S).timeout.connect(func() -> void:
			if is_instance_valid(b):
				b.remove_meta("armed")
				b.text = tr("LOBBY_KICK")
				for c: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
					b.remove_theme_color_override(c)))
	return b


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

## Applies and remembers the host's choices (the next lobby starts with
## them): `changes` holds any of map, mode, minutes, bots, bot_difficulty,
## friendly_fire; the rest stay as they are.
func _apply(changes: Dictionary) -> void:
	session.configure(changes.get("map", session.map_id), changes.get("mode", session.game_mode),
			changes.get("minutes", session.minutes), changes.get("bots", session.bots),
			changes.get("bot_difficulty", session.bot_difficulty), changes.get("friendly_fire", session.friendly_fire))
	Settings.set_value("profile", "map", session.map_id)
	Settings.set_value("profile", "mode", GameMode.IDS[session.game_mode])
	Settings.set_value("profile", "minutes", session.minutes)
	Settings.set_value("profile", "bots", session.bots)
	Settings.set_value("profile", "bot_difficulty", BotBrain.DIFFICULTY_IDS[session.bot_difficulty])
	Settings.set_value("profile", "friendly_fire", session.friendly_fire)
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
	config.bots = session.bots
	config.bot_difficulty = session.bot_difficulty
	config.friendly_fire = session.friendly_fire
	config.from_lobby = true
	config.team_names = session.team_names
	config.team_colors = session.team_colors
	if _host:
		config.team_plan = session.team_plan_now()
	config.spectate = false  # lobby members play; spectating is for games already playing
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
	if _leaving or _to_match:
		return
	Platform.perf_log("LOBBY left: %s" % tr(reason))
	MatchConfig.last_error = reason
	_back()


func _back() -> void:
	if _leaving or _to_match:
		return
	_leaving = true
	session.leave()
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU)


func _go(scene: String) -> void:
	if _to_match:
		return
	MatchConfig.pending = config
	_to_match = true  # the cover takes two frames to show; nothing may turn back now
	LoadingCover.change_scene(get_tree(), scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _team_editor.visible:
			_team_editor.visible = false
		else:
			_back()


# --- Host: a team's name and colour ---

func _open_team_editor(team: int) -> void:
	_editing_team = team
	_team_name_edit.text = session.team_names[team]
	_team_name_edit.placeholder_text = tr(GameMode.TEAM_KEYS[team])
	_swatch_pick = session.team_colors[team]
	_show_swatches()
	_team_editor.visible = true
	_team_name_edit.grab_focus()


## The palette, the current pick outlined; the other team's colour is taken.
func _show_swatches() -> void:
	var taken := session.team_colors[1 - _editing_team]
	for i in _swatches.get_child_count():
		var b := _swatches.get_child(i) as Button
		var c: Color = GameMode.TEAM_PALETTE[i]
		var border := Color.WHITE if i == _swatch_pick else Color(c, 0.0)
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			var fill := Color(c, 0.2) if i == taken else c
			b.add_theme_stylebox_override(state, UiStyle.box(fill, border if state != "focus" else Color.WHITE,
					3 if i == _swatch_pick or state == "focus" else 0, UiStyle.SKEW, 0, 0))
		b.disabled = i == taken


func _save_team() -> void:
	session.set_team_style(_editing_team, _team_name_edit.text, _swatch_pick)
	_team_editor.visible = false
	Settings.set_value("profile", "team_names", Array(session.team_names))
	Settings.set_value("profile", "team_colors", Array(session.team_colors))
	Settings.save_settings()


func _make_team_editor() -> Control:
	var parts := UiStyle.menu_overlay(520.0)
	var root: Control = parts[0]
	var box: VBoxContainer = parts[1]
	root.visible = false
	box.add_child(UiStyle.label("LOBBY_EDIT_TEAM_TITLE", &"HeaderLabel"))
	box.add_child(MenuKit.section("LOBBY_TEAM_NAME"))
	_team_name_edit = LineEdit.new()
	_team_name_edit.max_length = GameMode.MAX_TEAM_NAME
	_team_name_edit.custom_minimum_size.y = 52
	_team_name_edit.text_submitted.connect(func(_t: String) -> void: _save_team())
	box.add_child(_team_name_edit)
	box.add_child(MenuKit.section("LOBBY_TEAM_COLOUR"))
	_swatches = HBoxContainer.new()
	_swatches.add_theme_constant_override("separation", 8)
	box.add_child(_swatches)
	for i in GameMode.TEAM_PALETTE.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 44)
		b.pressed.connect(func() -> void:
			_swatch_pick = i
			_show_swatches())
		_swatches.add_child(b)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var save := UiStyle.menu_button("LOBBY_TEAM_SAVE", &"PrimaryButton")
	save.pressed.connect(_save_team)
	buttons.add_child(save)
	var cancel := UiStyle.menu_button("LOBBY_TEAM_CANCEL")
	cancel.pressed.connect(func() -> void: _team_editor.visible = false)
	buttons.add_child(cancel)
	return root


# --- Layout: header with the invite code; map, mode, length and bots on the left,
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
	maps.custom_minimum_size.y = 120  # room for the name and blurb with every option row below
	maps.add_theme_constant_override("separation", 14)
	settings.add_child(maps)
	for id: String in Maps.PLAYABLE:
		var tile := MenuTile.make(Maps.LIST[id].name, Maps.LIST[id].blurb, "", load(Maps.LIST[id].thumb))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.read_only = not _host
		tile.pressed.connect(func() -> void: _apply({"map": id}))
		maps.add_child(tile)
		_map_tiles.append(tile)
	# One row each: side by side, the chips don't fit the column in longer
	# languages and would push the players list off screen.
	var options := VBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	settings.add_child(options)
	_mode_chips = _option(options, "MENU_SECTION_MODE", GameMode.CHIP_KEYS,
			func(i: int) -> void: _apply({"mode": i}))
	# Match length and the bot count share a row, so every option fits a
	# 720 px screen.
	var length_row := HBoxContainer.new()
	length_row.add_theme_constant_override("separation", 24)
	options.add_child(length_row)
	_duration_chips = _option(length_row, "MENU_SECTION_DURATION", MenuKit.duration_labels(),
			func(i: int) -> void: _apply({"minutes": LobbySession.DURATIONS[i]}))
	# Members see the host's count; the host's cap is the limit.
	var bots_box := VBoxContainer.new()
	bots_box.add_theme_constant_override("separation", 8)
	length_row.add_child(bots_box)
	bots_box.add_child(MenuKit.section("MENU_SECTION_BOTS"))
	_bot_stepper = Stepper.new(0, config.max_bots() if _host else Protocol.MAX_PEERS - 1, config.bots, not _host)
	_bot_stepper.label_for = MenuKit.bot_label
	_bot_stepper.set_value(config.bots)
	_bot_stepper.changed.connect(func(n: int) -> void: _apply({"bots": n}))
	bots_box.add_child(_bot_stepper)
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", 24)
	options.add_child(bot_row)
	_difficulty_chips = _option(bot_row, "MENU_SECTION_BOT_DIFFICULTY", MenuKit.difficulty_labels(),
			func(i: int) -> void: _apply({"bot_difficulty": i}))
	_ff_chips = _option(bot_row, "MENU_SECTION_FRIENDLY_FIRE", ["MENU_OFF", "MENU_ON"],
			func(i: int) -> void: _apply({"friendly_fire": i == 1}))

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 12)
	columns.add_child(side)
	var players := PanelContainer.new()
	players.theme_type_variation = &"CardPanel"
	players.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(players)
	_players_card = players
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	players.add_child(list)
	var heading := HBoxContainer.new()
	list.add_child(heading)
	var title := MenuKit.section("LOBBY_PLAYERS_TITLE")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_count = MenuKit.section("")
	heading.add_child(_count)
	# Up to 16 players: the list scrolls rather than pushing the page down.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_child(scroll)
	_slots = VBoxContainer.new()
	_slots.add_theme_constant_override("separation", 6)
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_slots)
	for team in 2:
		var card := PanelContainer.new()
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.visible = false
		side.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		card.add_child(box)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		box.add_child(head)
		var team_scroll := ScrollContainer.new()
		team_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		team_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(team_scroll)
		var team_slots := VBoxContainer.new()
		team_slots.add_theme_constant_override("separation", 6)
		team_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		team_scroll.add_child(team_slots)
		_team_cards.append(card)
		_team_heads.append(head)
		_team_slots.append(team_slots)

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
	_team_editor = _make_team_editor()
	add_child(_team_editor)


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
