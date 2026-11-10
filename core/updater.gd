extends Node
## Keeps the game up to date from its GitHub releases (UpdateLogic).
##
## Every start (release builds) it asks GitHub for the
## latest release. When it's newer:
## - Windows and Linux, Settings "updates/mode" = "install" (the default):
##   downloads this platform's zip in the background while in the main menu
##   (never during a match), checks it against the release's SHA256SUMS,
##   unpacks it next to the game and installs it on the next start, or at
##   once from the menu's "Restart now". "notify" only tells; "off" doesn't
##   check.
## - Android: Android always asks before installing an app, so the menu
##   offers the new APK's download; installs from Google Play are left to
##   Play, which updates them itself.
## - Web: the page always serves the latest build.
##
## Dev: `--update-check` checks in any build,
## `--update-from <version>` pretends to be that version, `--update-dir <dir>`
## installs into that folder instead of the game's (and doesn't restart).

signal changed

enum State { IDLE, CHECKING, AVAILABLE, DOWNLOADING, READY, FAILED }

const MENU_SCENE := "res://ui/main_menu/main_menu.tscn"

var state: int = State.IDLE
## The newer release: {version, page, notes, asset: {name, url, size}}.
var latest: Dictionary = {}
var error: String = ""
var progress: float = 0.0  ## 0..1 while downloading

var _http: HTTPRequest
var _job: Callable  ## what to do with the current request's result
var _unpack_task: int = -1
var _unpack_result: String = ""


func _ready() -> void:
	if not supported():
		return
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	_http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var job := _job
		_job = Callable()
		if job.is_valid():
			job.call(result, code, body))
	add_child(_http)
	get_tree().scene_changed.connect(_on_scene_changed)
	_start.call_deferred()


## Whether this build updates itself or tells about updates.
func supported() -> bool:
	if Platform.is_dedicated_server() or OS.has_feature("web") or platform().is_empty():
		return false
	return not OS.is_debug_build() or Platform.user_args.has("--update-check")


## "linux", "windows", "android", or "" elsewhere.
func platform() -> String:
	match OS.get_name():
		"Windows": return "windows"
		"Linux", "FreeBSD": return "linux"
		"Android": return "android"
	return ""


## "install", "notify" or "off". Android can only notify.
func mode() -> String:
	if platform() == "android":
		return "notify"
	# From the editor the "game folder" is the editor's: never install there.
	if OS.has_feature("editor") and not Platform.user_args.has("--update-dir"):
		return "notify"
	return str(Settings.get_value("updates", "mode"))


func current_version() -> String:
	return Platform.get_user_arg("--update-from", BuildInfo.version)


func game_dir() -> String:
	return Platform.get_user_arg("--update-dir", OS.get_executable_path().get_base_dir())


func stage_dir() -> String:
	return game_dir().path_join(UpdateLogic.STAGE_DIR)


## Installs the downloaded update: restarts into the new version.
func install_now() -> void:
	if state != State.READY:
		return
	Log.i("update", "installing %s now" % UpdateLogic.ready_version(stage_dir()))
	_install()


## The page to open for a manual update: the APK on Android, else the
## release page.
func download_page() -> String:
	if platform() == "android" and not latest.get("asset", {}).is_empty():
		return latest.asset.url
	return latest.get("page", "https://github.com/%s/releases/latest" % UpdateLogic.REPO)


func retry() -> void:
	if state == State.FAILED:
		error = ""
		_check()


# --- Steps ---

func _start() -> void:
	var staged := UpdateLogic.ready_version(stage_dir())
	if not staged.is_empty():
		if UpdateLogic.is_newer(staged, current_version()) and mode() == "install":
			Log.i("update", "installing %s (downloaded earlier) over %s" % [staged, current_version()])
			_install()
			return
		if not UpdateLogic.is_newer(staged, current_version()):
			Log.i("update", "removing the installed or older update %s" % staged)
			UpdateLogic.remove_tree(stage_dir())
	elif DirAccess.dir_exists_absolute(stage_dir()):
		UpdateLogic.remove_tree(stage_dir())  # Windows' install script, or a download cut short
	if mode() == "off":
		Log.i("update", "update checks are off")
		return
	_check()


## One request to GitHub's API per start (it allows 60 an hour per address).
func _check() -> void:
	_set_state(State.CHECKING)
	Log.i("update", "checking for a newer version than %s" % current_version())
	_job = _on_latest
	var err := _http.request(UpdateLogic.LATEST_URL, ["Accept: application/vnd.github+json",
			"User-Agent: IONFALL-updater", "X-GitHub-Api-Version: 2022-11-28"])
	if err != OK:
		_job = Callable()
		_fail("can't reach GitHub (%s)" % error_string(err))


func _on_latest(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("the update check failed (%s, HTTP %d)" % [_result_name(result), code], false)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not (data as Dictionary).has("tag_name"):
		_fail("the update check got an unexpected answer", false)
		return
	var release := {"version": str(data.tag_name).trim_prefix("v"), "page": str(data.get("html_url", "")),
			"notes": str(data.get("body", "")).left(2000), "asset": UpdateLogic.asset_for(data, platform()),
			"sums": UpdateLogic.sums_url(data)}
	if not UpdateLogic.is_newer(release.version, current_version()):
		Log.i("update", "up to date (latest %s, running %s)" % [release.version, current_version()])
		_set_state(State.IDLE)
		return
	_found(release)


func _found(release: Dictionary) -> void:
	latest = release
	Log.i("update", "%s is available (running %s), %s" % [release.version, current_version(),
			"file %s, %.0f MB" % [release.asset.name, release.asset.size / 1048576.0] if not release.asset.is_empty()
			else "no file for %s" % platform()])
	if platform() == "android" and _installed_from_play():
		Log.i("update", "installed from Google Play: Play updates it")
		_set_state(State.IDLE)
		return
	_set_state(State.AVAILABLE)
	if mode() == "install" and platform() != "android":
		if release.asset.is_empty() or str(release.get("sums", "")).is_empty():
			_fail("the release has no %s download" % platform())
		elif not _writable(game_dir()):
			Log.w("update", "can't write to %s: the menu offers the download page instead" % game_dir())
		else:
			_download_if_in_menu()


func _download_if_in_menu() -> void:
	var scene := get_tree().current_scene
	if state != State.AVAILABLE or scene == null or scene.scene_file_path != MENU_SCENE:
		return
	DirAccess.make_dir_recursive_absolute(stage_dir())
	_set_state(State.DOWNLOADING)
	progress = 0.0
	Log.i("update", "downloading %s" % latest.asset.url)
	_http.download_file = stage_dir().path_join("download.part")
	_job = _on_downloaded
	var err := _http.request(latest.asset.url, ["User-Agent: IONFALL-updater"])
	if err != OK:
		_job = Callable()
		_fail("can't start the download (%s)" % error_string(err))


## The download stops during matches (it would compete with the game's
## traffic) and starts again from the menu.
func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	var in_menu := scene != null and scene.scene_file_path == MENU_SCENE
	if state == State.DOWNLOADING and not in_menu:
		Log.i("update", "pausing the download outside the menu (%.0f%% done)" % (progress * 100.0))
		_http.cancel_request()
		_job = Callable()
		_http.download_file = ""
		_set_state(State.AVAILABLE)
	elif state == State.AVAILABLE and in_menu and mode() == "install":
		_download_if_in_menu()


func _process(_delta: float) -> void:
	if state == State.DOWNLOADING and _http != null:
		var total := _http.get_body_size()
		if total > 0:
			var p := float(_http.get_downloaded_bytes()) / total
			if absf(p - progress) >= 0.01:
				progress = p
				changed.emit()
	if _unpack_task != -1 and WorkerThreadPool.is_task_completed(_unpack_task):
		WorkerThreadPool.wait_for_task_completion(_unpack_task)
		_unpack_task = -1
		if not _unpack_result.is_empty():
			_fail(_unpack_result)
		else:
			Log.i("update", "%s is ready: installs on the next start" % latest.version)
			_set_state(State.READY)


func _on_downloaded(result: int, code: int, _body: PackedByteArray) -> void:
	_http.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("the download failed (%s, HTTP %d)" % [_result_name(result), code])
		return
	Log.i("update", "downloaded %.0f MB, checking it" % (_http.get_downloaded_bytes() / 1048576.0))
	_job = _on_sums
	var err := _http.request(latest.sums, ["User-Agent: IONFALL-updater"])
	if err != OK:
		_job = Callable()
		_fail("can't fetch the checksums (%s)" % error_string(err))


func _on_sums(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("can't fetch the checksums (%s, HTTP %d)" % [_result_name(result), code])
		return
	var expected := UpdateLogic.expected_sha256(body.get_string_from_utf8(), latest.asset.name)
	if expected.is_empty():
		_fail("the release lists no checksum for %s" % latest.asset.name)
		return
	# Hashing and unpacking ~100 MB takes seconds: off the main thread.
	var part := stage_dir().path_join("download.part")
	var stage := stage_dir()
	var version: String = latest.version
	_unpack_result = ""
	_unpack_task = WorkerThreadPool.add_task(func() -> void:
		var actual := FileAccess.get_sha256(part)
		if actual != expected:
			_unpack_result = "the download is damaged (checksum %s, expected %s)" % [actual.left(12), expected.left(12)]
		else:
			_unpack_result = UpdateLogic.unpack(part, stage, version)
		DirAccess.remove_absolute(part))


func _install() -> void:
	var stage := stage_dir()
	var exe := OS.get_executable_path().get_file()
	var dev := Platform.user_args.has("--update-dir")
	if platform() == "windows":
		var script := stage.path_join("apply.cmd")
		var f := FileAccess.open(script, FileAccess.WRITE)
		if f == null:
			_fail("can't write the install script (%s)" % error_string(FileAccess.get_open_error()))
			return
		f.store_string(UpdateLogic.windows_script(stage, game_dir(), exe, OS.get_process_id()))
		f.close()
		Log.i("update", "installing with %s after the game exits" % script)
		if not dev:
			OS.create_process("cmd.exe", ["/c", ProjectSettings.globalize_path(script)])
			get_tree().quit()
		return
	var err := UpdateLogic.install_unix(stage, game_dir(), exe)
	if not err.is_empty():
		_fail(err)
		return
	Log.i("update", "installed into %s%s" % [game_dir(), " (dev: no restart)" if dev else ": restarting"])
	if not dev:
		var args := OS.get_cmdline_args()
		if not OS.get_cmdline_user_args().is_empty():
			args.append("--")
			args.append_array(OS.get_cmdline_user_args())
		OS.set_restart_on_exit(true, args)
		get_tree().quit()
	else:
		_set_state(State.IDLE)


func _fail(reason: String, shown: bool = true) -> void:
	error = reason
	Log.w("update", reason)
	_set_state(State.FAILED if shown else State.IDLE)


func _set_state(s: int) -> void:
	state = s
	changed.emit()


func _writable(dir: String) -> bool:
	var probe := dir.path_join(UpdateLogic.STAGE_DIR).path_join(".probe")
	DirAccess.make_dir_recursive_absolute(probe.get_base_dir())
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Android: installed by the Play Store (which updates it) rather than from
## the APK.
func _installed_from_play() -> bool:
	if not Engine.has_singleton("AndroidRuntime"):
		return false
	var ctx: Variant = Engine.get_singleton("AndroidRuntime").call("getApplicationContext")
	if ctx == null:
		return false
	var pm: Variant = ctx.call("getPackageManager")
	var installer: Variant = pm.call("getInstallerPackageName", ctx.call("getPackageName")) if pm != null else null
	Log.d("update", "installed by %s" % installer)
	return str(installer) == "com.android.vending"


static func _result_name(result: int) -> String:
	return ["ok", "chunked body", "can't connect", "can't resolve", "connection error", "TLS error", "no response",
			"body too big", "body decompression failed", "request failed", "download file can't open",
			"download file write error", "too many redirects", "timeout"][clampi(result, 0, 13)]
