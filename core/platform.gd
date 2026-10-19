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


func _init() -> void:
	user_args = OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or user_args.has("--server"):
		role = Role.DEDICATED_SERVER


func _ready() -> void:
	storage_available = _probe_storage()
	if not storage_available:
		push_warning("Platform: user:// is not writable; the profile won't be saved.")


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
## broadcasts on some Android devices (PLAN §3.6). No-op elsewhere until the
## Android plugin exists.
func acquire_multicast_lock() -> void:
	pass


func release_multicast_lock() -> void:
	pass


func _probe_storage() -> bool:
	var path := "user://.storage_probe"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return true
