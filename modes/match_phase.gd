class_name MatchPhase
extends RefCounted
## Server-owned match phases (PLAN §3.4). `match_id` stays the same for a whole
## match; `phase_seq` increments on each transition within it.

enum { WAITING, COUNTDOWN, PLAYING, POST_MATCH }

const COUNTDOWN_TICKS := 300
const POST_MATCH_TICKS := 900
const FFA_SCORE_LIMIT := 25
const FFA_TIME_LIMIT_TICKS := 36000


static func allows_damage(phase: int) -> bool:
	return phase == PLAYING


static func label_key(phase: int) -> String:
	return ["PHASE_WAITING", "PHASE_COUNTDOWN", "PHASE_PLAYING", "PHASE_POST_MATCH"][clampi(phase, 0, 3)]
