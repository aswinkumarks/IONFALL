class_name ProfileData
extends RefCounted
## The local player profile (PLAN §3.13): versioned schema with migrations,
## checksum (detects corruption only; LAN progression is local-trust), stats
## split vs players / vs bots, XP and levels, and idempotent application of
## match results (each result id once; the last 200 ids are kept).

const SCHEMA_VERSION := 1
const MAX_APPLIED_IDS := 200
const TICK_RATE := 60  ## simulation ticks per second (sim/sim.gd), for time played

## XP (PLAN §3.13, provisional). Bot-related values are halved (PLAN §2.7).
const XP_KILL := 10
const XP_ASSIST := 5
const XP_PER_10_SECONDS := 1
const XP_WIN := 100
const XP_COMPLETE := 30

## Migrations: version N -> N + 1. Add one function per schema change and a
## fixture in tests/fixtures/profile_vN.json (tests load every fixture).
const MIGRATIONS := {}

var data: Dictionary = {}


static func fresh() -> ProfileData:
	var p := ProfileData.new()
	p.data = {
		"version": SCHEMA_VERSION,
		"created_unix": int(Time.get_unix_time_from_system()),
		"xp": 0,
		"stats": _empty_stats(),
		"applied_results": [],
		"unconfirmed_results": 0,
	}
	return p


static func _empty_stats() -> Dictionary:
	return {
		"vs_players": {"kills": 0, "deaths": 0, "assists": 0},
		"vs_bots": {"kills": 0, "deaths": 0, "assists": 0},
		"suicides": 0, "wins": 0, "matches": 0, "matches_incomplete": 0, "shots": 0, "hits": 0,
		"headshot_kills": 0, "damage_dealt": 0, "best_streak": 0, "seconds_played": 0, "weapon_kills": {},
	}


# --- Serialization ---

## JSON with a checksum over the payload.
func to_text() -> String:
	var payload := JSON.stringify(data, "", true)
	return JSON.stringify({"checksum": payload.sha256_text(), "payload": payload})


## Parses saved text: {} for corrupt text, otherwise {profile: ProfileData,
## newer: bool} (`newer`: written by a newer build, kept read-only).
static func from_text(text: String) -> Dictionary:
	var outer: Variant = _parse(text)
	if not outer is Dictionary or not outer.has("payload") or not outer.has("checksum"):
		return {}
	var payload: String = str(outer.payload)
	if payload.sha256_text() != str(outer.checksum):
		return {}
	var inner: Variant = _parse(payload)
	if not inner is Dictionary or not inner.has("version"):
		return {}
	var version := int(inner.version)
	if version > SCHEMA_VERSION:
		var p := ProfileData.new()
		p.data = inner
		return {"profile": p, "newer": true}
	var migrated := migrate(inner)
	if migrated.is_empty():
		return {}
	var out := ProfileData.new()
	out.data = migrated
	out._normalize()
	return {"profile": out, "newer": false}


## Parses JSON without logging errors (corrupt saves are expected input).
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


## Runs migrations from the saved version up to SCHEMA_VERSION.
static func migrate(d: Dictionary) -> Dictionary:
	var version := int(d.version)
	while version < SCHEMA_VERSION:
		if not MIGRATIONS.has(version):
			return {}
		d = MIGRATIONS[version].call(d)
		version += 1
		d.version = version
	return d


## JSON turns ints into floats and may lack newer keys: restore the shape.
func _normalize() -> void:
	var fresh_stats := _empty_stats()
	var stats: Dictionary = data.get("stats", {})
	for k in fresh_stats:
		if not stats.has(k):
			stats[k] = fresh_stats[k]
	for side in ["vs_players", "vs_bots"]:
		for k in fresh_stats[side]:
			stats[side][k] = int(stats[side].get(k, 0))
	for k in stats:
		if typeof(stats[k]) == TYPE_FLOAT:
			stats[k] = int(stats[k])
	var wk: Dictionary = stats.weapon_kills
	for w in wk:
		wk[w] = int(wk[w])
	data.stats = stats
	data.xp = int(data.get("xp", 0))
	data.unconfirmed_results = int(data.get("unconfirmed_results", 0))
	data.applied_results = Array(data.get("applied_results", []))


# --- Progress ---

func xp() -> int:
	return data.xp


func stats() -> Dictionary:
	return data.stats


## Level from XP: level n → n+1 costs 400 + 100·n XP.
static func level_for(total_xp: int) -> Dictionary:
	var level := 1
	var remaining := total_xp
	while remaining >= 400 + 100 * level:
		remaining -= 400 + 100 * level
		level += 1
	return {"level": level, "into": remaining, "needed": 400 + 100 * level}


## XP for one results row (PLAN §3.13 / §2.7).
@warning_ignore("integer_division")
static func xp_for(row: Dictionary, won: bool, completed: bool, humans: int) -> int:
	var kills_players: int = row.kills - row.kills_vs_bots
	var assists_players: int = row.assists - row.assists_vs_bots
	var xp: int = kills_players * XP_KILL + row.kills_vs_bots * XP_KILL / 2 \
			+ assists_players * XP_ASSIST + row.assists_vs_bots * XP_ASSIST / 2 \
			+ (row.ticks_played / TICK_RATE / 10) * XP_PER_10_SECONDS
	if completed:
		var bonus := XP_COMPLETE + (XP_WIN if won else 0)
		xp += bonus if humans >= 2 else bonus / 2
	return xp


## Applies one match's results for `player_id`. Returns the XP gained, or -1
## if this result id was already applied (idempotent).
@warning_ignore("integer_division")
func apply_results(results: Dictionary, player_id: int, completed: bool = true, confirmed: bool = true) -> int:
	if data.applied_results.has(results.result_id):
		return -1
	var row: Dictionary = {}
	for p in results.players:
		if p.id == player_id:
			row = p
	if row.is_empty():
		return -1
	var won: bool = completed and (results.winner == player_id
			or (results.get("winner_team", GameMode.NO_TEAM) != GameMode.NO_TEAM and row.get("team", -1) == results.winner_team))
	var gained := xp_for(row, won, completed, results.humans)
	var s: Dictionary = data.stats
	s.vs_players.kills += row.kills - row.kills_vs_bots
	s.vs_bots.kills += row.kills_vs_bots
	s.vs_players.deaths += row.deaths - row.deaths_vs_bots - row.suicides
	s.vs_bots.deaths += row.deaths_vs_bots
	s.vs_players.assists += row.assists - row.assists_vs_bots
	s.vs_bots.assists += row.assists_vs_bots
	s.suicides += row.suicides
	s.shots += row.shots
	s.hits += row.hits
	s.headshot_kills += row.headshot_kills
	s.damage_dealt += row.damage_dealt
	s.best_streak = maxi(s.best_streak, row.best_streak)
	s.seconds_played += row.ticks_played / TICK_RATE
	if completed:
		s.matches += 1
		s.wins += 1 if won else 0
	else:
		s.matches_incomplete += 1
	for w in row.weapon_kills:
		s.weapon_kills[String(w)] = s.weapon_kills.get(String(w), 0) + row.weapon_kills[w]
	data.xp += gained
	if not confirmed:
		data.unconfirmed_results += 1
	data.applied_results.append(results.result_id)
	while data.applied_results.size() > MAX_APPLIED_IDS:
		data.applied_results.pop_front()
	return gained
