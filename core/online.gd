extends Node
## Internet play (decision 0005): player-hosted matches over Epic Online
## Services P2P, joined with a short invite code. Everything else in the game
## sees only MultiplayerPeers and codes; EOS code lives in
## net/online/eos_backend.gd, loaded only where the EOSG extension and the
## credentials exist (not on web, dedicated servers, or systems where the
## extension can't load). Elsewhere `available()` is false and online
## options are hidden.

const BACKEND := "res://net/online/eos_backend.gd"
## Invite codes: 6 characters from an alphabet without look-alikes (no 0/O,
## 1/I): about 10^9 codes, read aloud or typed on a phone.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 6
const CODE_PATTERN := "^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$"

var _backend: Node = null
var _signing_in: bool = false
var _signed_in: bool = false
var _code_regex := RegEx.create_from_string(CODE_PATTERN)
## Hosting: the invite code, and the browser info waiting to be published
## (updates are sent one at a time, the latest wins).
var hosting_code: String = ""
var _info_pending: Dictionary = {}
var _info_sending: bool = false


func _ready() -> void:
	if Platform.is_dedicated_server() or not ClassDB.class_exists("EOSGMultiplayerPeer"):
		return
	var script: GDScript = load(BACKEND)
	if script == null or not script.configured():
		return
	_backend = script.new()
	_backend.name = "EOS"
	add_child(_backend)
	Log.i("online", "Epic Online Services backend ready")


func available() -> bool:
	return _backend != null


static func new_code() -> String:
	var out := ""
	for i in CODE_LENGTH:
		out += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return out


## Normalizes typed input ("abc 123" → "ABC123"); "" when it isn't a code.
func parse_code(text: String) -> String:
	var code := text.strip_edges().to_upper().replace(" ", "").replace("-", "")
	return code if _code_regex.search(code) != null else ""


## Signs in once per session. Returns "" or an error.
func ensure_signed_in(display_name: String) -> String:
	if _backend == null:
		return "online play is not available on this build"
	while _signing_in:
		await get_tree().process_frame
	if _signed_in:
		return ""
	_signing_in = true
	var started := Time.get_ticks_msec()
	Log.i("online", "signing in as \"%s\"" % display_name)
	var err: String = await _backend.sign_in_async(display_name)
	_signing_in = false
	_signed_in = err.is_empty()
	if _signed_in:
		Log.i("online", "signed in (%d ms)" % (Time.get_ticks_msec() - started))
	else:
		Log.e("online", "sign-in failed after %d ms: %s" % [Time.get_ticks_msec() - started, err])
	return err


## Opens a game with a new invite code; `info` is what the server browser
## shows (name, map, mode, players, max, state). Returns {peer, code} or {error}.
func host(display_name: String, max_members: int, info: Dictionary = {}) -> Dictionary:
	var err := await ensure_signed_in(display_name)
	if not err.is_empty():
		return {"error": err}
	var hosted: Dictionary = await _backend.host_async(max_members, info)
	hosting_code = hosted.get("code", "")
	if hosted.has("error"):
		Log.e("online", "hosting failed: %s" % hosted.error)
	else:
		Log.i("online", "hosting with invite code %s (max %d, %s)" % [hosting_code, max_members, info])
	return hosted


## Host: a new listening peer for the same game (the lobby's peer must be
## closed first). Returns {peer} or {error}.
func serve() -> Dictionary:
	return _backend.serve() if _backend != null else {"error": "online play is not available on this build"}


## Host: updates what the server browser shows about our game.
func update_info(info: Dictionary) -> void:
	if _backend == null or hosting_code.is_empty():
		return
	_info_pending.merge(info, true)
	if _info_sending:
		return
	_info_sending = true
	while not _info_pending.is_empty() and not hosting_code.is_empty():
		var sending := _info_pending
		_info_pending = {}
		var err: String = await _backend.update_async(sending)
		if not err.is_empty():
			Log.w("online", "updating the game's listing failed: %s" % err)
		await get_tree().create_timer(1.0).timeout  # stay well inside EOS's rate limits
	_info_sending = false


## Online games of this build: {games: Array of {code, host_id, name, map,
## mode, players, max, state}} or {error}.
func list_games(display_name: String) -> Dictionary:
	var err := await ensure_signed_in(display_name)
	if not err.is_empty():
		return {"error": err}
	var listed: Variant = await _backend.list_async()
	Log.i("online", "listed %s" % ("%d games" % listed.size() if listed is Array else str(listed)))
	return {"games": listed} if listed is Array else listed


## Returns {peer, host_id} or {error}; error "not_found" when no game has
## that code, "version" when the host runs an incompatible build.
func join(display_name: String, invite_code: String) -> Dictionary:
	var err := await ensure_signed_in(display_name)
	if not err.is_empty():
		return {"error": err}
	Log.i("online", "joining invite code %s" % invite_code)
	var joined: Dictionary = await _backend.join_async(invite_code)
	_log_join(joined)
	return joined


## Connects to a known host (from the browser, or the lobby before the
## match). Returns {peer, host_id} or {error}.
func connect_to(display_name: String, host_id: String) -> Dictionary:
	var err := await ensure_signed_in(display_name)
	if not err.is_empty():
		return {"error": err}
	Log.i("online", "connecting to host %s" % host_id)
	var joined: Dictionary = await _backend.connect_async(host_id)
	_log_join(joined)
	return joined


## Host: closes the invite code.
func stop_hosting() -> void:
	if not hosting_code.is_empty():
		Log.i("online", "closing invite code %s" % hosting_code)
	hosting_code = ""
	_info_pending = {}
	if _backend != null:
		await _backend.leave_async()


func _log_join(joined: Dictionary) -> void:
	if joined.has("error"):
		Log.w("online", "join failed: %s" % joined.error)
	else:
		Log.i("online", "connecting through EOS P2P to host %s" % joined.get("host_id", "?"))
