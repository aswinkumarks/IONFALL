class_name WaveDirector
extends RefCounted
## Co-op waves (PLAN §2.4): the humans (team 0) hold out against waves of
## bots (team 1). A wave's bots don't respawn: they leave shortly after
## dying. Fallen humans wait for the end of the wave and come back when it
## is cleared. Clearing Balance.MODES.wave_count waves wins; everyone down at
## once loses. Server only; clients see `wave`, `enemies_left()` and
## `ticks_to_next()` in snapshots.

const CLEANUP_TICKS := 120  ## a dead wave bot leaves after 2 s
const NEVER := 0x7FFFFFFF  ## a fallen human's respawn tick while the wave lasts

var wave: int = 0  ## the current (or last) wave, 0 before the first
var fighting: bool = false
var next_wave_tick: int = 0
var _session: ServerSession
var _dead_since: Dictionary = {}  ## wave bot id -> tick it died


func _init(session: ServerSession) -> void:
	_session = session


## A new match: the first wave comes after the intermission.
func reset(tick: int) -> void:
	wave = 0
	fighting = false
	next_wave_tick = tick + Balance.MODES.wave_intermission_ticks
	_dead_since.clear()


func enemies_left() -> int:
	var n := 0
	for id in _session.bots:
		if _session.world.players[id].state.alive:
			n += 1
	return n


func ticks_to_next() -> int:
	return 0 if fighting else maxi(next_wave_tick - _session.world.tick, 0)


## Bots in wave `n` (capped by the match's combatant limit).
func wave_size(n: int, humans: int) -> int:
	var m := Balance.MODES
	var bots := m.first_wave_bots + (n - 1) * m.extra_bots_per_wave + maxi(humans - 1, 0) * m.extra_bots_per_human
	return clampi(bots, 1, maxi(_session.max_combatants - humans, 1))


## Wave `n`'s difficulty: the chosen one, one step harder every
## Balance.MODES.waves_per_difficulty_step waves.
@warning_ignore("integer_division")
func wave_difficulty(n: int) -> int:
	return mini(_session.bot_difficulty + (n - 1) / maxi(Balance.MODES.waves_per_difficulty_step, 1), BotBrain.Difficulty.INSANE)


## One tick during PLAYING. Returns the winning team + 1 when the match is
## decided (GameMode.HUMANS + 1 or GameMode.WAVE_TEAM + 1), else 0.
func step() -> int:
	var world := _session.world
	var tick := world.tick
	# Wave bots leave a moment after dying.
	for id: int in _session.bots.keys():
		var bot: SimPlayer = world.players[id]
		if bot.state.alive:
			bot.state.respawn_tick = NEVER
			continue
		if not _dead_since.has(id):
			_dead_since[id] = tick
			bot.state.respawn_tick = NEVER
		elif tick - int(_dead_since[id]) >= CLEANUP_TICKS:
			_dead_since.erase(id)
			_session.remove_bot(id)
	var humans := 0
	var standing := 0
	for p: SimPlayer in world.players.values():
		if p.is_bot:
			continue
		humans += 1
		if p.state.alive:
			standing += 1
		elif fighting:
			p.state.respawn_tick = NEVER  # back when the wave is cleared
	if humans == 0:
		return 0
	if fighting:
		if standing == 0:
			return GameMode.WAVE_TEAM + 1
		if _session.bots.is_empty():
			fighting = false
			world.team_scores[GameMode.HUMANS] = wave
			world._emit("w:%d:%d" % [wave, tick], "wave", {"action": "cleared", "wave": wave})
			for p: SimPlayer in world.players.values():
				if not p.is_bot and not p.state.alive:
					p.state.respawn_tick = tick
			if wave >= Balance.MODES.wave_count:
				return GameMode.HUMANS + 1
			next_wave_tick = tick + Balance.MODES.wave_intermission_ticks
	elif tick >= next_wave_tick:
		_start_wave(wave + 1, humans)
	return 0


func _start_wave(n: int, humans: int) -> void:
	wave = n
	fighting = true
	var difficulty := wave_difficulty(n)
	for i in wave_size(n, humans):
		_session.add_wave_bot(difficulty)
	_session.world._emit("w:%d:%d" % [n, _session.world.tick], "wave", {"action": "start", "wave": n,
			"enemies": _session.bots.size()})
