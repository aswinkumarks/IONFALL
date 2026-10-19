extends Control
## Placeholder main menu (M0). Every visible string is a translation key
## (PLAN §3.16). Gameplay entries are wired up from M1 onward.

@onready var _version_label: Label = %VersionLabel
@onready var _storage_warning: Label = %StorageWarning
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_version_label.text = BuildInfo.display_string()
	_storage_warning.visible = not Platform.storage_available
	# Browsers and mobile apps are closed by the OS, not by an in-game button.
	_quit_button.visible = not (Platform.is_web() or Platform.is_mobile())
	_quit_button.pressed.connect(get_tree().quit)
