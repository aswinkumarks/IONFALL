extends GutTest

const PATH := "user://test_atomic_file.txt"


func before_each() -> void:
	_cleanup()


func after_all() -> void:
	_cleanup()


func test_write_then_read() -> void:
	assert_eq(AtomicFile.write_text(PATH, "hello"), OK)
	assert_eq(AtomicFile.read_text(PATH), "hello")


func test_second_write_keeps_backup() -> void:
	AtomicFile.write_text(PATH, "first")
	AtomicFile.write_text(PATH, "second")
	assert_eq(AtomicFile.read_text(PATH), "second")
	assert_eq(FileAccess.get_file_as_string(PATH + ".bak"), "first")


func test_corrupt_main_file_falls_back_to_backup() -> void:
	AtomicFile.write_text(PATH, "good")
	AtomicFile.write_text(PATH, "good-2")
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("CORRUPT")
	f.close()
	var is_good := func(t: String) -> bool: return t.begins_with("good")
	assert_eq(AtomicFile.read_text(PATH, is_good), "good")


func test_missing_file_reads_empty() -> void:
	assert_eq(AtomicFile.read_text(PATH), "")


func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var p := ProjectSettings.globalize_path(PATH + suffix)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
