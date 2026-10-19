extends GutTest
## Profile persistence, migrations, XP and idempotent results (PLAN §3.13).

const PATH := "user://test_profile.save"
const FIXTURES := "res://tests/fixtures/"


func _row(overrides: Dictionary = {}) -> Dictionary:
	var row := {"id": 5, "bot": false, "name": "Me", "score": 10, "ticks_played": 6000, "weapon_kills": {&"pulse_rifle": 8}}
	for k in Protocol.RESULT_COUNTERS:
		row[k] = 0
	row.merge(overrides, true)
	return row


func _results(row: Dictionary, winner: int = 5, humans: int = 2, id: String = "aa-01") -> Dictionary:
	return {"result_id": id, "winner": winner, "humans": humans, "players": [row]}


func test_round_trip_and_checksum() -> void:
	var p := ProfileData.fresh()
	p.apply_results(_results(_row({"kills": 10})), 5)
	var parsed := ProfileData.from_text(p.to_text())
	assert_false(parsed.is_empty())
	assert_eq(parsed.profile.xp(), p.xp())
	assert_eq(parsed.profile.stats().vs_players.kills, 10)
	var tampered := p.to_text().replace("\\\"kills\\\":10", "\\\"kills\\\":99")
	assert_ne(tampered, p.to_text(), "the test really changed the payload")
	assert_true(ProfileData.from_text(tampered).is_empty(), "checksum mismatch rejected")
	assert_true(ProfileData.from_text("{not json").is_empty())


func test_xp_formula() -> void:
	# 10 kills (4 vs bots) + 3 assists (1 vs bot) + 100 s, completed win with 2 humans.
	var row := _row({"kills": 10, "kills_vs_bots": 4, "assists": 3, "assists_vs_bots": 1})
	assert_eq(ProfileData.xp_for(row, true, true, 2), 6 * 10 + 4 * 5 + 2 * 5 + 1 * 2 + 10 + 30 + 100)
	assert_eq(ProfileData.xp_for(row, true, true, 1), 6 * 10 + 4 * 5 + 2 * 5 + 1 * 2 + 10 + 65, "bonuses halved under 2 humans")
	assert_eq(ProfileData.xp_for(row, false, false, 2), 6 * 10 + 4 * 5 + 2 * 5 + 1 * 2 + 10, "incomplete: no bonus")


func test_results_apply_once() -> void:
	var p := ProfileData.fresh()
	var r := _results(_row({"kills": 3, "deaths": 2, "deaths_vs_bots": 1, "shots": 40, "hits": 12}))
	var gained := p.apply_results(r, 5)
	assert_gt(gained, 0)
	assert_eq(p.apply_results(r, 5), -1, "same result id is ignored")
	var s := p.stats()
	assert_eq([s.matches, s.wins, s.vs_players.deaths, s.vs_bots.deaths, s.shots, s.hits], [1, 1, 1, 1, 40, 12])
	assert_eq(s.weapon_kills.pulse_rifle, 8)


func test_applied_ids_are_capped() -> void:
	var p := ProfileData.fresh()
	for i in ProfileData.MAX_APPLIED_IDS + 20:
		p.apply_results(_results(_row(), 5, 2, "id-%d" % i), 5)
	assert_eq(p.data.applied_results.size(), ProfileData.MAX_APPLIED_IDS)
	assert_eq(p.stats().matches, ProfileData.MAX_APPLIED_IDS + 20)


func test_incomplete_and_unconfirmed() -> void:
	var p := ProfileData.fresh()
	p.apply_results(_results(_row({"kills": 2})), 5, false, false)
	assert_eq(p.stats().matches_incomplete, 1)
	assert_eq(p.stats().matches, 0)
	assert_eq(p.stats().wins, 0, "no win for an incomplete match")
	assert_eq(p.data.unconfirmed_results, 1)


func test_levels() -> void:
	assert_eq(ProfileData.level_for(0).level, 1)
	assert_eq(ProfileData.level_for(499).level, 1)
	assert_eq(ProfileData.level_for(500).level, 2)
	assert_eq(ProfileData.level_for(500 + 600).level, 3)


func test_newer_schema_is_read_only() -> void:
	var p := ProfileData.fresh()
	p.data.version = ProfileData.SCHEMA_VERSION + 1
	var parsed := ProfileData.from_text(p.to_text())
	assert_true(parsed.newer)


func test_every_fixture_migrates_to_current() -> void:
	var dir := DirAccess.open(FIXTURES)
	var found := 0
	for f in dir.get_files():
		if not f.begins_with("profile_v") or not f.ends_with(".json"):
			continue
		found += 1
		var parsed := ProfileData.from_text(FileAccess.get_file_as_string(FIXTURES + f))
		assert_false(parsed.is_empty(), "%s loads" % f)
		assert_eq(int(parsed.profile.data.version), ProfileData.SCHEMA_VERSION, "%s migrated" % f)
		assert_gt(parsed.profile.stats().vs_players.kills, 0, "%s keeps its stats" % f)
	assert_gte(found, ProfileData.SCHEMA_VERSION, "a fixture for every schema version")


func test_corrupt_save_falls_back_to_backup() -> void:
	var p := ProfileData.fresh()
	p.apply_results(_results(_row({"kills": 1}), 5, 2, "first"), 5)
	AtomicFile.write_text(PATH, p.to_text())
	p.apply_results(_results(_row({"kills": 1}), 5, 2, "second"), 5)
	AtomicFile.write_text(PATH, p.to_text())
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	var text := AtomicFile.read_text(PATH, func(t: String) -> bool: return not ProfileData.from_text(t).is_empty())
	assert_eq(ProfileData.from_text(text).profile.stats().vs_players.kills, 1, "the backup (one match) loads")
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
