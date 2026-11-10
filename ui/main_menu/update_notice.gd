class_name UpdateNotice
extends HBoxContainer
## The main menu's line about a newer version (Updater): downloading (with
## progress), ready (Restart now), available (Download: the release page, or
## the APK on Android) or failed (Try again). Hidden when there's nothing to
## say.

var _label := UiStyle.label("", &"DimLabel")
var _button := UiStyle.menu_button("")


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_label)
	_button.custom_minimum_size = Vector2(220, 46)
	_button.pressed.connect(_on_pressed)
	add_child(_button)
	if has_node("/root/Updater"):
		Updater.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var updater: Node = get_node_or_null("/root/Updater")
	var state: int = updater.state if updater != null else 0
	var version: String = updater.latest.get("version", "") if updater != null else ""
	visible = true
	_button.visible = true
	_label.remove_theme_color_override("font_color")
	match state:
		Updater.State.DOWNLOADING:
			_label.text = tr("UPDATE_DOWNLOADING") % [version, roundi(updater.progress * 100.0)]
			_button.visible = false
		Updater.State.READY:
			_label.text = tr("UPDATE_READY") % version
			_button.text = tr("UPDATE_RESTART")
		Updater.State.AVAILABLE:
			_label.text = tr("UPDATE_AVAILABLE") % version
			_button.text = tr("UPDATE_GET")
		Updater.State.FAILED:
			_label.text = tr("UPDATE_FAILED") % updater.error
			_label.add_theme_color_override("font_color", UiStyle.WARN)
			_button.text = tr("UPDATE_RETRY")
		_:
			visible = false


func _on_pressed() -> void:
	match Updater.state:
		Updater.State.READY:
			Updater.install_now()
		Updater.State.AVAILABLE:
			OS.shell_open(Updater.download_page())
		Updater.State.FAILED:
			Updater.retry()
