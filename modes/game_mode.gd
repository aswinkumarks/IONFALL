class_name GameMode
extends RefCounted
## Match modes (PLAN §2.4): free-for-all, team deathmatch, capture the flag
## and co-op waves. Victory is a score: a player's in FFA, a team's in the
## team modes (kills in TDM, captures in CTF, waves cleared in co-op).

enum { FFA, TDM, CTF, WAVES }

## Appended only: the index goes over the wire.
const IDS := ["ffa", "tdm", "ctf", "waves"]
const NAME_KEYS := ["MODE_FFA", "MODE_TDM", "MODE_CTF", "MODE_WAVES"]
## Short names for the mode choice buttons.
const CHIP_KEYS := ["MODE_FFA", "MODE_TDM_SHORT", "MODE_CTF_SHORT", "MODE_WAVES"]
## Team 0 (cyan) spawns on the west half, team 1 (orange) on the east. In
## co-op the humans are team 0 and the waves team 1.
const TEAM_COLORS := [Color(0.35, 0.9, 1.0), Color(1.0, 0.6, 0.25)]
const TEAM_KEYS := ["TEAM_CYAN", "TEAM_ORANGE"]
## Each team also has a shape (PLAN §3.16: never colour alone): cyan a
## diamond, orange a triangle; points around the origin, radius 1.
const TEAM_SHAPES := [
	[Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)],
	[Vector2(0, -1), Vector2(0.95, 0.75), Vector2(-0.95, 0.75)],
]
const NO_TEAM := 255
## Co-op: the humans' team and the waves' team.
const HUMANS := 0
const WAVE_TEAM := 1


## Modes with two teams (team spawns, team scores, no friendly fire).
static func is_team_mode(mode: int) -> bool:
	return mode == TDM or mode == CTF or mode == WAVES


## The score that wins: 25 kills (FFA), 50 team kills (TDM), 3 captures
## (CTF), 10 waves cleared (co-op).
static func score_limit(mode: int) -> int:
	match mode:
		TDM:
			return 50
		CTF:
			return 3
		WAVES:
			return WAVE_COUNT
	return 25


## Co-op: clearing this many waves wins.
const WAVE_COUNT := 10


## Respawn delay (PLAN §2.5): FFA 3 s, team modes 5 s (co-op: at the end
## of the wave instead, see WaveDirector).
static func respawn_ticks(mode: int) -> int:
	return 180 if mode == FFA else 300


static func from_id(id: String) -> int:
	return maxi(IDS.find(id), 0)


## The side of the map a team spawns on (-1 west, +1 east).
static func team_side(team: int) -> float:
	return -1.0 if team == 0 else 1.0
