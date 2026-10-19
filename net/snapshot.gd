class_name Snapshot
extends RefCounted
## One server snapshot for one client (PLAN §3.3.3): remote entities (delta
## against the acknowledged baseline), the owner's exact state for
## reconciliation, projectiles and cosmetic events.

const MAX_EVENTS := 8

var id: int = 0  ## = server tick
var match_id: int = 0
var phase_seq: int = 0
var baseline_id: int = 0
var last_cmd_tick: int = 0  ## owner's last processed command
var buffer_delta: int = 0  ## (server command queue length - target), in tenths of a command
var entities: Dictionary = {}  ## id -> NetEntity
var owner_gen: int = -1
var owner_state: PlayerSimState  ## null if the client has no player entity
var projectiles: Array = []  ## of {id, owner, position, velocity}
var events: Array[Dictionary] = []


func encode(baseline: Dictionary, events_bytes: Array[PackedByteArray]) -> PackedByteArray:
	var w := Wire.Writer.new().u8(Protocol.Msg.SNAPSHOT).u32(id).u32(match_id).u8(phase_seq) \
			.u32(baseline_id).u32(last_cmd_tick).i8(buffer_delta).u8(entities.size())
	for e_id in entities:
		(entities[e_id] as NetEntity).write(w, baseline.get(e_id))
	w.u8(1 if owner_state != null else 0)
	if owner_state != null:
		w.u8(owner_gen)
		write_owner(w, owner_state)
	w.u8(projectiles.size())
	for p in projectiles:
		w.u16(p.owner).u8(p.gen).u32(p.action).pos(p.position).vel(p.velocity)
	w.u8(events_bytes.size())
	for b in events_bytes:
		w.bytes(b)
	return w.data()


## `baselines`: snapshot id -> {entity id -> NetEntity} kept by the client.
## Returns null if the packet is malformed or its baseline is unknown.
static func decode(data: PackedByteArray, baselines: Dictionary) -> Snapshot:
	var r := Wire.Reader.new(data)
	if r.u8() != Protocol.Msg.SNAPSHOT:
		return null
	var s := Snapshot.new()
	s.id = r.u32()
	s.match_id = r.u32()
	s.phase_seq = r.u8()
	s.baseline_id = r.u32()
	s.last_cmd_tick = r.u32()
	s.buffer_delta = r.i8()
	var base: Dictionary = {}
	if s.baseline_id != 0:
		if not baselines.has(s.baseline_id):
			return null
		base = baselines[s.baseline_id]
	var n := r.u8()
	for i in n:
		var e := NetEntity.read(r, base)
		if e == null:
			return null
		s.entities[e.id] = e
	if r.u8() == 1:
		s.owner_gen = r.u8()
		s.owner_state = read_owner(r)
	var np := r.u8()
	for i in np:
		var owner := r.u16()
		var gen := r.u8()
		var action := r.u32()
		s.projectiles.append({"id": "%d:%d:%d" % [owner, gen, action], "owner": owner,
				"position": r.pos(), "velocity": r.vel()})
	var ne := r.u8()
	if ne > MAX_EVENTS:
		return null
	for i in ne:
		var e := Protocol.read_event(r)
		if e.is_empty():
			return null
		s.events.append(e)
	return s if r.ok and r.remaining() == 0 else null


## Owner state with exact float precision, so the client can restore it and
## replay its commands bit for bit (PLAN §3.2 reconciliation).
static func write_owner(w: Wire.Writer, s: PlayerSimState) -> void:
	w.vec_f32(s.position).vec_f32(s.velocity).vec_f32(s.floor_normal)
	w.u8(s.move_state).u8(s.stance).u8((1 if s.sprinting else 0) | (2 if s.alive else 0))
	w.u16(mini(s.ticks_since_floor, 65535)).u8(s.jump_buffer_ticks).u8(s.air_jumps_left).u8(s.slide_ticks)
	w.u8(s.mantle_tick)
	if s.move_state == PlayerSimState.Move.MANTLE:
		w.vec_f32(s.mantle_start).vec_f32(s.mantle_target)
	w.u32(s.action_seq).u8(s.weapon_slot).u8(s.switch_ticks).u8(s.mag.size())
	for i in s.mag.size():
		w.u16(s.mag[i]).u16(s.reserve[i]).u8(s.cooldown[i]).u8(s.reload[i]).u8(s.burst_left[i]).u8(s.burst_timer[i])
	w.bytes(s.last_presses).bytes(s.pending_presses)
	w.f32(s.shield).f32(s.health).u8(s.life_gen & 0xFF).u8(s.discontinuity_gen & 0xFF)
	w.u8(mini(s.spawn_protection_ticks, 255)).u32(s.respawn_tick)


static func read_owner(r: Wire.Reader) -> PlayerSimState:
	var s := PlayerSimState.new()
	s.position = r.vec_f32()
	s.velocity = r.vec_f32()
	s.floor_normal = r.vec_f32()
	s.move_state = r.u8()
	s.stance = r.u8()
	var f := r.u8()
	s.sprinting = (f & 1) != 0
	s.alive = (f & 2) != 0
	s.ticks_since_floor = r.u16()
	s.jump_buffer_ticks = r.u8()
	s.air_jumps_left = r.u8()
	s.slide_ticks = r.u8()
	s.mantle_tick = r.u8()
	if s.move_state == PlayerSimState.Move.MANTLE:
		s.mantle_start = r.vec_f32()
		s.mantle_target = r.vec_f32()
	s.action_seq = r.u32()
	s.weapon_slot = r.u8()
	s.switch_ticks = r.u8()
	var n := r.u8()
	if n > 8 or s.move_state > PlayerSimState.Move.DEAD or s.stance > PlayerSimState.Stance.SLIDE:
		r.ok = false
		return s
	# Packed arrays are value types: resize each field directly.
	s.mag.resize(n)
	s.reserve.resize(n)
	s.cooldown.resize(n)
	s.reload.resize(n)
	s.burst_left.resize(n)
	s.burst_timer.resize(n)
	for i in n:
		s.mag[i] = r.u16()
		s.reserve[i] = r.u16()
		s.cooldown[i] = r.u8()
		s.reload[i] = r.u8()
		s.burst_left[i] = r.u8()
		s.burst_timer[i] = r.u8()
	for a in PlayerCommand.ACTION_COUNT:
		s.last_presses[a] = r.u8()
	for a in PlayerCommand.ACTION_COUNT:
		s.pending_presses[a] = r.u8()
	s.shield = r.f32()
	s.health = r.f32()
	s.life_gen = r.u8()
	s.discontinuity_gen = r.u8()
	s.spawn_protection_ticks = r.u8()
	s.respawn_tick = r.u32()
	return s
