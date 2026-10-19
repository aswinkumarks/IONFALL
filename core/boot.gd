extends Node
## Entry scene: routes to the dedicated-server bootstrap or the client menu
## (PLAN §3.5.2: server mode comes from the `dedicated_server` feature tag or
## the `--server` user argument, never from `--headless` alone).

const MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
const SERVER_MAIN := "res://server/server_main.tscn"


func _ready() -> void:
	var target := SERVER_MAIN if Platform.is_dedicated_server() else MAIN_MENU
	get_tree().change_scene_to_file.call_deferred(target)
