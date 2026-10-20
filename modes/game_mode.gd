class_name GameMode
extends RefCounted
## Match modes (PLAN §2.4): free-for-all and team deathmatch. Victory is a
## score: a player's in FFA, a team's in TDM.

enum { FFA, TDM }

const IDS := ["ffa", "tdm"]
const NAME_KEYS := ["MODE_FFA", "MODE_TDM"]
## Team 0 (cyan) spawns on the west half, team 1 (orange) on the east.
const TEAM_COLORS := [Color(0.35, 0.9, 1.0), Color(1.0, 0.6, 0.25)]
const TEAM_KEYS := ["TEAM_CYAN", "TEAM_ORANGE"]
const NO_TEAM := 255


static func score_limit(mode: int) -> int:
	return 50 if mode == TDM else 25


## Respawn delay (PLAN §2.5): FFA 3 s, TDM 5 s.
static func respawn_ticks(mode: int) -> int:
	return 300 if mode == TDM else 180


static func from_id(id: String) -> int:
	return maxi(IDS.find(id), 0)


## The side of the map a team spawns on (-1 west, +1 east).
static func team_side(team: int) -> float:
	return -1.0 if team == 0 else 1.0
