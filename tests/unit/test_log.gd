extends GutTest
## Log: session log lines, levels, the engine's own log captured, clean-exit
## detection and the bug report text.


func test_lines_have_time_level_and_tag() -> void:
	var line := Log.format_line(Log.Level.WARN, "net", "lost the server")
	var re := RegEx.create_from_string("^\\d\\d:\\d\\d:\\d\\d\\.\\d{3} \\+\\d+\\.\\d{3} WARN  \\[net\\] lost the server$")
	assert_not_null(re.search(line), line)


func test_level_filters_and_recent_text_keeps_lines() -> void:
	var before := Log.level
	Log.level = Log.Level.INFO
	Log.d("test", "hidden detail %d" % get_instance_id())
	Log.i("test", "shown line %d" % get_instance_id())
	Log.level = before
	var text := Log.recent_text()
	assert_false(text.contains("hidden detail %d" % get_instance_id()), "below the level: not logged")
	assert_true(text.contains("shown line %d" % get_instance_id()))


func test_the_engines_log_is_captured() -> void:
	print("plain print %d" % get_instance_id())
	assert_true(Log.recent_text().contains("[engine] plain print %d" % get_instance_id()), "print() goes into the log")


func test_the_session_file_is_open_and_written() -> void:
	assert_false(Log.path.is_empty(), "LogService opened a session file")
	Log.i("test", "on disk %d" % get_instance_id())
	Log.flush()
	assert_true(FileAccess.get_file_as_string(Log.path).contains("on disk %d" % get_instance_id()))
	assert_true(Log.sessions().has(Log.path), "listed with the sessions")


func test_clean_exit_marker() -> void:
	var clean := "user://test_log_clean.log"
	var crashed := "user://test_log_crashed.log"
	var f := FileAccess.open(clean, FileAccess.WRITE)
	f.store_line("12:00:00.000 +1.000 INFO  [log] session end after 1.0 s")
	f.store_line(Log.SESSION_END)
	f.close()
	f = FileAccess.open(crashed, FileAccess.WRITE)
	f.store_line("12:00:00.000 +1.000 INFO  [match] running")
	f.close()
	assert_true(Log.ended_cleanly(clean))
	assert_false(Log.ended_cleanly(crashed))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(clean))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(crashed))


func test_report_has_this_session() -> void:
	Log.i("test", "for the report %d" % get_instance_id())
	var report := Log.report_text()
	assert_true(report.contains("### this session: %s" % Log.path.get_file()))
	assert_true(report.contains("for the report %d" % get_instance_id()))


func test_describe_lists_script_variables() -> void:
	var config := MatchConfig.new()
	config.map = "spire"
	var text := Log.describe(config, ["team_plan"])
	assert_true(text.contains("map=spire"), text)
	assert_false(text.contains("team_plan="), "skipped")


func test_level_names() -> void:
	assert_eq(Log.level_from_name("warn"), Log.Level.WARN)
	assert_eq(Log.level_from_name("nonsense"), Log.Level.DEBUG)
