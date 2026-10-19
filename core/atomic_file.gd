class_name AtomicFile
extends RefCounted
## Crash-safe file writes (PLAN §3.13).
##
## Writes go to `<path>.tmp` first, the previous file is kept as `<path>.bak`,
## and the temp file is then renamed over the target. Reads fall back to the
## backup if the main file is missing or unreadable.


static func write_text(path: String, text: String) -> Error:
	var abs_path := ProjectSettings.globalize_path(path)
	var tmp := abs_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.file_exists(abs_path):
		var err := DirAccess.copy_absolute(abs_path, abs_path + ".bak")
		if err != OK:
			return err
	return DirAccess.rename_absolute(tmp, abs_path)


## Returns the file's text, falling back to the `.bak` copy. Returns an empty
## string if neither can be read. `validator` (optional) rejects corrupt text.
static func read_text(path: String, validator: Callable = Callable()) -> String:
	var abs_path := ProjectSettings.globalize_path(path)
	for candidate in [abs_path, abs_path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var text := FileAccess.get_file_as_string(candidate)
		if text.is_empty():
			continue
		if validator.is_valid() and not validator.call(text):
			continue
		return text
	return ""
