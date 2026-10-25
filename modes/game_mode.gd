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
## The colours a host can give a team; team 0 defaults to the first, team 1
## to the second. Appended only: the index goes over the wire.
const TEAM_PALETTE := [Color(0.35, 0.9, 1.0), Color(1.0, 0.6, 0.25), Color(1.0, 0.32, 0.36), Color(0.4, 0.95, 0.45),
		Color(0.72, 0.5, 1.0), Color(1.0, 0.88, 0.3), Color(1.0, 0.45, 0.8), Color(0.92, 0.95, 1.0)]
const DEFAULT_TEAM_COLORS: PackedInt32Array = [0, 1]
const TEAM_KEYS := ["TEAM_CYAN", "TEAM_ORANGE"]
const MAX_TEAM_NAME := 16  ## characters
## The current match's team names and colours, as the host set them in the
## lobby: a name "" is the default (TEAM_KEYS), a colour a TEAM_PALETTE index.
## Set when a match starts.
static var team_names := PackedStringArray(["", ""])
static var team_colors := DEFAULT_TEAM_COLORS
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


## The score that wins: kills (FFA), team kills (TDM), captures (CTF),
## waves cleared (co-op); Balance.MODES (data/modes.tres).
static func score_limit(mode: int) -> int:
	match mode:
		TDM:
			return Balance.MODES.tdm_score_limit
		CTF:
			return Balance.MODES.ctf_score_limit
		WAVES:
			return Balance.MODES.wave_count
	return Balance.MODES.ffa_score_limit


## Respawn delay (PLAN §2.5), from Balance.MODES (co-op: at the end of the
## wave instead, see WaveDirector).
static func respawn_ticks(mode: int) -> int:
	return Balance.MODES.ffa_respawn_ticks if mode == FFA else Balance.MODES.team_respawn_ticks


## Team `team`'s name: `names[team]` if the host gave one, else the default.
static func team_name(team: int, names: PackedStringArray = PackedStringArray()) -> String:
	if names.is_empty():
		names = team_names
	var custom := names[team] if team < names.size() else ""
	return custom if not custom.is_empty() else TranslationServer.translate(TEAM_KEYS[clampi(team, 0, 1)])


## Team `team`'s colour: from `picks` (TEAM_PALETTE indices) if given, else
## the current match's.
static func team_color(team: int, picks: PackedInt32Array = PackedInt32Array()) -> Color:
	if picks.is_empty():
		picks = team_colors
	return TEAM_PALETTE[picks[clampi(team, 0, 1)]]


## Received or chosen colours made valid: two different palette indices
## (else the defaults).
static func clean_team_colors(picks: PackedInt32Array) -> PackedInt32Array:
	if picks.size() != 2 or picks[0] == picks[1] or picks[0] < 0 or picks[1] < 0 \
			or picks[0] >= TEAM_PALETTE.size() or picks[1] >= TEAM_PALETTE.size():
		return DEFAULT_TEAM_COLORS
	return picks


## A typed or received team name made safe to show: no control characters,
## at most MAX_TEAM_NAME long; "" (the default) if nothing is left.
static func clean_team_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	return out.left(MAX_TEAM_NAME).strip_edges()


static func from_id(id: String) -> int:
	return maxi(IDS.find(id), 0)


## The side of the map a team spawns on (-1 west, +1 east).
static func team_side(team: int) -> float:
	return -1.0 if team == 0 else 1.0
