extends Control
## Main menu. Every visible string is a translation key (PLAN §3.16).
##
## Quick test launches (desktop): `-- --play`, `-- --host`, `-- --join <address>` and
## `-- --name <name>` skip the menu.

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


func _ready() -> void:
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
	_address_edit.text_submitted.connect(func(_t: String) -> void: _start(MatchConfig.Mode.JOIN))
	# Web builds can't host or use ENet (PLAN §3.20); they get a WebSocket transport later.
	_host_button.visible = not Platform.is_web()
	_join_button.visible = not Platform.is_web()
	if not MatchConfig.last_error.is_empty():
		_status.text = tr(MatchConfig.last_error)
		_status.visible = true
		MatchConfig.last_error = ""
	_play_button.grab_focus()
	if _try_join_link():
		return
	if Platform.user_args.has("--play"):
		_start.call_deferred(MatchConfig.Mode.OFFLINE)
	elif Platform.user_args.has("--host"):
		_start.call_deferred(MatchConfig.Mode.HOST)
	elif Platform.user_args.has("--join") and not Platform.user_args.has("--test-clients"):
		_address_edit.text = Platform.get_user_arg("--join", "127.0.0.1")
		_start.call_deferred(MatchConfig.Mode.JOIN)


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
	for b: Control in [_play_button, _host_button, _join_button, %SettingsButton, _quit_button]:
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
