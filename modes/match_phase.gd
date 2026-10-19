class_name MatchPhase
extends RefCounted
## Server-owned match phases (PLAN §3.4). `match_id` stays the same for a whole
## match; `phase_seq` increments on each transition within it.

enum { WAITING, COUNTDOWN, PLAYING, POST_MATCH, SUDDEN_DEATH }

const COUNTDOWN_TICKS := 300
const POST_MATCH_TICKS := 900
const FFA_SCORE_LIMIT := 25
const FFA_TIME_LIMIT_TICKS := 36000
## Tie at the time limit: the next score change decides, for at most 2 min,
## then the match is a draw (PLAN §2.4).
const SUDDEN_DEATH_TICKS := 7200


static func allows_damage(phase: int) -> bool:
	return phase == PLAYING or phase == SUDDEN_DEATH


static func label_key(phase: int) -> String:
	return ["PHASE_WAITING", "PHASE_COUNTDOWN", "PHASE_PLAYING", "PHASE_POST_MATCH", "PHASE_SUDDEN_DEATH"][clampi(phase, 0, 4)]


## Unique top scorer, or 0 when nobody leads alone.
static func leader(scores: Dictionary) -> int:
	var best := -0x7FFFFFFF
	var who := 0
	for id in scores:
		if scores[id] > best:
			best = scores[id]
			who = id
		elif scores[id] == best:
			who = 0
	return who
