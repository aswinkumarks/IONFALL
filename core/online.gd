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


func _ready() -> void:
	if Platform.is_dedicated_server() or not ClassDB.class_exists("EOSGMultiplayerPeer"):
		return
	var script: GDScript = load(BACKEND)
	if script == null or not script.configured():
		return
	_backend = script.new()
	_backend.name = "EOS"
	add_child(_backend)


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
	var err: String = await _backend.sign_in_async(display_name)
	_signing_in = false
	_signed_in = err.is_empty()
	return err


## Returns {peer, code} or {error}.
func host(display_name: String, max_members: int) -> Dictionary:
	var err := await ensure_signed_in(display_name)
	if not err.is_empty():
		return {"error": err}
	return await _backend.host_async(max_members)


## Returns {peer} or {error}; error "not_found" when no game has that code.
func join(display_name: String, code: String) -> Dictionary:
	var err := await ensure_signed_in(display_name)
	if not err.is_empty():
		return {"error": err}
	return await _backend.join_async(code)


## Host: closes the invite code.
func stop_hosting() -> void:
	if _backend != null:
		await _backend.leave_async()
