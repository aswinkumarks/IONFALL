extends GutTest


func _state() -> PlayerSimState:
	return PlayerSimState.new()


func test_shield_absorbs_first_and_overflow_goes_to_health() -> void:
	var s := _state()
	Health.apply(s, 90.0, false, 1.5, false)
	assert_eq(s.shield, 10.0)
	assert_eq(s.health, 100.0)
	Health.apply(s, 30.0, false, 1.5, false)
	assert_eq(s.shield, 0.0)
	assert_eq(s.health, 80.0, "20 overflow carries into health in the same hit")


func test_headshot_multiplier_only_applies_to_health_damage() -> void:
	var s := _state()
	var r := Health.apply(s, 20.0, true, 2.0, false)
	assert_eq(r.shield_damage, 20.0, "no multiplier against shield")
	s.shield = 0.0
	Health.apply(s, 20.0, true, 2.0, false)
	assert_eq(s.health, 60.0, "x2 against health")


func test_precision_headshot_goes_through_shield() -> void:
	var s := _state()
	var r := Health.apply(s, 110.0, true, 2.0, true)
	assert_true(r.killed, "Rail Sniper headshot (110 x2 = 220) kills from full")


func test_regen_delays_are_in_ticks() -> void:
	var s := _state()
	Health.apply(s, 150.0, false, 1.0, false)
	for i in Balance.PLAYER.shield_delay_ticks:
		Health.tick_regen(s)
	assert_eq(s.shield, 0.0, "no shield regen during the 300-tick delay")
	Health.tick_regen(s)
	assert_almost_eq(s.shield, 10.0 / 60.0, 0.0001, "shield recharges at 10/s after the delay")


func test_health_waits_for_a_full_shield() -> void:
	var s := _state()
	Health.apply(s, 150.0, false, 1.0, false)
	# 5 s delay, then 10 s to refill the shield at 10/s.
	for i in Balance.PLAYER.shield_delay_ticks + 599:
		Health.tick_regen(s)
	assert_eq(s.health, 50.0, "no health regen while the shield is recharging")
	assert_lt(s.shield, Balance.PLAYER.max_shield)
	Health.tick_regen(s)
	assert_eq(s.shield, Balance.PLAYER.max_shield, "shield full after 10 s")
	assert_almost_eq(s.health, 50.0 + 5.0 / 60.0, 0.001, "then health at 5/s, from that tick")


func test_damage_resets_both_regen_timers() -> void:
	var s := _state()
	Health.apply(s, 150.0, false, 1.0, false)
	for i in 300:
		Health.tick_regen(s)
	Health.apply(s, 1.0, false, 1.0, false)
	assert_eq(s.shield_delay_ticks, Balance.PLAYER.shield_delay_ticks)
	assert_eq(s.health_delay_ticks, Balance.PLAYER.health_delay_ticks)


func test_spawn_protection_blocks_damage() -> void:
	var s := _state()
	s.spawn_protection_ticks = 10
	var r := Health.apply(s, 500.0, false, 1.0, false)
	assert_true(r.blocked)
	assert_eq(s.health, 100.0)
