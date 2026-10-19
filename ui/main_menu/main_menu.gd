extends Control
## Placeholder main menu (M0). Every visible string is a translation key
## (PLAN §3.16). Gameplay entries are wired up from M1 onward.

@onready var _version_label: Label = %VersionLabel
@onready var _storage_warning: Label = %StorageWarning
@onready var _quit_button: Button = %QuitButton
@onready var _play_button: Button = %PlayButton

const OFFLINE_MATCH := "res://game/offline_match.tscn"


func _ready() -> void:
	_version_label.text = BuildInfo.display_string()
	_storage_warning.visible = not Platform.storage_available
	# Browsers and mobile apps are closed by the OS, not by an in-game button.
	_quit_button.visible = not (Platform.is_web() or Platform.is_mobile())
	_quit_button.pressed.connect(get_tree().quit)
	_play_button.pressed.connect(get_tree().change_scene_to_file.bind(OFFLINE_MATCH))
	_play_button.grab_focus()
