class_name Log
extends RefCounted
## The game's log: timestamped, tagged lines in one file per session under
## user://logs/ (the last KEEP sessions), for debugging from a player's log.
##
##     Log.i("net", "joined %s:%d" % [address, port])
##
## Levels: d (debug: detail), i (info: what happened), w (warning), e (error).
## Besides these calls the file gets everything the engine logs: print()
## output, push_warning/push_error, engine errors and script errors with
## their backtraces (a Logger, OS.add_logger), so nothing printed is lost,
## also on Android release builds, which don't log to logcat.
##
## Static, so any script (and tools without the autoloads) can log; LogService
## (autoload) opens the file, writes the session header and flushes it.
## Without it (tools, `-s` scripts) lines only go to the console.
## `--log-level debug|info|warn|error` sets the minimum level (default debug).

enum Level { DEBUG, INFO, WARN, ERROR }
const LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]
const DIR := "user://logs/"  ## the default; Android: the app's external files (LogService)
const PREFIX := "ionfall_"
const KEEP := 10  ## session logs kept (oldest deleted at start)
const RECENT := 2000  ## lines kept in memory (the log as text without the file)
const SESSION_END := "=== session end"

static var level: int = Level.DEBUG
static var path: String = ""  ## this session's log file ("" until opened)
static var dir: String = DIR  ## where the session logs are
static var _file: FileAccess
static var _mutex := Mutex.new()
static var _echoing: bool = false  ## our own print(): the sink skips it
static var _recent: PackedStringArray = []
static var _start_ms: int = Time.get_ticks_msec()
static var _sink: _Sink


static func d(tag: String, msg: String) -> void:
	write(Level.DEBUG, tag, msg)


static func i(tag: String, msg: String) -> void:
	write(Level.INFO, tag, msg)


static func w(tag: String, msg: String) -> void:
	write(Level.WARN, tag, msg)


static func e(tag: String, msg: String) -> void:
	write(Level.ERROR, tag, msg)


## A line at `lvl` (Level) under `tag` (the subsystem: boot, net, match...).
## Warnings and errors also go to the console (stderr) and flush the file.
static func write(lvl: int, tag: String, msg: String) -> void:
	if lvl < level:
		return
	var line := format_line(lvl, tag, msg)
	_mutex.lock()
	_echoing = true
	if lvl >= Level.WARN:
		printerr(line)
	else:
		print(line)
	_echoing = false
	_store(line, lvl >= Level.WARN)
	_mutex.unlock()


## "12:34:56.789 +1234.567 INFO  [tag] msg": wall clock, seconds since start.
static func format_line(lvl: int, tag: String, msg: String) -> String:
	var t := Time.get_time_dict_from_system()
	var frac := fposmod(Time.get_unix_time_from_system(), 1.0)
	return "%02d:%02d:%02d.%03d +%.3f %-5s [%s] %s" % [t.hour, t.minute, t.second, int(frac * 1000.0),
			(Time.get_ticks_msec() - _start_ms) / 1000.0, LEVEL_NAMES[clampi(lvl, 0, 3)], tag, msg]


## `obj`'s script variables as "name=value, ..." (for configs), without
## the `skip` ones.
static func describe(obj: Object, skip: Array = []) -> String:
	var parts := PackedStringArray()
	for prop: Dictionary in obj.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not prop.name in skip:
			parts.append("%s=%s" % [prop.name, obj.get(prop.name)])
	return ", ".join(parts)


static func level_from_name(name: String) -> int:
	var idx := LEVEL_NAMES.find(name.to_upper())
	return idx if idx != -1 else Level.DEBUG


## Opens this session's file (deleting the oldest beyond KEEP), and starts
## capturing the engine's own log. Returns the previous session's file, ""
## if none.
static func open(p_dir: String = "") -> String:
	if _file != null:
		return ""
	if not p_dir.is_empty():
		dir = p_dir.path_join("")
	if DirAccess.make_dir_recursive_absolute(dir) != OK and dir != DIR:
		dir = DIR  # not writable: the private user data instead
		DirAccess.make_dir_recursive_absolute(dir)
	var previous := sessions()
	var stamp := Time.get_datetime_string_from_system(false, false).replace("T", "_").replace(":", "")
	path = dir + PREFIX + stamp + ".log"
	var n := 1
	while FileAccess.file_exists(path):  # two starts in one second
		n += 1
		path = dir + PREFIX + stamp + "_%d.log" % n
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		path = ""
		push_warning("Log: can't write %s (%s); logging to the console only" % [dir, error_string(FileAccess.get_open_error())])
	else:
		for line in _recent:  # anything logged before the file opened
			_file.store_line(line)
		_file.flush()
	while previous.size() >= KEEP:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(previous[0]))
		previous.remove_at(0)
	if _sink == null:
		_sink = _Sink.new()
		OS.add_logger(_sink)
	return previous[-1] if not previous.is_empty() else ""


## Writes the session end marker and closes the file.
static func close() -> void:
	i("log", SESSION_END.trim_prefix("=== ") + " after %.1f s" % ((Time.get_ticks_msec() - _start_ms) / 1000.0))
	_mutex.lock()
	if _file != null:
		_file.store_line(SESSION_END)
		_file.close()
		_file = null
	_mutex.unlock()


static func flush() -> void:
	_mutex.lock()
	if _file != null:
		_file.flush()
	_mutex.unlock()


## The session log files, oldest first.
static func sessions() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(PREFIX) and f.ends_with(".log"):
			out.append(dir + f)
	out.sort()
	return out


## Whether the log at `file` ended with the session end marker (the game
## closed normally, not a crash or a kill).
static func ended_cleanly(file: String) -> bool:
	var text := FileAccess.get_file_as_string(file)
	return text.strip_edges().ends_with(SESSION_END)


## For a bug report: the previous session's log when it didn't close
## normally (the crash), then this one's; each its last `max_lines` lines.
static func report_text(max_lines: int = RECENT) -> String:
	var out := ""
	var all := sessions()
	if all.size() >= 2 and not ended_cleanly(all[-2]):
		var lines := FileAccess.get_file_as_string(all[-2]).split("\n")
		out += "### previous session (did not close normally): %s\n%s\n\n" % [all[-2].get_file(),
				"\n".join(lines.slice(maxi(lines.size() - max_lines, 0)))]
	out += "### this session: %s\n%s" % [path.get_file(), recent_text(max_lines)]
	return out


## This session's log so far (its last `max_lines` lines).
static func recent_text(max_lines: int = RECENT) -> String:
	_mutex.lock()
	var lines := _recent.slice(maxi(_recent.size() - max_lines, 0))
	_mutex.unlock()
	return "\n".join(lines)


static func _store(line: String, flush_now: bool) -> void:
	_recent.append(line)
	if _recent.size() > RECENT + 200:
		_recent = _recent.slice(_recent.size() - RECENT)
	if _file != null:
		_file.store_line(line)
		if flush_now:
			_file.flush()


## The engine's log (print, warnings, errors, script errors) into the file.
## Called from any thread, so under the mutex; never prints (that would
## call it again).
class _Sink extends Logger:
	func _log_message(message: String, error: bool) -> void:
		Log._mutex.lock()
		if not Log._echoing:
			var msg := message.strip_edges(false, true)
			if not msg.is_empty():
				Log._store(Log.format_line(Log.Level.WARN if error else Log.Level.INFO, "engine", msg), error)
		Log._mutex.unlock()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["error", "warning", "script error", "shader error"][clampi(error_type, 0, 3)]
		var text := "%s: %s (%s:%d in %s)" % [kind, rationale if not rationale.is_empty() else code, file, line, function]
		if not rationale.is_empty() and not code.is_empty():
			text += " [%s]" % code
		for bt in script_backtraces:
			if not bt.is_empty():
				text += "\n" + bt.format(4).strip_edges(false, true)
		Log._mutex.lock()
		Log._store(Log.format_line(Log.Level.WARN if error_type == ERROR_TYPE_WARNING else Log.Level.ERROR,
				"engine", text), true)
		Log._mutex.unlock()
