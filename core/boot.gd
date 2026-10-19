extends Node
## Entry scene: routes to the dedicated-server bootstrap or the client menu
## (PLAN §3.5.2: server mode comes from the `dedicated_server` feature tag or
## the `--server` user argument, never from `--headless` alone).

const MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
const SERVER_MAIN := "res://server/server_main.tscn"
const TEST_CLIENTS := "res://game/test_clients.tscn"


func _ready() -> void:
	if Platform.user_args.has("--replay-check"):
		var check := ReplayCheck.new()
		check.finished.connect(func(_s: String) -> void: get_tree().quit())
		add_child(check)
		return
	var target := SERVER_MAIN if Platform.is_dedicated_server() else MAIN_MENU
	if not Platform.is_dedicated_server() and Platform.user_args.has("--test-clients"):
		target = TEST_CLIENTS
	get_tree().change_scene_to_file.call_deferred(target)
