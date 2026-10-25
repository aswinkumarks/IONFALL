extends GutTest
## The balance configuration files (docs/balance.md) load, and the bot
## levels get harder from Easy to Insane.


func test_files_load() -> void:
	assert_not_null(Balance.PLAYER)
	assert_not_null(Balance.MODES)
	assert_not_null(BotBrain.CONFIG)
	assert_gt(Balance.PLAYER.max_shield, 0.0)
	assert_gt(Balance.MODES.ffa_score_limit, 0)


func test_bot_levels_get_harder() -> void:
	var levels := BotBrain.CONFIG.difficulties
	assert_eq(levels.size(), BotBrain.DIFFICULTY_IDS.size(), "one level per difficulty")
	for i in range(1, levels.size()):
		var easier := levels[i - 1]
		var harder := levels[i]
		assert_true(harder.reaction_ticks <= easier.reaction_ticks, "%s reacts no slower" % harder.name)
		assert_true(harder.aim_error_degrees <= easier.aim_error_degrees, "%s aims no worse" % harder.name)
		assert_true(harder.recoil_control >= easier.recoil_control, "%s holds recoil no worse" % harder.name)
		assert_true(harder.turn_speed_degrees_per_second >= easier.turn_speed_degrees_per_second,
				"%s turns no slower" % harder.name)
