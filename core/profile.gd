extends Node
## Profile service (PLAN §3.13): loads `user://profile.save` at startup with
## the AtomicFile fallback chain (main → .bak → new profile, keeping the
## corrupt file for diagnostics) and saves after every change.

signal changed

const PATH := "user://profile.save"

var data: ProfileData
## Written by a newer build: shown, but never overwritten.
var read_only: bool = false


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	read_only = false
	var text := AtomicFile.read_text(PATH, func(t: String) -> bool: return not ProfileData.from_text(t).is_empty())
	if text.is_empty():
		if FileAccess.file_exists(PATH) or FileAccess.file_exists(PATH + ".bak"):
			_keep_corrupt()
		else:
			Log.i("profile", "no saved profile: starting a new one")
		data = ProfileData.fresh()
		return
	var parsed := ProfileData.from_text(text)
	data = parsed.profile
	read_only = parsed.newer
	if read_only:
		Log.w("profile", "saved by a newer version (schema %s); progress won't be saved." % data.data.version)
	else:
		Log.i("profile", "loaded (%d bytes)" % text.length())


func save() -> Error:
	if read_only or not Platform.storage_available:
		return ERR_UNAVAILABLE
	var err := AtomicFile.write_text(PATH, data.to_text())
	if err != OK:
		Log.e("profile", "saving failed: %s" % error_string(err))
	else:
		Log.d("profile", "saved")
	changed.emit()
	return err


## Applies match results for the local player and saves. Returns XP gained
## (-1 if already applied).
func apply_results(results: Dictionary, player_id: int, completed: bool = true, confirmed: bool = true) -> int:
	var gained := data.apply_results(results, player_id, completed, confirmed)
	Log.i("profile", "results %s for player %d: %s (completed %s, confirmed %s)" % [results.get("result_id", "?"),
			player_id, "+%d XP" % gained if gained >= 0 else "already applied", completed, confirmed])
	if gained >= 0:
		save()
	return gained


func _keep_corrupt() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	for suffix in ["", ".bak"]:
		var p := ProjectSettings.globalize_path(PATH + suffix)
		if FileAccess.file_exists(p):
			DirAccess.rename_absolute(p, p + ".corrupt-" + stamp)
	Log.w("profile", "unreadable save kept as *.corrupt-%s; starting a new profile." % stamp)
