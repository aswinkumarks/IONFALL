extends Node
## Dedicated-server bootstrap (M0 stub). Networking arrives in M1b.
##
## Logs go to stderr (PLAN §3.5.2); stdout is reserved for the managed-mode
## JSON protocol. `--smoke-test` exits right after startup so CI can verify
## that the exported server boots.


func _ready() -> void:
	printerr("IONFALL server %s starting (engine %s, compat %s)" % [
		BuildInfo.display_string(), BuildInfo.engine_version, BuildInfo.compat_hash,
	])
	if Platform.user_args.has("--smoke-test"):
		printerr("IONFALL server smoke test OK")
		get_tree().quit(0)
