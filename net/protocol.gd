class_name Protocol
extends RefCounted
## Message formats (PLAN §3.3). Every message starts with a u8 type. Clients
## may only send HELLO (during auth), CMD, PING, PONG and LOADED; the server
## rejects anything else (PLAN §3.7 whitelist).

const VERSION := 11
const MAGIC := 0x464E4F49  ## "IONF"
## HELLO flags.
const HELLO_SPECTATE := 1
const DEFAULT_PORT := 47710
## Browser clients (WebSocket, TCP) when a native host also serves them (§3.20).
const DEFAULT_WEB_PORT := 47711
const MAX_PEERS := 16

enum Msg { CMD = 10, PING = 11, PONG = 12, SNAPSHOT = 13, WELCOME = 20, PHASE = 21, ROSTER = 22, EVENT = 23, LOADED = 24, NOTICE = 25, RESULTS = 26, LOADOUT = 27, LOBBY = 28, START = 29, TEAM_PICK = 30 }
## NOTICE codes: host lifecycle hints (PLAN §3.5.1, best effort).
enum Notice { HOST_PAUSED = 1, HOST_RESUMED = 2, RETURN_TO_LOBBY = 3, SERVER_SHUTDOWN = 4, KICKED = 5 }
const CLIENT_MESSAGES := [Msg.CMD, Msg.PING, Msg.PONG, Msg.LOADED, Msg.LOADOUT]

## Logical channels (PLAN §3.3.3).
const CH_GAME := 0  ## unreliable: commands, snapshots, pings
const CH_CONTROL := 1  ## reliable ordered: welcome, phases, roster, critical events
const CH_CHAT := 2  ## reliable ordered: chat (later)

const MAX_CLIENT_PACKET := 256
const CMD_REDUNDANCY := 4
const MAX_NAME_BYTES := 48
## Rows in a results message: everyone who played part of the match, so
## bots that gave way to joining players count too (more than MAX_PEERS).
const MAX_RESULT_ROWS := 32


enum Event { FIRE = 1, EXPLOSION = 2, HIT = 3, DEATH = 4, SPAWN = 5, PICKUP = 6, FLAG = 7, WAVE = 8 }


## Weapon wire index (Weapons.ALL order).
static func weapon_index(id: StringName) -> int:
	return maxi(Weapons.index_of(id), 0)


static func weapon_id(index: int) -> StringName:
	return Weapons.ALL[clampi(index, 0, Weapons.ALL.size() - 1)].id


# --- Handshake (SceneMultiplayer auth payloads) ---

## `token`: the reconnect token from an earlier WELCOME, or 0 for a new join.
## `character`, `color`: the player's cosmetic picks (CharacterRig.SELECTABLE,
## PlayerVisual.PALETTE indices).
## `spectate`: watch the match without playing (no player, no commands).
static func encode_hello(compat: String, build: String, uuid: String, player_name: String, token: int = 0,
		character: int = 0, color: int = 0, primary: int = 0, spectate: bool = false) -> PackedByteArray:
	return Wire.Writer.new().u32(MAGIC).u16(VERSION).str8(compat).str8(build).str8(uuid) \
			.str8(player_name.left(MAX_NAME_BYTES)).u32(token >> 32).u32(token & 0xFFFFFFFF).u8(character & 0xFF) \
			.u8(color & 0xFF).u8(primary & 0xFF).u8(HELLO_SPECTATE if spectate else 0).data()


## Returns {} if malformed.
static func decode_hello(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	var out := {"magic": r.u32(), "version": r.u16()}
	if not r.ok or out.version != VERSION:
		return out if r.ok else {}  # other versions: only magic and version are comparable
	out.merge({"compat": r.str8(64), "build": r.str8(96), "uuid": r.str8(64), "name": r.str8(MAX_NAME_BYTES)})
	out["token"] = (r.u32() << 32) | r.u32()
	out["character"] = r.u8()
	out["color"] = r.u8()
	out["primary"] = r.u8()
	out["spectate"] = (r.u8() & HELLO_SPECTATE) != 0
	return out if r.ok and r.remaining() == 0 else {}


static func encode_hello_reply(accepted: bool, reason: String) -> PackedByteArray:
	return Wire.Writer.new().u32(MAGIC).u8(1 if accepted else 0).str8(reason).data()


static func decode_hello_reply(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	var out := {"magic": r.u32(), "accepted": r.u8() == 1, "reason": r.str8()}
	return out if r.ok and out.magic == MAGIC else {}


# --- Commands (client -> server, unreliable, last 4 commands per packet) ---

static func encode_commands(match_id: int, ack_snapshot: int, interp_ticks: int, cmds: Array[PlayerCommand]) -> PackedByteArray:
	var w := Wire.Writer.new().u8(Msg.CMD).u32(match_id).u32(ack_snapshot).u8(interp_ticks) \
			.u8(cmds.size()).u32(cmds[0].tick if not cmds.is_empty() else 0)
	for c in cmds:
		w.i8(c.move_x).i8(c.move_y).u16(c.view_yaw).i16(c.view_pitch).u8(c.held)
		w.bytes(c.presses).i8(c.weapon_slot).f32(c.view_tick)
	return w.data()


## Consecutive commands, oldest first. Returns {} if malformed or out of range.
static func decode_commands(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	if r.u8() != Msg.CMD:
		return {}
	var out := {"match_id": r.u32(), "ack": r.u32(), "interp": r.u8(), "cmds": []}
	var count := r.u8()
	var base := r.u32()
	if not r.ok or count < 1 or count > 8 or out.interp > 30:
		return {}
	for i in count:
		var c := PlayerCommand.new()
		c.tick = base + i
		c.move_x = r.i8()
		c.move_y = r.i8()
		c.view_yaw = r.u16()
		c.view_pitch = r.i16()
		c.held = r.u8()
		for a in PlayerCommand.ACTION_COUNT:
			c.presses[a] = r.u8()
		c.weapon_slot = r.i8()
		c.view_tick = r.f32()
		c.interp_ticks = out.interp
		if c.move_x < -127 or c.move_y < -127 or c.held > 31 or c.weapon_slot < -1 or c.weapon_slot > 7 \
				or c.view_tick < 0.0 or absi(c.view_pitch) > 32767:
			return {}
		out.cmds.append(c)
	return out if r.ok and r.remaining() == 0 else {}


# --- Clock sync ---

static func encode_ping(time_ms: int) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.PING).u32(time_ms).data()


static func encode_pong(echo_ms: int, server_tick: int, fraction: float) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.PONG).u32(echo_ms).u32(server_tick).f32(fraction).data()


static func decode_ping(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	var out := {"type": r.u8(), "time": r.u32()}
	return out if r.ok and r.remaining() == 0 and out.type == Msg.PING else {}


static func decode_pong(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	var out := {"type": r.u8(), "echo": r.u32(), "tick": r.u32(), "fraction": r.f32()}
	return out if r.ok and r.remaining() == 0 and out.type == Msg.PONG and out.fraction >= 0.0 and out.fraction <= 1.0 else {}


# --- Control messages (server -> client, reliable) ---

## `team_names`, `team_colors`: the host's names ("" = the default) and
## colours (GameMode.TEAM_PALETTE indices) for the two teams.
static func encode_welcome(your_id: int, match_id: int, phase: int, phase_seq: int, tick: int, seed_value: int, map_id: String, token: int,
		team_names := PackedStringArray(["", ""]), team_colors := GameMode.DEFAULT_TEAM_COLORS) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.WELCOME).u16(your_id).u32(match_id).u8(phase).u8(phase_seq) \
			.u32(tick).u32(seed_value).str8(map_id).u32(token >> 32).u32(token & 0xFFFFFFFF) \
			.str8(team_names[0]).str8(team_names[1]).u8(team_colors[0]).u8(team_colors[1]).data()


static func decode_welcome(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	r.u8()
	var out := {"id": r.u16(), "match_id": r.u32(), "phase": r.u8(), "phase_seq": r.u8(),
			"tick": r.u32(), "seed": r.u32(), "map": r.str8()}
	out["token"] = (r.u32() << 32) | r.u32()
	out["team_names"] = PackedStringArray([GameMode.clean_team_name(r.str8(64)), GameMode.clean_team_name(r.str8(64))])
	out["team_colors"] = GameMode.clean_team_colors(PackedInt32Array([r.u8(), r.u8()]))
	return out if r.ok else {}


## `seed`: the match's spread seed (SimWorld.match_seed), new each rematch.
static func encode_phase(match_id: int, phase_seq: int, phase: int, tick: int, ends_tick: int, seed: int) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.PHASE).u32(match_id).u8(phase_seq).u8(phase).u32(tick).u32(ends_tick).u32(seed).data()


static func decode_phase(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	r.u8()
	var out := {"match_id": r.u32(), "phase_seq": r.u8(), "phase": r.u8(), "tick": r.u32(), "ends": r.u32(), "seed": r.u32()}
	return out if r.ok else {}


## roster: Array of {id, name, bot, character, color, score, team, kills,
## deaths, assists}; `mode` GameMode; `team_scores` [cyan, orange] (TDM).
static func encode_roster(match_id: int, roster: Array, mode: int = GameMode.FFA,
		team_scores := PackedInt32Array([0, 0])) -> PackedByteArray:
	var w := Wire.Writer.new().u8(Msg.ROSTER).u32(match_id).u8(mode).i16(team_scores[0]).i16(team_scores[1]) \
			.u8(roster.size())
	for p in roster:
		w.u16(p.id).u8(1 if p.bot else 0).u8(p.get("character", 0) & 0xFF).u8(p.get("color", 0) & 0xFF) \
				.i16(p.score).u8(p.get("team", GameMode.NO_TEAM)).u16(p.get("kills", 0)).u16(p.get("deaths", 0)) \
				.u16(p.get("assists", 0)).str8(p.name)
	return w.data()


static func decode_roster(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	r.u8()
	var out := {"match_id": r.u32(), "mode": r.u8(), "team_scores": PackedInt32Array([r.i16(), r.i16()]), "players": []}
	var n := r.u8()
	for i in n:
		out.players.append({"id": r.u16(), "bot": r.u8() == 1, "character": r.u8(), "color": r.u8(), "score": r.i16(),
				"team": r.u8(), "kills": r.u16(), "deaths": r.u16(), "assists": r.u16(), "name": r.str8()})
	return out if r.ok and out.mode < GameMode.IDS.size() else {}


## End-of-match results (PLAN §2.6, §3.13). `result_id` makes applying them
## to a profile idempotent. `winner` 0 = draw. `players`: Array of Dictionary
## from MatchStats lines plus "score".
## TDM: `winner_team` (GameMode.NO_TEAM = none) and `team_scores`; rows
## carry "team".
static func encode_results(match_id: int, result_id: String, winner: int, duration_ticks: int, humans: int,
		players: Array, mode: int = GameMode.FFA, winner_team: int = GameMode.NO_TEAM,
		team_scores := PackedInt32Array([0, 0])) -> PackedByteArray:
	var w := Wire.Writer.new().u8(Msg.RESULTS).u32(match_id).str8(result_id).u16(winner).u32(duration_ticks) \
			.u8(humans).u8(mode).u8(winner_team).i16(team_scores[0]).i16(team_scores[1]).u8(players.size())
	for p in players:
		w.u16(p.id).u8(1 if p.bot else 0).str8(p.name).i16(p.score).u8(p.get("team", GameMode.NO_TEAM)).u32(p.ticks_played)
		for k in RESULT_COUNTERS:
			w.u16(clampi(p[k], 0, 65535))
		var wk: Dictionary = p.weapon_kills
		w.u8(mini(wk.size(), Weapons.ALL.size()))
		for weapon in wk.keys().slice(0, Weapons.ALL.size()):
			w.u8(weapon_index(weapon)).u16(clampi(wk[weapon], 0, 65535))
	return w.data()


const RESULT_COUNTERS := ["kills", "kills_vs_bots", "deaths", "deaths_vs_bots", "assists", "assists_vs_bots",
		"suicides", "headshot_kills", "shots", "hits", "damage_dealt", "damage_taken", "best_streak"]


static func decode_results(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	r.u8()
	var out := {"match_id": r.u32(), "result_id": r.str8(64), "winner": r.u16(), "duration_ticks": r.u32(),
			"humans": r.u8(), "mode": r.u8(), "winner_team": r.u8(), "team_scores": PackedInt32Array([r.i16(), r.i16()]),
			"players": []}
	var n := r.u8()
	if n > MAX_RESULT_ROWS:
		return {}
	for i in n:
		var p := {"id": r.u16(), "bot": r.u8() == 1, "name": r.str8(MAX_NAME_BYTES), "score": r.i16(), "team": r.u8(),
				"ticks_played": r.u32()}
		for k in RESULT_COUNTERS:
			p[k] = r.u16()
		var wk := {}
		var nw := r.u8()
		if nw > Weapons.ALL.size():
			return {}
		for j in nw:
			var idx := r.u8()
			wk[weapon_id(idx)] = r.u16()
		p["weapon_kills"] = wk
		out.players.append(p)
	return out if r.ok and r.remaining() == 0 else {}


static func encode_notice(code: int) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.NOTICE).u8(code).data()


static func decode_notice(data: PackedByteArray) -> int:
	var r := Wire.Reader.new(data)
	r.u8()
	var code := r.u8()
	return code if r.ok else 0


## Client -> server: the primary for the next spawn (Loadouts.PRIMARIES).
static func encode_loadout(primary: int) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.LOADOUT).u8(primary & 0xFF).data()


static func decode_loadout(data: PackedByteArray) -> int:
	var r := Wire.Reader.new(data)
	var type := r.u8()
	var primary := r.u8()
	return primary if r.ok and r.remaining() == 0 and type == Msg.LOADOUT and primary < Loadouts.PRIMARIES.size() else -1


static func encode_loaded(match_id: int) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.LOADED).u32(match_id).data()


static func decode_loaded(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	var out := {"type": r.u8(), "match_id": r.u32()}
	return out if r.ok and r.remaining() == 0 and out.type == Msg.LOADED else {}


static func encode_event_message(match_id: int, event: Dictionary) -> PackedByteArray:
	var w := Wire.Writer.new().u8(Msg.EVENT).u32(match_id)
	write_event(w, event)
	return w.data()


static func decode_event_message(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	r.u8()
	var match_id := r.u32()
	var e := read_event(r)
	if not r.ok or e.is_empty():
		return {}
	e["match_id"] = match_id
	return e


# --- Events: sim event dictionaries <-> wire ---

## CTF flag events (SimWorld._step_flags) and their event id prefixes.
const FLAG_ACTIONS := ["take", "drop", "return", "capture"]
const FLAG_ID_PREFIXES := ["ft", "fd", "fr", "fc"]

## Writes a SimWorld event. Returns false for event types that aren't sent.
static func write_event(w: Wire.Writer, e: Dictionary) -> bool:
	match e.type:
		"fire":
			var parts: PackedStringArray = e.id.split(":")
			var flags := (1 if e.has("end") else 0) | (2 if e.get("hit_world", false) else 0) | (4 if e.get("hit_player", false) else 0)
			w.u8(Event.FIRE).u16(e.shooter).u8(int(parts[1])).u32(int(parts[2])).u8(weapon_index(e.weapon)).u8(flags)
			w.pos(e.origin)
			if e.has("end"):
				w.pos(e.end)
			else:
				var d: Vector3 = e.direction
				w.i16(roundi(d.x * 32767)).i16(roundi(d.y * 32767)).i16(roundi(d.z * 32767))
		"explosion":
			var parts: PackedStringArray = e.id.substr(2).split(":")
			w.u8(Event.EXPLOSION).u16(int(parts[0])).u8(int(parts[1])).u32(int(parts[2])).pos(e.position)
		"hit":
			var parts: PackedStringArray = e.id.substr(2).split(":")
			var flags := (1 if e.headshot else 0) | (2 if e.killed else 0) | (4 if e.shield_broken else 0)
			w.u8(Event.HIT).u16(e.attacker).u32(int(parts[1])).u16(e.target).u32(e.tick).u8(clampi(roundi(e.amount), 0, 255)).u8(flags)
		"death":
			var flags := (1 if e.suicide else 0) | (2 if e.get("headshot", false) else 0) | (4 if e.get("environment", false) else 0)
			var assists: Array = e.get("assists", [])
			w.u8(Event.DEATH).u16(e.victim).u8(int(e.id.split(":")[2])).u16(e.killer).u8(flags) \
					.u8(weapon_index(e.weapon) if e.weapon != &"" else 255).pos(e.position).u8(mini(assists.size(), 3))
			for i in mini(assists.size(), 3):
				w.u16(assists[i])
		"pickup":
			var parts: PackedStringArray = e.id.substr(2).split(":")
			w.u8(Event.PICKUP).u16(e.player).u16(int(parts[0])).u32(int(parts[1])) \
					.u8(255 if e.weapon == &"grenade" else weapon_index(e.weapon)).pos(e.position)
		"spawn":
			w.u8(Event.SPAWN).u16(e.player).u8(int(e.id.split(":")[2])).pos(e.position).u16(PlayerCommand.quantize_yaw(e.yaw))
		"flag":
			w.u8(Event.FLAG).u8(FLAG_ACTIONS.find(e.action)).u8(e.team).u16(e.player).u32(e.tick).pos(e.position)
		"wave":
			w.u8(Event.WAVE).u8(0 if e.action == "start" else 1).u8(mini(e.wave, 255)).u32(e.tick) \
					.u8(mini(e.get("enemies", 0), 255))
		_:
			return false
	return true


## Reads one event back into the same dictionary shape SimWorld emits,
## including the same `id`, so presentation de-duplication works across
## predicted (local) and server (remote) copies.
static func read_event(r: Wire.Reader) -> Dictionary:
	var type := r.u8()
	match type:
		Event.FIRE:
			var shooter := r.u16()
			var gen := r.u8()
			var action := r.u32()
			var weapon: StringName = weapon_id(r.u8())
			var flags := r.u8()
			var e := {"type": "fire", "id": "%d:%d:%d" % [shooter, gen, action], "shooter": shooter,
					"weapon": weapon, "origin": r.pos()}
			if flags & 1:
				e["end"] = r.pos()
				e["hit_world"] = (flags & 2) != 0
				e["hit_player"] = (flags & 4) != 0
			else:
				e["direction"] = Vector3(r.i16(), r.i16(), r.i16()) / 32767.0
			return e
		Event.EXPLOSION:
			var owner := r.u16()
			var gen := r.u8()
			var action := r.u32()
			return {"type": "explosion", "id": "x:%d:%d:%d" % [owner, gen, action], "owner": owner, "position": r.pos()}
		Event.HIT:
			var attacker := r.u16()
			var action := r.u32()
			var target := r.u16()
			var tick := r.u32()
			var amount := r.u8()
			var flags := r.u8()
			return {"type": "hit", "id": "h:%d:%d:%d:%d" % [attacker, action, target, tick], "attacker": attacker,
					"target": target, "amount": float(amount), "headshot": (flags & 1) != 0,
					"killed": (flags & 2) != 0, "shield_broken": (flags & 4) != 0}
		Event.DEATH:
			var victim := r.u16()
			var life := r.u8()
			var killer := r.u16()
			var flags := r.u8()
			var wi := r.u8()
			var weapon: StringName = &"" if wi == 255 else weapon_id(wi)
			var position := r.pos()
			var n := r.u8()
			if n > 3:
				r.ok = false
				return {}
			var assists: Array[int] = []
			for i in n:
				assists.append(r.u16())
			return {"type": "death", "id": "d:%d:%d" % [victim, life], "victim": victim, "killer": killer,
					"suicide": (flags & 1) != 0, "headshot": (flags & 2) != 0, "environment": (flags & 4) != 0,
					"weapon": weapon, "position": position, "assists": assists}
		Event.PICKUP:
			var player := r.u16()
			var item := r.u16()
			var tick := r.u32()
			var wi := r.u8()
			return {"type": "pickup", "id": "p:%d:%d" % [item, tick], "player": player,
					"weapon": &"grenade" if wi == 255 else weapon_id(wi), "position": r.pos()}
		Event.SPAWN:
			var player := r.u16()
			var life := r.u8()
			return {"type": "spawn", "id": "s:%d:%d" % [player, life], "player": player, "position": r.pos(),
					"yaw": r.u16() * TAU / 65536.0}
		Event.FLAG:
			var action := r.u8()
			var team := r.u8()
			var player := r.u16()
			var tick := r.u32()
			if action >= FLAG_ACTIONS.size() or team > 1:
				r.ok = false
				return {}
			return {"type": "flag", "id": "%s:%d:%d" % [FLAG_ID_PREFIXES[action], team, tick], "action": FLAG_ACTIONS[action],
					"team": team, "player": player, "tick": tick, "position": r.pos()}
		Event.WAVE:
			var cleared := r.u8() == 1
			var wave := r.u8()
			var tick := r.u32()
			return {"type": "wave", "id": "w:%d:%d" % [wave, tick], "action": "cleared" if cleared else "start",
					"wave": wave, "tick": tick, "enemies": r.u8()}
	r.ok = false
	return {}


# --- Pre-match lobby (LobbySession; server -> client, reliable) ---

## The host's settings and who is in the lobby. `members`: Array of
## {id, name, host, team, ping} in join order (`id` the member's transport
## peer id; `team` 0 or 1, used in the team modes; `ping` the member's round
## trip to the host in ms, 0 for the host). `team_names`, `team_colors`: the
## host's names ("" = the default) and colours (GameMode.TEAM_PALETTE) for
## the teams.
## `bots`, `bot_difficulty`, `friendly_fire`: the host's bot settings, shown
## read-only to members.
static func encode_lobby(map_id: String, mode: int, minutes: int, max_players: int, members: Array,
		bots: int = 0, bot_difficulty: int = 1, friendly_fire: bool = false,
		team_names := PackedStringArray(["", ""]), team_colors := GameMode.DEFAULT_TEAM_COLORS) -> PackedByteArray:
	var w := Wire.Writer.new().u8(Msg.LOBBY).str8(map_id).u8(mode).u8(minutes).u8(max_players) \
			.u8(bots).u8(bot_difficulty).u8(1 if friendly_fire else 0).str8(team_names[0]).str8(team_names[1]) \
			.u8(team_colors[0]).u8(team_colors[1]).u8(members.size())
	for m in members:
		w.u32(m.id).u8(1 if m.host else 0).u8(m.team).u16(mini(m.get("ping", 0), 65535)).str8(m.name)
	return w.data()


static func decode_lobby(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	r.u8()
	var out := {"map": r.str8(32), "mode": r.u8(), "minutes": r.u8(), "max": r.u8(), "bots": r.u8(),
			"bot_difficulty": r.u8(), "friendly_fire": r.u8() == 1, "members": []}
	out["team_names"] = PackedStringArray([GameMode.clean_team_name(r.str8(64)), GameMode.clean_team_name(r.str8(64))])
	out["team_colors"] = GameMode.clean_team_colors(PackedInt32Array([r.u8(), r.u8()]))
	var n := r.u8()
	if n > MAX_PEERS or out.bots >= MAX_PEERS or out.bot_difficulty > 3:
		return {}
	for i in n:
		var m := {"id": r.u32(), "host": r.u8() == 1, "team": r.u8(), "ping": r.u16(), "name": r.str8(MAX_NAME_BYTES)}
		if m.team > 1:
			return {}
		out.members.append(m)
	return out if r.ok and r.remaining() == 0 and out.mode < GameMode.IDS.size() else {}


## The host started the match: everyone loads `map_id` and joins it.
static func encode_start(map_id: String, mode: int, minutes: int) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.START).str8(map_id).u8(mode).u8(minutes).data()


static func decode_start(data: PackedByteArray) -> Dictionary:
	var r := Wire.Reader.new(data)
	r.u8()
	var out := {"map": r.str8(32), "mode": r.u8(), "minutes": r.u8()}
	return out if r.ok and r.remaining() == 0 and out.mode < GameMode.IDS.size() else {}


## Lobby, client -> host: put me on `team` (0 or 1) in the team modes.
static func encode_team_pick(team: int) -> PackedByteArray:
	return Wire.Writer.new().u8(Msg.TEAM_PICK).u8(team).data()


## The team, or -1 if malformed.
static func decode_team_pick(data: PackedByteArray) -> int:
	var r := Wire.Reader.new(data)
	r.u8()
	var team := r.u8()
	return team if r.ok and r.remaining() == 0 and team <= 1 else -1


static func message_type(data: PackedByteArray) -> int:
	return data.decode_u8(0) if data.size() > 0 else -1
