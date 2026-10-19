class_name MatchStats
extends RefCounted
## Per-match player statistics, built on the server from simulation events
## (PLAN §2.6, §3.13). Every kill, death and assist is classified per event
## as "vs players" or "vs bots" (PLAN §2.7). Sent to clients in RESULTS at the
## end of a match and used for the live scoreboard.

class Line:
	var id: int = 0
	var name: String = ""
	var bot: bool = false
	var joined_tick: int = 0
	var left_tick: int = -1
	var kills: int = 0
	var kills_vs_bots: int = 0
	var deaths: int = 0
	var deaths_vs_bots: int = 0
	var assists: int = 0
	var assists_vs_bots: int = 0
	var suicides: int = 0
	var headshot_kills: int = 0
	var shots: int = 0
	var hits: int = 0
	var damage_dealt: int = 0
	var damage_taken: int = 0
	var streak: int = 0
	var best_streak: int = 0
	var weapon_kills: Dictionary = {}  ## weapon id -> kills
	var _hit_actions: Dictionary = {}  ## action seq -> true (accuracy counts each shot once)

	func ticks_played(now: int) -> int:
		return (left_tick if left_tick >= 0 else now) - joined_tick


var lines: Dictionary = {}  ## player id -> Line


func add_player(id: int, player_name: String, bot: bool, tick: int) -> void:
	var l: Line = lines.get(id)
	if l == null:
		l = Line.new()
		l.id = id
		l.joined_tick = tick
		lines[id] = l
	l.name = player_name
	l.bot = bot
	l.left_tick = -1


func remove_player(id: int, tick: int) -> void:
	if lines.has(id):
		lines[id].left_tick = tick


func is_bot(id: int) -> bool:
	return lines.has(id) and lines[id].bot


func on_event(e: Dictionary) -> void:
	match e.type:
		"fire":
			var l: Line = lines.get(e.shooter)
			if l != null:
				l.shots += 1
		"hit":
			if e.attacker == e.target:
				return
			var a: Line = lines.get(e.attacker)
			if a != null:
				a.damage_dealt += roundi(e.amount)
				var action: String = e.id.split(":")[2]
				if not a._hit_actions.has(action):
					a._hit_actions[action] = true
					a.hits += 1
			var t: Line = lines.get(e.target)
			if t != null:
				t.damage_taken += roundi(e.amount)
		"death":
			var v: Line = lines.get(e.victim)
			var victim_bot := is_bot(e.victim)
			if v != null:
				v.deaths += 1
				v.streak = 0
				if e.suicide:
					v.suicides += 1
				elif is_bot(e.killer):
					v.deaths_vs_bots += 1
			if not e.suicide:
				var k: Line = lines.get(e.killer)
				if k != null:
					k.kills += 1
					k.kills_vs_bots += 1 if victim_bot else 0
					k.headshot_kills += 1 if e.get("headshot", false) else 0
					k.streak += 1
					k.best_streak = maxi(k.best_streak, k.streak)
					if e.weapon != &"":
						k.weapon_kills[e.weapon] = k.weapon_kills.get(e.weapon, 0) + 1
				for id in e.get("assists", []):
					var s: Line = lines.get(id)
					if s != null:
						s.assists += 1
						s.assists_vs_bots += 1 if victim_bot else 0


## Starts a new match: everyone still present starts from zero at `tick`.
func reset(tick: int) -> void:
	for id in lines.keys():
		var old: Line = lines[id]
		if old.left_tick >= 0:
			lines.erase(id)
			continue
		var l := Line.new()
		l.id = id
		l.name = old.name
		l.bot = old.bot
		l.joined_tick = tick
		lines[id] = l
