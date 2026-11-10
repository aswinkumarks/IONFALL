class_name UpdateLogic
extends RefCounted
## The updater's steps that don't need the network (Updater runs them):
## version comparison, picking the release file for this platform, checking
## it against the release's SHA256SUMS, unpacking it into a staging folder
## and installing it over the game's folder.
##
## Desktop builds update themselves: the platform zip is unpacked into
## <game folder>/.update/ready/ and installed on the next start (or "Restart
## now"). Linux renames the files over the running ones; Windows can't
## replace a running game's files, so a script waits for the game to exit,
## copies them and starts it again.

const REPO := "aswinkumarks/IONFALL"
const LATEST_URL := "https://api.github.com/repos/%s/releases/latest" % REPO
## Only files from this repository's releases are downloaded.
const DOWNLOAD_PREFIX := "https://github.com/%s/releases/download/" % REPO
const STAGE_DIR := ".update"
const READY := "ready"  ## unpacked and verified, waiting to be installed
const VERSION_FILE := ".version"  ## in READY: the version it holds


## [major, minor, patch, prerelease] of "v1.2.3-rc1+meta" (prerelease "" for
## a release); [] if it isn't a version.
static func parse_version(text: String) -> Array:
	var v := text.strip_edges().trim_prefix("v").get_slice("+", 0)
	var pre := ""
	if v.contains("-"):
		pre = v.get_slice("-", 1)
		v = v.get_slice("-", 0)
	var parts := v.split(".")
	if parts.is_empty() or parts.size() > 3:
		return []
	var out := []
	for p in parts:
		if not p.is_valid_int():
			return []
		out.append(p.to_int())
	while out.size() < 3:
		out.append(0)
	out.append(pre)
	return out


## Whether version `a` is newer than `b` (semver order: a release is newer
## than its own pre-releases). Unparseable versions are never newer.
static func is_newer(a: String, b: String) -> bool:
	var va := parse_version(a)
	var vb := parse_version(b)
	if va.is_empty() or vb.is_empty():
		return false
	for i in 3:
		if va[i] != vb[i]:
			return va[i] > vb[i]
	if va[3] == vb[3]:
		return false
	if va[3] == "":
		return true  # 1.0.0 > 1.0.0-rc2
	if vb[3] == "":
		return false
	return va[3] > vb[3]


## The release file for `platform` ("linux", "windows", "android"):
## {name, url, size}, or {} if the release has none (or it isn't one of ours).
static func asset_for(release: Dictionary, platform: String) -> Dictionary:
	var suffix: String = {"linux": "-linux.zip", "windows": "-windows.zip", "android": "-android-arm64.apk"}.get(platform, "")
	if suffix.is_empty():
		return {}
	for a: Dictionary in release.get("assets", []):
		var name := str(a.get("name", ""))
		var url := str(a.get("browser_download_url", ""))
		if name.begins_with("ionfall-") and name.ends_with(suffix) and url.begins_with(DOWNLOAD_PREFIX):
			return {"name": name, "url": url, "size": int(a.get("size", 0))}
	return {}


## The SHA256SUMS file's URL in `release`, "" if none.
static func sums_url(release: Dictionary) -> String:
	for a: Dictionary in release.get("assets", []):
		var url := str(a.get("browser_download_url", ""))
		if a.get("name", "") == "SHA256SUMS" and url.begins_with(DOWNLOAD_PREFIX):
			return url
	return ""


## The hash SHA256SUMS (`sha256sum` output) lists for `file_name`, "" if none.
static func expected_sha256(sums: String, file_name: String) -> String:
	for line in sums.split("\n", false):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 2 and parts[1].trim_prefix("*").trim_prefix("./") == file_name:
			return parts[0].to_lower()
	return ""


## Unpacks `zip_path` into `<stage>/ready/` (replacing an older one) and
## writes the version it holds. Returns "" or an error.
static func unpack(zip_path: String, stage: String, version: String) -> String:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		return "can't open the download (%s)" % error_string(err)
	var tmp := stage.path_join("unpacking")
	remove_tree(tmp)
	for file in reader.get_files():
		if file.ends_with("/"):
			continue
		if file.begins_with("/") or file.contains(".."):
			reader.close()
			return "unsafe path in the download: %s" % file
		var out := tmp.path_join(file)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f == null:
			reader.close()
			return "can't write %s (%s)" % [out, error_string(FileAccess.get_open_error())]
		f.store_buffer(reader.read_file(file))
		f.close()
	reader.close()
	var vf := FileAccess.open(tmp.path_join(VERSION_FILE), FileAccess.WRITE)
	vf.store_string(version)
	vf.close()
	var ready := stage.path_join(READY)
	remove_tree(ready)
	err = DirAccess.rename_absolute(tmp, ready)
	return "" if err == OK else "can't stage the update (%s)" % error_string(err)


## The version waiting in `<stage>/ready/`, "" if none.
static func ready_version(stage: String) -> String:
	var path := stage.path_join(READY).path_join(VERSION_FILE)
	return FileAccess.get_file_as_string(path).strip_edges() if FileAccess.file_exists(path) else ""


## The files in `dir` (relative paths, recursive), without the version file.
static func list_files(dir: String, prefix: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir.path_join(prefix)):
		if prefix.is_empty() and f == VERSION_FILE:
			continue
		out.append(prefix.path_join(f))
	for d in DirAccess.get_directories_at(dir.path_join(prefix)):
		out.append_array(list_files(dir, prefix.path_join(d)))
	return out


## Linux: moves the staged files over the game's (renaming over a running
## file is safe there: the running game keeps the old one open), marks the
## executable runnable and removes the stage. Returns "" or an error.
static func install_unix(stage: String, game_dir: String, executable: String) -> String:
	var ready := stage.path_join(READY)
	for rel in list_files(ready):
		var dest := game_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var err := DirAccess.rename_absolute(ready.path_join(rel), dest)
		if err != OK:
			return "can't replace %s (%s)" % [rel, error_string(err)]
		if rel == executable or rel.ends_with(".so") or rel.ends_with(".x86_64"):
			FileAccess.set_unix_permissions(dest, 0b111_101_101)  # rwxr-xr-x
	remove_tree(stage)
	return ""


## Windows: a script that waits for process `pid` to exit, copies the
## staged files over the game's, removes the stage and starts the game.
static func windows_script(stage: String, game_dir: String, executable: String, pid: int) -> String:
	var ready := stage.path_join(READY).replace("/", "\\")
	var dest := game_dir.replace("/", "\\")
	var exe := dest + "\\" + executable
	return "\r\n".join([
		"@echo off",
		"chcp 65001 >nul",
		"rem IONFALL update: wait for the game to exit, copy the new files, start it again.",
		":wait",
		"tasklist /FI \"PID eq %d\" /NH 2>nul | find \"%d\" >nul && (ping -n 2 127.0.0.1 >nul & goto wait)" % [pid, pid],
		"del /q \"%s\\%s\" 2>nul" % [ready, VERSION_FILE],
		"xcopy \"%s\" \"%s\" /E /I /Y /Q >nul" % [ready, dest],
		"if errorlevel 1 goto start",
		"rmdir /s /q \"%s\"" % ready,
		":start",
		"start \"\" \"%s\"" % exe,
		""])


## Deletes `path` and everything under it (no error if it's missing).
static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true  # the version file
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
