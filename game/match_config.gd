class_name MatchConfig
extends RefCounted
## What the match scene should start: offline play, a listen host or a client
## (PLAN §2.4). The menu fills `pending` before changing scene; the match
## reports a failure back through `last_error`.

enum Mode { OFFLINE, HOST, JOIN }

static var pending: MatchConfig
static var last_error: String = ""
## After losing a match to the network: how to rejoin it (PLAN §3.4: the
## server keeps our score and team for 60 s). {config, token, until_ms}.
static var rejoin: Dictionary = {}

var mode: int = Mode.OFFLINE
var address: String = "127.0.0.1"
var port: int = Protocol.DEFAULT_PORT
var player_name: String = "Player"
var map: String = Maps.DEFAULT
var bots: int = 3  ## dummies alongside the local player; they leave as humans join
var character: int = 0  ## index into CharacterRig.SELECTABLE
var color: int = 0  ## index into PlayerVisual.PALETTE (0 = auto)
var primary: int = 0  ## index into Loadouts.PRIMARIES
var game_mode: int = GameMode.FFA  ## hosting: the mode to run
var friendly_fire: bool = false  ## hosting TDM
var bot_difficulty: int = 1  ## BotBrain.Difficulty
var map_retried: bool = false  ## joined once already and reloaded with the host's map
var reconnect_token: int = 0  ## JOIN: rejoin a match we dropped out of
## Internet play over EOS (decision 0005): HOST advertises an invite code,
## JOIN connects to the game with `online_code` instead of `address`.
var online: bool = false
var online_code: String = ""
## JOIN online: the host's product user ID when already known (server
## browser, or the lobby before its match); otherwise found by `online_code`.
var online_host: String = ""
var minutes: int = 0  ## match length; 0: the mode's default
## Started from a lobby (LobbySession): the host serves the lobby's online
## game again; clients give the host a moment to open the match.
var from_lobby: bool = false


## The rejoin offer if it is still open, else {}.
static func open_rejoin() -> Dictionary:
	return rejoin if not rejoin.is_empty() and Time.get_ticks_msec() < int(rejoin.until_ms) else {}


## PLAN §3.5.1: a phone host takes 4 combatants, a PC host 8. Final for M4:
## the Mi 11X failed the 20-minute 8-combatant host test (frame p95 ~26 ms,
## tick p99 up to 5 ms; docs/perf/m4.md).
func max_combatants() -> int:
	if Platform.get_user_arg("--host-cap").is_valid_int():  # dev: the phone host test
		return clampi(Platform.get_user_arg("--host-cap").to_int(), 2, Protocol.MAX_PEERS)
	return 4 if Platform.is_mobile() else 8


static func make(p_mode: int, p_name: String, p_bots: int = 0, p_address: String = "") -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = p_mode
	c.player_name = p_name
	c.bots = p_bots
	var saved: Variant = Settings.get_value("profile", "map")
	c.map = Maps.from_args(saved if saved is String else Maps.DEFAULT)
	c.character = profile_character()
	c.color = profile_color()
	c.primary = profile_primary()
	var mode: Variant = Settings.get_value("profile", "mode")
	c.game_mode = GameMode.from_id(Platform.get_user_arg("--mode", mode if mode is String else "ffa"))
	c.friendly_fire = Settings.get_value("profile", "friendly_fire") == true
	var minutes: Variant = Settings.get_value("profile", "minutes")
	c.minutes = minutes if minutes is int and LobbySession.DURATIONS.has(minutes) else LobbySession.DEFAULT_MINUTES
	var level: Variant = Settings.get_value("profile", "bot_difficulty")
	c.bot_difficulty = maxi(BotBrain.DIFFICULTY_IDS.find(Platform.get_user_arg("--bot-difficulty",
			level if level is String else "normal")), 0)
	if Platform.get_user_arg("--bots").is_valid_int():  # dev override for quick launches
		c.bots = Platform.get_user_arg("--bots").to_int()
	if not p_address.is_empty():
		c.address = p_address
	return c


## The player's name from settings, generating and saving one on first use.
static func profile_name() -> String:
	var v: Variant = Settings.get_value("profile", "name")
	var n: String = v if v is String else ""
	if n.strip_edges().length() < 3:
		n = "Pilot%03d" % (randi() % 1000)
		Settings.set_value("profile", "name", n)
		Settings.save_settings()
	return n


## The chosen character's index (CharacterRig.SELECTABLE); the default if
## it is still locked.
static func profile_character() -> int:
	var v: Variant = Settings.get_value("profile", "character")
	var i := CharacterRig.selectable_index(v if v is String else "")
	return i if Unlocks.character_level(CharacterRig.SELECTABLE[i]) <= Unlocks.level() else 0


## The chosen colour's index (PlayerVisual.PALETTE, 0 = auto); auto if it
## is still locked.
static func profile_color() -> int:
	var v: Variant = Settings.get_value("profile", "color")
	var i := clampi(v if v is int else 0, 0, PlayerVisual.PALETTE.size() - 1)
	return i if Unlocks.color_level(i) <= Unlocks.level() else 0


## The chosen primary weapon (Loadouts.PRIMARIES index).
static func profile_primary() -> int:
	var v: Variant = Settings.get_value("profile", "primary")
	return clampi(v if v is int else 0, 0, Loadouts.PRIMARIES.size() - 1)


## Stable per-install id sent in the handshake (identifies the player across
## sessions; never personal data).
static func profile_uuid() -> String:
	var v: Variant = Settings.get_value("profile", "uuid")
	var id: String = v if v is String else ""
	if id.length() < 16:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		id = "%08x%08x" % [rng.randi(), rng.randi()]
		Settings.set_value("profile", "uuid", id)
		Settings.save_settings()
	return id
