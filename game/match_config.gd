class_name MatchConfig
extends RefCounted
## What the match scene should start: offline play, a listen host or a client
## (PLAN §2.4). The menu fills `pending` before changing scene; the match
## reports a failure back through `last_error`.

enum Mode { OFFLINE, HOST, JOIN }

static var pending: MatchConfig
static var last_error: String = ""

var mode: int = Mode.OFFLINE
var address: String = "127.0.0.1"
var port: int = Protocol.DEFAULT_PORT
var player_name: String = "Player"
var bots: int = 3


static func make(p_mode: int, p_name: String, p_bots: int = 0, p_address: String = "") -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = p_mode
	c.player_name = p_name
	c.bots = p_bots
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
