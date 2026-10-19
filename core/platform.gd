extends Node
## Platform service (PLAN §3.20 rule 11).
##
## All OS- and platform-specific behaviour goes through here so that `sim/`
## and `net/` never call OS APIs directly. Web and dedicated-server builds get
## their own implementations of each capability (often a no-op).

enum Role { CLIENT, DEDICATED_SERVER }

var role: Role = Role.CLIENT
## User arguments passed after `--` on the command line (PLAN §3.5.2).
var user_args: PackedStringArray = PackedStringArray()
## False when `user://` can't be written or isn't persistent (PLAN §3.13).
var storage_available: bool = true

const WIFI_MODE_FULL_LOW_LATENCY := 4

var _multicast_refs: int = 0
var _multicast_lock: Variant = null
var _latency_lock: Variant = null
var _handled_link: String = ""


func _init() -> void:
	user_args = OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or user_args.has("--server"):
		role = Role.DEDICATED_SERVER


func _ready() -> void:
	storage_available = _probe_storage()
	if not storage_available:
		push_warning("Platform: user:// is not writable; the profile won't be saved.")


## Android drops immersive fullscreen after calls and some system dialogs:
## restore it whenever the app gets focus back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_android():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func is_dedicated_server() -> bool:
	return role == Role.DEDICATED_SERVER


func is_web() -> bool:
	return OS.has_feature("web")


func is_android() -> bool:
	return OS.has_feature("android")


func is_mobile() -> bool:
	return OS.has_feature("mobile")


## Returns the value following `flag` in the user arguments, or `default`.
func get_user_arg(flag: String, default: String = "") -> String:
	var i := user_args.find(flag)
	if i == -1 or i + 1 >= user_args.size():
		return default
	return user_args[i + 1]


## Acquires the Wi-Fi multicast lock needed to receive LAN discovery
## broadcasts on some Android devices (PLAN §3.6). Reference counted; held
## only while the server browser is open or while hosting. No-op elsewhere.
func acquire_multicast_lock() -> void:
	_multicast_refs += 1
	if _multicast_refs == 1:
		_multicast_lock = _wifi_lock("createMulticastLock", ["ionfall-discovery"])


func release_multicast_lock() -> void:
	_multicast_refs = maxi(_multicast_refs - 1, 0)
	if _multicast_refs == 0 and _multicast_lock != null:
		_multicast_lock.call("release")
		_multicast_lock = null


## Asks Android for low-latency Wi-Fi during matches (disables Wi-Fi power
## saving, which otherwise bunches packets; see decision 0002). No-op elsewhere.
func set_low_latency_network(enabled: bool) -> void:
	if enabled and _latency_lock == null:
		_latency_lock = _wifi_lock("createWifiLock", [WIFI_MODE_FULL_LOW_LATENCY, "ionfall-match"])
	elif not enabled and _latency_lock != null:
		_latency_lock.call("release")
		_latency_lock = null


## A pending join link (PLAN §3.6), once: {host, port} or {}. Desktop:
## an `ionfall://join?host=…&port=…` argument. Android: the launch intent's
## data, so links work whether the app was running or not.
func take_join_link() -> Dictionary:
	var url := ""
	for a in user_args:
		if a.begins_with("ionfall://"):
			url = a
	if is_android():
		var activity: Variant = _android_activity()
		if activity != null:
			var intent: Variant = activity.call("getIntent")
			if intent != null:
				var data: Variant = intent.call("getDataString")
				url = str(data) if data != null else ""
	if url.is_empty() or url == _handled_link:
		return {}
	_handled_link = url
	return parse_join_link(url)


static func parse_join_link(url: String) -> Dictionary:
	if not url.begins_with("ionfall://join?"):
		return {}
	var out := {"host": "", "port": 47710}
	for pair in url.substr("ionfall://join?".length()).split("&"):
		var kv := pair.split("=")
		if kv.size() != 2:
			continue
		if kv[0] == "host":
			out.host = kv[1].uri_decode()
		elif kv[0] == "port" and kv[1].is_valid_int():
			out.port = clampi(kv[1].to_int(), 1, 65535)
	return out if out.host.is_valid_ip_address() else {}


## Android thermal status (PowerManager.THERMAL_STATUS_*: 0 none … 6
## shutdown), or -1 where unknown. For soak logs and, later, quality
## step-down (PLAN §3.10).
func thermal_status() -> int:
	if not is_android() or not Engine.has_singleton("AndroidRuntime"):
		return -1
	var ctx: Variant = Engine.get_singleton("AndroidRuntime").call("getApplicationContext")
	if ctx == null:
		return -1
	var power: Variant = ctx.call("getSystemService", "power")
	return int(power.call("getCurrentThermalStatus")) if power != null else -1


func _android_activity() -> Variant:
	if not is_android() or not Engine.has_singleton("AndroidRuntime"):
		return null
	return Engine.get_singleton("AndroidRuntime").call("getActivity")


## Creates and acquires a WifiManager lock through AndroidRuntime +
## JavaClassWrapper (no native plugin). Returns the lock or null.
func _wifi_lock(factory: String, args: Array) -> Variant:
	if not is_android() or not Engine.has_singleton("AndroidRuntime"):
		return null
	var ctx: Variant = Engine.get_singleton("AndroidRuntime").call("getApplicationContext")
	if ctx == null:
		return null
	var wifi: Variant = ctx.call("getSystemService", "wifi")
	if wifi == null:
		push_warning("Platform: no WifiManager")
		return null
	var lock: Variant = wifi.callv(factory, args)
	if lock == null:
		push_warning("Platform: %s failed" % factory)
		return null
	lock.call("setReferenceCounted", false)
	lock.call("acquire")
	print("Platform: %s acquired" % factory)
	return lock


func _probe_storage() -> bool:
	var path := "user://.storage_probe"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true
