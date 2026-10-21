extends Node
## Epic Online Services backend for internet play (decision 0005): platform
## setup, anonymous device-ID login, lobbies as invite codes, and EOS P2P
## peers for `Transport`. Loaded only by `Online` when the EOSG extension is
## present, so no other script refers to EOS types (web and dedicated-server
## builds don't have them).

const CREDENTIALS := "res://eos_credentials.cfg"
const SOCKET := "ionfall"  ## EOS P2P socket name (alphanumeric, ≤ 32)
const ATTR_CODE := "code"
const ATTR_COMPAT := "compat"

var product_user_id: String = ""
var _platform_ready: bool = false
var _lobby_id: String = ""


## True when credentials are present (the secret is filled in locally).
static func configured() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(CREDENTIALS) == OK and not str(cfg.get_value("eos", "client_secret", "")).is_empty()


## Initializes the SDK and creates the platform. Returns "" or an error.
func init_platform() -> String:
	if _platform_ready:
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(CREDENTIALS) != OK:
		return "missing %s" % CREDENTIALS
	var init := EOS.PlatformSdk.InitializeOptions.new()
	init.product_name = cfg.get_value("eos", "product_name", "IONFALL")
	init.product_version = BuildInfo.display_string()
	var res: int = EOS.PlatformSdk.PlatformInterface.initialize(init)
	if res != EOS.Result.Success and res != EOS.Result.AlreadyConfigured:
		return "EOS initialize failed: %s" % EOS.result_str(res)
	var create := EOS.PlatformSdk.CreateOptions.new()
	create.product_id = cfg.get_value("eos", "product_id", "")
	create.sandbox_id = cfg.get_value("eos", "sandbox_id", "")
	create.deployment_id = cfg.get_value("eos", "deployment_id", "")
	create.client_id = cfg.get_value("eos", "client_id", "")
	create.client_secret = cfg.get_value("eos", "client_secret", "")
	create.tick_budget_in_milliseconds = 2
	if not EOS.PlatformSdk.PlatformInterface.create(create):
		return "EOS platform could not be created"
	_platform_ready = true
	return ""


## Anonymous login with this device's ID (created once, then reused).
## Returns "" or an error.
func sign_in_async(display_name: String) -> String:
	var err := init_platform()
	if not err.is_empty():
		return err
	var device := EOS.Connect.CreateDeviceIdOptions.new()
	device.device_model = Platform.device_model()
	EOS.Connect.ConnectInterface.create_device_id(device)
	var created: Dictionary = await IEOS.connect_interface_create_device_id_callback
	if created.result_code != EOS.Result.Success and created.result_code != EOS.Result.DuplicateNotAllowed:
		return "device ID: %s" % EOS.result_str(created)
	var login := EOS.Connect.LoginOptions.new()
	login.credentials = EOS.Connect.Credentials.new()
	login.credentials.type = EOS.ExternalCredentialType.DeviceidAccessToken
	login.credentials.token = null
	login.user_login_info = EOS.Connect.UserLoginInfo.new()
	login.user_login_info.display_name = display_name.left(32) if not display_name.is_empty() else "Player"
	EOS.Connect.ConnectInterface.login(login)
	var ret: Dictionary = await IEOS.connect_interface_login_callback
	if ret.result_code == EOS.Result.InvalidUser:
		var user := EOS.Connect.CreateUserOptions.new()
		user.continuance_token = ret.continuance_token
		EOS.Connect.ConnectInterface.create_user(user)
		ret = await IEOS.connect_interface_create_user_callback
	if ret.result_code != EOS.Result.Success:
		return "login: %s" % EOS.result_str(ret)
	product_user_id = ret.local_user_id
	EOSGRuntime.local_product_user_id = product_user_id
	return ""


## Hosting: a listening P2P peer plus a lobby advertising its invite code.
## Returns {peer, code} or {error}.
func host_async(max_members: int) -> Dictionary:
	var peer := EOSGMultiplayerPeer.new()
	var err: int = peer.create_server(SOCKET)
	if err != OK:
		return {"error": "P2P server: %s" % error_string(err)}
	var opts := EOS.Lobby.CreateLobbyOptions.new()
	opts.local_user_id = product_user_id
	opts.bucket_id = _bucket()
	opts.max_lobby_members = clampi(max_members, 2, 64)
	opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	opts.presence_enabled = false
	opts.allow_invites = false
	opts.enable_join_by_id = false
	opts.enable_rtc_room = false
	EOS.Lobby.LobbyInterface.create_lobby(opts)
	var created: Dictionary = await IEOS.lobby_interface_create_lobby_callback
	if created.result_code != EOS.Result.Success:
		peer.close()
		return {"error": "lobby: %s" % EOS.result_str(created)}
	_lobby_id = created.lobby_id
	var code := Online.new_code()
	var mod_opts := EOS.Lobby.UpdateLobbyModificationOptions.new()
	mod_opts.local_user_id = product_user_id
	mod_opts.lobby_id = _lobby_id
	var mod_ret: Dictionary = EOS.Lobby.LobbyInterface.update_lobby_modification(mod_opts)
	if mod_ret.result_code != EOS.Result.Success:
		await leave_async()
		peer.close()
		return {"error": "lobby update: %s" % EOS.result_str(mod_ret)}
	var mod: EOSGLobbyModification = mod_ret.lobby_modification
	mod.add_attribute(ATTR_CODE, code, EOS.Lobby.LobbyAttributeVisibility.Public)
	mod.add_attribute(ATTR_COMPAT, BuildInfo.compat_hash, EOS.Lobby.LobbyAttributeVisibility.Public)
	var update := EOS.Lobby.UpdateLobbyOptions.new()
	update.lobby_modification = mod
	EOS.Lobby.LobbyInterface.update_lobby(update)
	var updated: Dictionary = await IEOS.lobby_interface_update_lobby_callback
	if updated.result_code != EOS.Result.Success:
		await leave_async()
		peer.close()
		return {"error": "lobby update: %s" % EOS.result_str(updated)}
	return {"peer": peer, "code": code}


## Joining: finds the lobby with `code` and connects to its owner.
## Returns {peer} or {error} (error "not_found" when no such game).
func join_async(code: String) -> Dictionary:
	var search_opts := EOS.Lobby.CreateLobbySearchOptions.new()
	search_opts.max_results = 1
	var search_ret: Dictionary = EOS.Lobby.LobbyInterface.create_lobby_search(search_opts)
	if search_ret.result_code != EOS.Result.Success:
		return {"error": "search: %s" % EOS.result_str(search_ret)}
	var search: EOSGLobbySearch = search_ret.lobby_search
	search.set_parameter(EOS.Lobby.SEARCH_BUCKET_ID, _bucket(), EOS.ComparisonOp.Equal)
	search.set_parameter(ATTR_CODE, code, EOS.ComparisonOp.Equal)
	search.find(product_user_id)
	var found: Dictionary = await IEOS.lobby_search_find_callback
	if found.result_code == EOS.Result.NotFound or (found.result_code == EOS.Result.Success
			and search.get_search_result_count() == 0):
		return {"error": "not_found"}
	if found.result_code != EOS.Result.Success:
		return {"error": "search: %s" % EOS.result_str(found)}
	var copied: Dictionary = search.copy_search_result_by_index(0)
	if copied.result_code != EOS.Result.Success:
		return {"error": "search: %s" % EOS.result_str(copied)}
	var info: Dictionary = (copied.lobby_details as EOSGLobbyDetails).copy_info()
	if info.result_code != EOS.Result.Success:
		return {"error": "lobby info: %s" % EOS.result_str(info)}
	var host_id: String = info.lobby_details.lobby_owner_user_id
	var peer := EOSGMultiplayerPeer.new()
	var err: int = peer.create_client(SOCKET, host_id)
	if err != OK:
		return {"error": "P2P client: %s" % error_string(err)}
	return {"peer": peer}


## Host: closes the lobby so its code stops working.
func leave_async() -> void:
	if _lobby_id.is_empty():
		return
	var opts := EOS.Lobby.DestroyLobbyOptions.new()
	opts.local_user_id = product_user_id
	opts.lobby_id = _lobby_id
	_lobby_id = ""
	EOS.Lobby.LobbyInterface.destroy_lobby(opts)
	await IEOS.lobby_interface_destroy_lobby_callback


## Lobbies only match builds that can play together.
static func _bucket() -> String:
	return "ionfall:%s" % BuildInfo.compat_hash

