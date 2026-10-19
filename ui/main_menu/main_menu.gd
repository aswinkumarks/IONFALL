extends Control
## Main menu. Every visible string is a translation key (PLAN §3.16).
##
## Quick test launches (desktop): `-- --play`, `-- --host`, `-- --join <address>` and
## `-- --name <name>` skip the menu; `--open-settings` / `--open-profile` open those screens
## (`--open-stats`: the profile's Stats tab).

const MATCH := "res://game/match.tscn"
const OFFLINE_DUMMIES := 3
const HOST_DUMMIES := 2

@onready var _version_label: Label = %VersionLabel
@onready var _storage_warning: Label = %StorageWarning
@onready var _quit_button: Button = %QuitButton
@onready var _play_button: Button = %PlayButton
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _join_panel: Control = %JoinPanel
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _connect_button: Button = %ConnectButton
@onready var _back_button: Button = %BackButton
@onready var _name_edit: LineEdit = %NameEdit
@onready var _status: Label = %StatusLabel
@onready var _lan_label: Label = %LanLabel
@onready var _game_list: VBoxContainer = %GameList

var _browser: Discovery.Browser
var _profile_panel := ProfilePanel.new()
var _settings := SettingsMenu.new()


func _ready() -> void:
	var music := AudioStreamPlayer.new()
	music.stream = load("res://audio/generated/ambient_loop.wav")
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
	_play_button.pressed.connect(_start.bind(MatchConfig.Mode.OFFLINE))
	_host_button.pressed.connect(_start.bind(MatchConfig.Mode.HOST))
	_join_button.pressed.connect(_show_join.bind(true))
	_back_button.pressed.connect(_show_join.bind(false))
	_connect_button.pressed.connect(_start.bind(MatchConfig.Mode.JOIN))
	add_child(_profile_panel)
	add_child(_settings)
	%SettingsButton.pressed.connect(_settings.open)
	_settings.closed.connect(func() -> void: %SettingsButton.grab_focus())
	_profile_panel.closed.connect(func() -> void:
		_name_edit.text = MatchConfig.profile_name()
		%ProfileButton.grab_focus())
	%ProfileButton.pressed.connect(func() -> void: _profile_panel.open(_name_edit.text))
	_address_edit.text_submitted.connect(func(_t: String) -> void: _start(MatchConfig.Mode.JOIN))
	# Web builds can't host or use ENet (PLAN §3.20); they get a WebSocket transport later.
	_host_button.visible = not Platform.is_web()
	_join_button.visible = not Platform.is_web()
	if not MatchConfig.last_error.is_empty():
		_status.text = tr(MatchConfig.last_error)
		_status.visible = true
		MatchConfig.last_error = ""
	_update_player_card()
	Profile.changed.connect(_update_player_card)
	_play_button.grab_focus()
	_animate_in()
	if _try_join_link():
		return
	if Platform.user_args.has("--open-settings"):
		_settings.open()
	elif Platform.user_args.has("--open-profile"):
		_profile_panel.open(_name_edit.text)
	elif Platform.user_args.has("--open-stats"):
		_profile_panel.open(_name_edit.text, ProfilePanel.Tab.STATS)
	elif Platform.user_args.has("--play"):
		_start.call_deferred(MatchConfig.Mode.OFFLINE)
	elif Platform.user_args.has("--host"):
		_start.call_deferred(MatchConfig.Mode.HOST)
	elif Platform.user_args.has("--join") and not Platform.user_args.has("--test-clients"):
		_address_edit.text = Platform.get_user_arg("--join", "127.0.0.1")
		_start.call_deferred(MatchConfig.Mode.JOIN)


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
	_address_edit.text = link.host
	_start.call_deferred(MatchConfig.Mode.JOIN, link.port)
	return true


## The join panel replaces the menu buttons, so on phones the address field
## sits near the top, above the on-screen keyboard. LAN games are listed
## while it's open (PLAN §3.6).
func _show_join(show: bool) -> void:
	_join_panel.visible = show
	if show and _browser == null:
		_browser = Discovery.Browser.new()
		_browser.changed.connect(_refresh_games)
		add_child(_browser)
		_refresh_games()
	elif not show and _browser != null:
		_browser.queue_free()
		_browser = null
	for b: Control in [_play_button, _host_button, _join_button, %ProfileButton, %SettingsButton, _quit_button]:
		b.visible = not show and (b != _quit_button or not (Platform.is_web() or Platform.is_mobile()))
	if show:
		_address_edit.grab_focus()
	else:
		_join_button.grab_focus()


func _refresh_games() -> void:
	for child in _game_list.get_children():
		child.queue_free()
	var games := _browser.sorted() if _browser != null else []
	if _browser != null and not _browser.listening:
		_lan_label.text = tr("MENU_LAN_UNAVAILABLE")
	else:
		_lan_label.text = tr("MENU_LAN_SEARCHING") if games.is_empty() else tr("MENU_LAN_GAMES")
	for b: Discovery.Beacon in games:
		var row := Button.new()
		row.text = "%s · %s · %d/%d" % [b.name, b.map, b.combatants, b.max_combatants]
		if not b.compatible():
			row.text += " · " + tr("MENU_LAN_OTHER_VERSION") % b.build
			row.disabled = true
		var address := b.address
		var port := b.game_port
		row.pressed.connect(func() -> void:
			_address_edit.text = address
			_start(MatchConfig.Mode.JOIN, port))
		_game_list.add_child(row)


func _start(mode: int, port: int = Protocol.DEFAULT_PORT) -> void:
	var player_name := ServerSession.sanitize_name(_name_edit.text)
	if player_name != MatchConfig.profile_name():
		Settings.set_value("profile", "name", player_name)
	var bots := OFFLINE_DUMMIES if mode == MatchConfig.Mode.OFFLINE else HOST_DUMMIES if mode == MatchConfig.Mode.HOST else 0
	var config := MatchConfig.make(mode, player_name, bots)
	if mode == MatchConfig.Mode.JOIN:
		var address := _address_edit.text.strip_edges()
		var colon := address.rfind(":")
		if colon > 0 and address.count(":") == 1 and address.substr(colon + 1).is_valid_int():
			port = clampi(address.substr(colon + 1).to_int(), 1, 65535)
			address = address.left(colon)
		if not address.is_valid_ip_address():
			_status.text = tr("MENU_BAD_ADDRESS")
			_status.visible = true
			return
		config.address = address
		config.port = port
		Settings.set_value("profile", "last_address", address)
	Settings.save_settings()
	MatchConfig.pending = config
	get_tree().change_scene_to_file(MATCH)
