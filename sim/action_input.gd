class_name ActionInput
extends RefCounted
## Press-counter rules (PLAN §3.2):
## - the difference between a command's counter and the last processed value
##   is the number of new presses (counters wrap at 256);
## - at most one execution per action type per tick, extras carry over;
## - deltas above MAX_DELTA are discarded and counted as anomalies.

const MAX_DELTA := 2


## Returns a bitmask of `PlayerCommand.Action` values that execute this tick.
## Updates `state.last_presses`, `state.pending_presses` and anomalies.
static func consume(state: PlayerSimState, cmd: PlayerCommand) -> int:
	var executed := 0
	for a in PlayerCommand.ACTION_COUNT:
		var delta := (cmd.presses[a] - state.last_presses[a]) & 0xFF
		if delta > 0:
			if delta > MAX_DELTA:
				state.input_anomalies += 1
				delta = MAX_DELTA
			state.pending_presses[a] = mini(state.pending_presses[a] + delta, MAX_DELTA)
			state.last_presses[a] = cmd.presses[a]
		if state.pending_presses[a] > 0:
			state.pending_presses[a] -= 1
			executed |= 1 << a
	return executed


static func has(executed: int, action: int) -> bool:
	return (executed & (1 << action)) != 0
