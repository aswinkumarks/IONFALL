class_name GameLog
extends Logger
## A copy of everything the game logs (prints, warnings, errors with their
## script backtraces) in a folder players can find and send in bug reports:
## `logs/` next to the executable on desktop, the app's external files
## directory on Android (Android/data/<app>/files/logs, reachable over USB or
## with a file manager; release builds don't log to logcat). Each line starts
## with the wall-clock time, so a host's and a client's logs line up.
##
## One file per session, flushed per line (a frozen or killed game keeps
## everything up to the freeze). The newest KEEP_FILES stay. Exported builds
## only; nowhere writable means no copy (user://logs still has Godot's own).

const KEEP_FILES := 10

var path: String = ""
var _file: FileAccess
var _mutex := Mutex.new()


## Starts logging into `dir`; returns null when it can't be written.
static func open(dir: String) -> GameLog:
	if dir.is_empty() or DirAccess.make_dir_recursive_absolute(dir) != OK:
		return null
	var stamp := Time.get_datetime_string_from_system().replace(":", ".")
	var log := GameLog.new()
	log.path = dir.path_join("ionfall-%s.log" % stamp)
	log._file = FileAccess.open(log.path, FileAccess.WRITE)
	if log._file == null:
		return null
	_prune(dir)
	return log


## Where this platform's copy goes ("" for none: editor, tests, web).
static func default_dir(external_files_dir: String) -> String:
	if not OS.has_feature("template") or OS.has_feature("web"):
		return ""
	if OS.has_feature("android"):
		return external_files_dir.path_join("logs") if not external_files_dir.is_empty() else ""
	return OS.get_executable_path().get_base_dir().path_join("logs")


func _log_message(message: String, _error: bool) -> void:
	_write(message)


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
	var text := "%s: %s\n   at: %s (%s:%d)\n" % [kind, rationale if not rationale.is_empty() else code, function, file, line]
	for bt in script_backtraces:
		if not bt.is_empty():
			text += bt.format(3) + "\n"
	_write(text)


func _write(text: String) -> void:
	var now := Time.get_unix_time_from_system()
	var stamp := "%s.%03d " % [Time.get_time_string_from_system(), int(fmod(now, 1.0) * 1000.0)]
	_mutex.lock()
	if _file != null:
		_file.store_string(stamp + (text if text.ends_with("\n") else text + "\n"))
		_file.flush()
	_mutex.unlock()


static func _prune(dir: String) -> void:
	var names := Array(DirAccess.get_files_at(dir)).filter(func(n: String) -> bool:
		return n.begins_with("ionfall-") and n.ends_with(".log"))
	names.sort()  # timestamped names sort oldest first
	for i in names.size() - KEEP_FILES:
		DirAccess.remove_absolute(dir.path_join(names[i]))
