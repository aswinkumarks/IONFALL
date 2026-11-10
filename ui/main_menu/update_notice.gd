class_name UpdateNotice
extends HBoxContainer
## The main menu's line after "Later" (UpdateDialog): a newer version is
## available, and an Update button that opens the popup again. Hidden while
## the popup is open or there's nothing to say.

var dialog: UpdateDialog

var _label := UiStyle.label("", &"DimLabel")
var _button := UiStyle.menu_button("UPDATE_BUTTON")


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_label)
	_button.custom_minimum_size = Vector2(180, 46)
	_button.pressed.connect(func() -> void:
		if dialog != null:
			dialog.open())
	add_child(_button)
	if has_node("/root/Updater"):
		Updater.changed.connect(_refresh)
	if dialog != null:
		dialog.visibility_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var updater: Node = get_node_or_null("/root/Updater")
	visible = updater != null and updater.asked and updater.state in [Updater.State.AVAILABLE, Updater.State.FAILED] \
			and (dialog == null or not dialog.visible)
	if visible:
		_label.text = tr("UPDATE_AVAILABLE") % updater.latest.get("version", "")
