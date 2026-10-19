class_name RemoteInterpolator
extends RefCounted
## Snapshot interpolation for remote players (PLAN §3.3.4). Renders at
## `server_time - interp_delay`; extrapolates up to 6 ticks on underrun, then
## holds; never interpolates across a respawn/teleport (discontinuity_gen).
## This is the only smoothing applied to remote players.

const KEEP_TICKS := 90
const MAX_EXTRAPOLATE_TICKS := 6.0

var _frames: Array = []  ## [tick, {id -> NetEntity}], oldest first


func push(tick: int, entities: Dictionary) -> void:
	if not _frames.is_empty() and tick <= _frames[-1][0]:
		return  # stale or duplicate
	_frames.append([tick, entities])
	while _frames.size() > 2 and _frames[0][0] < tick - KEEP_TICKS:
		_frames.pop_front()


func latest_tick() -> int:
	return _frames[-1][0] if not _frames.is_empty() else -1


## Render states for every entity known at `render_tick` (fractional).
func sample(render_tick: float) -> Dictionary:
	var out := {}
	if _frames.is_empty():
		return out
	var i := _frames.size() - 1
	while i > 0 and _frames[i][0] > render_tick:
		i -= 1
	var a: Array = _frames[i]
	var b: Array = _frames[i + 1] if i + 1 < _frames.size() else []
	for id in (b[1] if not b.is_empty() else a[1]):
		var eb: NetEntity = b[1].get(id) if not b.is_empty() else null
		var ea: NetEntity = a[1].get(id)
		if ea == null:
			out[id] = eb.to_render_state()
			continue
		if eb == null:
			# Underrun: extrapolate from the newest frame for a few ticks, then hold.
			var s := ea.to_render_state()
			var ahead := clampf(render_tick - a[0], 0.0, MAX_EXTRAPOLATE_TICKS)
			if s.alive:
				s.position += s.velocity * ahead * Sim.TICK_DT
			out[id] = s
			continue
		if ea.disc != eb.disc or ea.gen != eb.gen:
			out[id] = eb.to_render_state()
			continue
		var t := clampf((render_tick - a[0]) / float(b[0] - a[0]), 0.0, 1.0)
		var sa := ea.to_render_state()
		var sb := eb.to_render_state()
		sb.position = sa.position.lerp(sb.position, t)
		sb.yaw = lerp_angle(sa.yaw, sb.yaw, t)
		sb.pitch = lerpf(sa.pitch, sb.pitch, t)
		if t < 0.5:
			sb.stance = sa.stance
			sb.alive = sa.alive
		out[id] = sb
	return out
