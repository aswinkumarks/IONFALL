extends GutTest
## UpdateLogic: versions, the release's files, checksums, unpacking and
## installing an update over a game folder.

const ROOT := "user://test_update"


func after_each() -> void:
	UpdateLogic.remove_tree(ROOT)


func test_version_order() -> void:
	assert_true(UpdateLogic.is_newer("0.9.7", "0.9.6"))
	assert_true(UpdateLogic.is_newer("v1.0", "0.9.12"))
	assert_true(UpdateLogic.is_newer("0.10.0", "0.9.9"), "numeric, not text order")
	assert_true(UpdateLogic.is_newer("1.0.0", "1.0.0-rc2"), "a release beats its pre-release")
	assert_true(UpdateLogic.is_newer("1.0.0-rc2", "1.0.0-rc1"))
	assert_false(UpdateLogic.is_newer("1.0.0-rc2", "1.0.0"))
	assert_false(UpdateLogic.is_newer("0.9.7", "0.9.7+clockfix"), "build metadata doesn't count")
	assert_false(UpdateLogic.is_newer("0.9.6", "0.9.7"))
	assert_false(UpdateLogic.is_newer("garbage", "0.9.7"))
	assert_true(UpdateLogic.is_newer("1.0.0", "1.0.0-dev"), "a dev build of 1.0.0 is older than 1.0.0")


func _release() -> Dictionary:
	var base := UpdateLogic.DOWNLOAD_PREFIX + "v0.9.7/"
	return {"tag_name": "v0.9.7", "assets": [
		{"name": "ionfall-0.9.7-android-arm64.apk", "browser_download_url": base + "ionfall-0.9.7-android-arm64.apk", "size": 3},
		{"name": "ionfall-0.9.7-linux.zip", "browser_download_url": base + "ionfall-0.9.7-linux.zip", "size": 2},
		{"name": "ionfall-0.9.7-windows.zip", "browser_download_url": "https://example.com/evil.zip", "size": 1},
		{"name": "SHA256SUMS", "browser_download_url": base + "SHA256SUMS", "size": 376},
	]}


func test_picks_this_platforms_file_from_our_releases_only() -> void:
	assert_eq(UpdateLogic.asset_for(_release(), "linux").name, "ionfall-0.9.7-linux.zip")
	assert_eq(UpdateLogic.asset_for(_release(), "android").size, 3)
	assert_true(UpdateLogic.asset_for(_release(), "windows").is_empty(), "not a download from this repository")
	assert_true(UpdateLogic.asset_for(_release(), "web").is_empty())
	assert_true(UpdateLogic.sums_url(_release()).ends_with("/v0.9.7/SHA256SUMS"))


func test_checksum_lookup() -> void:
	var sums := "aa11  ./ionfall-0.9.7-linux.zip\nBB22  ./ionfall-0.9.7-windows.zip\ncc33 *ionfall-0.9.7-android-arm64.apk\n"
	assert_eq(UpdateLogic.expected_sha256(sums, "ionfall-0.9.7-linux.zip"), "aa11")
	assert_eq(UpdateLogic.expected_sha256(sums, "ionfall-0.9.7-windows.zip"), "bb22", "lower case")
	assert_eq(UpdateLogic.expected_sha256(sums, "ionfall-0.9.7-android-arm64.apk"), "cc33")
	assert_eq(UpdateLogic.expected_sha256(sums, "ionfall-0.9.7-web.zip"), "")


func _zip(path: String, files: Dictionary) -> void:
	var z := ZIPPacker.new()
	assert_eq(z.open(path), OK)
	for name: String in files:
		z.start_file(name)
		z.write_file((files[name] as String).to_utf8_buffer())
		z.close_file()
	z.close()


func test_unpacks_and_installs_over_the_game() -> void:
	var game := ROOT.path_join("game")
	var stage := game.path_join(UpdateLogic.STAGE_DIR)
	DirAccess.make_dir_recursive_absolute(stage)
	for f: Array in [["ionfall.x86_64", "old exe"], ["ionfall.pck", "old pck"], ["keep.txt", "mine"]]:
		var w := FileAccess.open(game.path_join(f[0]), FileAccess.WRITE)
		w.store_string(f[1])
		w.close()
	var zip := stage.path_join("download.part")
	_zip(zip, {"ionfall.x86_64": "new exe", "ionfall.pck": "new pck", "lib/libionfall_native.so": "new lib"})
	assert_eq(UpdateLogic.unpack(zip, stage, "0.9.7"), "")
	assert_eq(UpdateLogic.ready_version(stage), "0.9.7")
	assert_eq(UpdateLogic.install_unix(stage, game, "ionfall.x86_64"), "")
	assert_eq(FileAccess.get_file_as_string(game.path_join("ionfall.x86_64")), "new exe")
	assert_eq(FileAccess.get_file_as_string(game.path_join("ionfall.pck")), "new pck")
	assert_eq(FileAccess.get_file_as_string(game.path_join("lib/libionfall_native.so")), "new lib")
	assert_eq(FileAccess.get_file_as_string(game.path_join("keep.txt")), "mine", "other files stay")
	assert_false(DirAccess.dir_exists_absolute(stage), "the stage is removed")
	if OS.get_name() == "Linux":
		assert_ne(FileAccess.get_unix_permissions(game.path_join("ionfall.x86_64")) & FileAccess.UNIX_EXECUTE_OWNER, 0,
				"the executable stays runnable")


func test_refuses_paths_outside_the_stage() -> void:
	var stage := ROOT.path_join(UpdateLogic.STAGE_DIR)
	DirAccess.make_dir_recursive_absolute(stage)
	var zip := stage.path_join("download.part")
	_zip(zip, {"../escape.txt": "x"})
	assert_string_contains(UpdateLogic.unpack(zip, stage, "0.9.7"), "unsafe path")
	assert_eq(UpdateLogic.ready_version(stage), "")


func test_windows_script_waits_copies_and_restarts() -> void:
	var script := UpdateLogic.windows_script("C:/Games/IONFALL/.update", "C:/Games/IONFALL", "IONFALL.exe", 4242)
	assert_string_contains(script, "PID eq 4242")
	assert_string_contains(script, "xcopy \"C:\\Games\\IONFALL\\.update\\ready\" \"C:\\Games\\IONFALL\" /E /I /Y")
	assert_string_contains(script, "start \"\" \"C:\\Games\\IONFALL\\IONFALL.exe\"")


func test_release_notes_preview() -> void:
	var notes := "IONFALL 0.9.7: intro text.\n\n## What's new\n### Graphics\n- **Sharper** characters, see [the PR](https://x/1).\n* Brighter `maps`\n- " + "long ".repeat(40) + "\n- four\n- five"
	var preview := UpdateDialog._notes_preview(notes)
	var lines := preview.split("\n")
	assert_eq(lines.size(), 4, "the first four bullets only")
	assert_eq(lines[0], "• Sharper characters, see the PR.")
	assert_eq(lines[1], "• Brighter maps")
	assert_true(lines[2].ends_with("…") and lines[2].length() <= 115, "long items cut short")
