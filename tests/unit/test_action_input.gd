extends GutTest

const JUMP := PlayerCommand.Action.JUMP


func _cmd(jump_counter: int) -> PlayerCommand:
	var c := PlayerCommand.new()
	c.presses[JUMP] = jump_counter
	return c


func test_one_press_executes_once() -> void:
	var s := PlayerSimState.new()
	assert_true(ActionInput.has(ActionInput.consume(s, _cmd(1)), JUMP))
	assert_false(ActionInput.has(ActionInput.consume(s, _cmd(1)), JUMP), "same counter = no new press")


func test_counter_wraps_at_256() -> void:
	var s := PlayerSimState.new()
	s.last_presses[JUMP] = 255
	assert_true(ActionInput.has(ActionInput.consume(s, _cmd(0)), JUMP), "255 -> 0 is one press")
	assert_eq(s.input_anomalies, 0)


func test_two_presses_execute_on_consecutive_ticks() -> void:
	var s := PlayerSimState.new()
	assert_true(ActionInput.has(ActionInput.consume(s, _cmd(2)), JUMP))
	assert_true(ActionInput.has(ActionInput.consume(s, _cmd(2)), JUMP), "second press carries over")
	assert_false(ActionInput.has(ActionInput.consume(s, _cmd(2)), JUMP))


func test_delta_above_two_is_capped_and_counted() -> void:
	var s := PlayerSimState.new()
	ActionInput.consume(s, _cmd(5))
	assert_eq(s.input_anomalies, 1)
	assert_true(ActionInput.has(ActionInput.consume(s, _cmd(5)), JUMP))
	assert_false(ActionInput.has(ActionInput.consume(s, _cmd(5)), JUMP), "only 2 executions total")


func test_lost_packets_do_not_lose_presses() -> void:
	# The client pressed jump in tick 10's command, but ticks 10-12 were lost;
	# tick 13's command still carries the incremented counter.
	var s := PlayerSimState.new()
	ActionInput.consume(s, _cmd(0))
	assert_true(ActionInput.has(ActionInput.consume(s, _cmd(1)), JUMP))
