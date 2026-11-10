class_name UpdateDialog
extends Control
## The main menu's "Update available" popup (Updater): shown once per start
## when GitHub has a newer version. Update now downloads it (with progress
## and Cancel), installs it and restarts, or, where the game can't install
## itself (Android, a folder it can't write to), opens the download. Later
## closes it; the menu keeps an Update line (UpdateNotice) that opens it
## again.

signal closed

var _body := UiStyle.label("")
var _notes := UiStyle.label("", &"DimLabel")
var _bar := ProgressBar.new()
var _status := UiStyle.label("", &"DimLabel")
var _primary := UiStyle.menu_button("UPDATE_NOW", &"PrimaryButton")
var _secondary := UiStyle.menu_button("UPDATE_LATER")


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var parts := UiStyle.menu_overlay(560.0)
	add_child(parts[0])
	var box: VBoxContainer = parts[1]
	var title := UiStyle.label("UPDATE_TITLE", &"HeaderLabel")
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	for l: Label in [_body, _notes, _status]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.custom_minimum_size.x = 540
	box.add_child(_body)
	box.add_child(_notes)
	_bar.custom_minimum_size = Vector2(540, 14)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	box.add_child(_bar)
	box.add_child(_status)
	_primary.pressed.connect(_on_primary)
	_secondary.pressed.connect(_on_secondary)
	box.add_child(_primary)
	box.add_child(_secondary)


func _ready() -> void:
	if has_node("/root/Updater"):
		Updater.changed.connect(_on_changed)
		_on_changed()


## Shows the popup (from the menu's Update line).
func open() -> void:
	visible = true
	_refresh()
	_primary.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _on_changed() -> void:
	# Ask once per start, as soon as the check finds something.
	if Updater.state == Updater.State.AVAILABLE and not Updater.asked:
		Updater.asked = true
		Log.i("update", "asking about %s" % Updater.latest.version)
		open()
	elif visible:
		_refresh()


func _refresh() -> void:
	var version: String = Updater.latest.get("version", "")
	_body.text = tr("UPDATE_BODY") % [version, Updater.current_version()]
	_notes.text = _notes_preview(str(Updater.latest.get("notes", "")))
	_notes.visible = not _notes.text.is_empty()
	_bar.visible = Updater.state in [Updater.State.DOWNLOADING, Updater.State.READY]
	_bar.value = Updater.progress if Updater.state == Updater.State.DOWNLOADING else 1.0
	_status.remove_theme_color_override("font_color")
	_primary.visible = true
	_secondary.visible = true
	match Updater.state:
		Updater.State.DOWNLOADING:
			_status.text = tr("UPDATE_DOWNLOADING") % [version, roundi(Updater.progress * 100.0)]
			_primary.visible = false
			_secondary.text = "UPDATE_CANCEL"
		Updater.State.READY:
			_status.text = tr("UPDATE_INSTALLING") % version
			_primary.visible = false
			_secondary.visible = false
		Updater.State.FAILED:
			_status.text = tr("UPDATE_FAILED") % Updater.error
			_status.add_theme_color_override("font_color", UiStyle.WARN)
			_primary.text = "UPDATE_RETRY"
			_secondary.text = "UPDATE_LATER"
		_:
			_status.text = ""
			_primary.text = "UPDATE_NOW"
			_secondary.text = "UPDATE_LATER"
	_status.visible = not _status.text.is_empty()


func _on_primary() -> void:
	if Updater.state == Updater.State.FAILED:
		Updater.retry()
	elif not Updater.can_install():
		Updater.update_now()  # opens the download page
		_status.text = tr("UPDATE_BROWSER")
		_status.visible = true
	else:
		Updater.update_now()


func _on_secondary() -> void:
	if Updater.state == Updater.State.DOWNLOADING:
		Updater.cancel()
		return
	Log.i("update", "later")
	close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and Updater.state != Updater.State.READY:
		get_viewport().set_input_as_handled()
		_on_secondary()


## The release notes' first few bullet points as plain text (markdown
## dropped, each cut short), for a glance at what's new.
static func _notes_preview(notes: String, max_items: int = 4, max_chars: int = 110) -> String:
	var link := RegEx.create_from_string("\\[([^\\]]*)\\]\\([^)]*\\)")
	var items := PackedStringArray()
	for line in notes.replace("\r", "").split("\n", false):
		var t := line.strip_edges()
		if not (t.begins_with("- ") or t.begins_with("* ")):
			continue
		t = link.sub(t.substr(2), "$1", true).replace("**", "").replace("*", "").replace("`", "").strip_edges()
		if t.length() > max_chars:
			t = t.left(max_chars).rstrip(" ,.;:") + "…"
		items.append("• " + t)
		if items.size() >= max_items:
			break
	return "\n".join(items)
