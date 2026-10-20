class_name NetEntity
extends RefCounted
## Quantized remote-player state as sent in snapshots (PLAN §3.3.3). Field
## groups are delta-encoded against the client's acknowledged baseline.

enum Group { POS = 1, VEL = 2, LOOK = 4, STATE = 8, VITALS = 16, WEAPON = 32, DISC = 64 }
const FULL := 0x80
const ALL_GROUPS := 0x7F

const FLAG_ALIVE := 1
const FLAG_PROTECTED := 2
const FLAG_SPRINTING := 4

var id: int = 0
var gen: int = 0
var px: int = 0
var py: int = 0
var pz: int = 0
var vx: int = 0
var vy: int = 0
var vz: int = 0
var yaw: int = 0
var pitch: int = 0
var flags: int = 0
var move_stance: int = 0  ## move_state | stance << 4
var shield: int = 0
var health: int = 0
var weapon: int = 0
var disc: int = 0


static func from_player(p: SimPlayer) -> NetEntity:
	var s := p.state
	var e := NetEntity.new()
	e.id = p.net_id
	e.gen = p.entity_gen & 0xFF
	e.px = roundi(s.position.x * Wire.POS_SCALE)
	e.py = roundi(s.position.y * Wire.POS_SCALE)
	e.pz = roundi(s.position.z * Wire.POS_SCALE)
	e.vx = clampi(roundi(s.velocity.x * Wire.VEL_SCALE), -32768, 32767)
	e.vy = clampi(roundi(s.velocity.y * Wire.VEL_SCALE), -32768, 32767)
	e.vz = clampi(roundi(s.velocity.z * Wire.VEL_SCALE), -32768, 32767)
	e.yaw = PlayerCommand.quantize_yaw(s.yaw)
	e.pitch = PlayerCommand.quantize_pitch(s.pitch)
	e.flags = (FLAG_ALIVE if s.alive else 0) | (FLAG_PROTECTED if s.spawn_protection_ticks > 0 else 0) \
			| (FLAG_SPRINTING if s.sprinting else 0)
	e.move_stance = s.move_state | (s.stance << 4)
	e.shield = clampi(ceili(s.shield), 0, 255)
	e.health = clampi(ceili(s.health), 0, 255)
	e.weapon = maxi(s.weapons[s.weapon_slot], 0) if s.weapon_slot < s.weapons.size() else 0
	e.disc = s.discontinuity_gen & 0xFF
	return e


## Bitmask of groups that differ from `base`.
func changed_groups(base: NetEntity) -> int:
	var m := 0
	if px != base.px or py != base.py or pz != base.pz:
		m |= Group.POS
	if vx != base.vx or vy != base.vy or vz != base.vz:
		m |= Group.VEL
	if yaw != base.yaw or pitch != base.pitch:
		m |= Group.LOOK
	if flags != base.flags or move_stance != base.move_stance:
		m |= Group.STATE
	if shield != base.shield or health != base.health:
		m |= Group.VITALS
	if weapon != base.weapon:
		m |= Group.WEAPON
	if disc != base.disc:
		m |= Group.DISC
	return m


## Writes this entity, as a delta against `base` when given.
func write(w: Wire.Writer, base: NetEntity) -> void:
	var mask := FULL | ALL_GROUPS
	if base != null and base.gen == gen:
		mask = changed_groups(base)
	w.u16(id).u8(gen).u8(mask)
	if mask & Group.POS:
		w.i24(px).i24(py).i24(pz)
	if mask & Group.VEL:
		w.i16(vx).i16(vy).i16(vz)
	if mask & Group.LOOK:
		w.u16(yaw).i16(pitch)
	if mask & Group.STATE:
		w.u8(flags).u8(move_stance)
	if mask & Group.VITALS:
		w.u8(shield).u8(health)
	if mask & Group.WEAPON:
		w.u8(weapon)
	if mask & Group.DISC:
		w.u8(disc)


## Reads an entity. Delta entities need their baseline; returns null if it's
## missing (the snapshot can't be decoded).
static func read(r: Wire.Reader, baselines: Dictionary) -> NetEntity:
	var e := NetEntity.new()
	e.id = r.u16()
	e.gen = r.u8()
	var mask := r.u8()
	if not (mask & FULL):
		var base: NetEntity = baselines.get(e.id)
		if base == null or base.gen != e.gen:
			r.ok = false
			return null
		e.copy_from(base)
	if mask & Group.POS:
		e.px = r.i24()
		e.py = r.i24()
		e.pz = r.i24()
	if mask & Group.VEL:
		e.vx = r.i16()
		e.vy = r.i16()
		e.vz = r.i16()
	if mask & Group.LOOK:
		e.yaw = r.u16()
		e.pitch = r.i16()
	if mask & Group.STATE:
		e.flags = r.u8()
		e.move_stance = r.u8()
	if mask & Group.VITALS:
		e.shield = r.u8()
		e.health = r.u8()
	if mask & Group.WEAPON:
		e.weapon = r.u8()
	if mask & Group.DISC:
		e.disc = r.u8()
	return e if r.ok else null


func copy_from(o: NetEntity) -> void:
	for k in ["px", "py", "pz", "vx", "vy", "vz", "yaw", "pitch", "flags", "move_stance", "shield", "health", "weapon", "disc"]:
		set(k, o.get(k))


func position() -> Vector3:
	return Vector3(px, py, pz) / Wire.POS_SCALE


func velocity() -> Vector3:
	return Vector3(vx, vy, vz) / Wire.VEL_SCALE


## A PlayerSimState with the fields presentation needs (for PlayerVisual).
func to_render_state() -> PlayerSimState:
	var s := PlayerSimState.new()
	s.position = position()
	s.velocity = velocity()
	s.yaw = yaw * TAU / 65536.0
	s.pitch = pitch * PlayerCommand.PITCH_LIMIT / 32767.0
	s.alive = (flags & FLAG_ALIVE) != 0
	s.spawn_protection_ticks = 1 if flags & FLAG_PROTECTED else 0
	s.sprinting = (flags & FLAG_SPRINTING) != 0
	s.move_state = move_stance & 0x0F
	s.stance = (move_stance >> 4) & 0x0F
	s.shield = shield
	s.health = health
	s.discontinuity_gen = disc
	s.weapons = PackedInt32Array([weapon])  # the held weapon (Weapons.ALL index)
	s.weapon_slot = 0
	return s
