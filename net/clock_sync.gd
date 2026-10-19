class_name ClockSync
extends RefCounted
## Client estimate of the server clock (PLAN §3.3.2): ping/pong carrying the
## server tick, median of the last 8 samples. Times are in (fractional) ticks.

const SAMPLES := 8

var rtt_ms: float = 100.0
var _offsets: Array[float] = []
var _rtts: Array[float] = []
var _offset: float = 0.0
var _has_offset: bool = false


static func local_ticks() -> float:
	return Time.get_ticks_usec() / 1000000.0 * Sim.TICK_RATE


func sample_count() -> int:
	return _offsets.size()


func on_pong(echo_ms: int, server_tick: int, fraction: float) -> void:
	var now_ms := Time.get_ticks_msec()
	var rtt := float((now_ms - echo_ms) & 0xFFFFFFFF)
	if rtt < 0.0 or rtt > 5000.0:
		return
	var server_now := server_tick + fraction + rtt * 0.5 / 1000.0 * Sim.TICK_RATE
	_push(_offsets, server_now - local_ticks())
	_push(_rtts, rtt)
	rtt_ms = _median(_rtts)
	var target := _median(_offsets)
	if not _has_offset or absf(target - _offset) > 6.0:
		_offset = target  # first sample or a big jump: snap
		_has_offset = true
	else:
		_offset = lerpf(_offset, target, 0.2)  # small drift: slew


func server_time() -> float:
	return local_ticks() + _offset


func one_way_ticks() -> float:
	return rtt_ms * 0.5 / 1000.0 * Sim.TICK_RATE


func _push(arr: Array[float], v: float) -> void:
	arr.append(v)
	if arr.size() > SAMPLES:
		arr.pop_front()


static func _median(arr: Array[float]) -> float:
	var s := arr.duplicate()
	s.sort()
	return s[s.size() / 2] if not s.is_empty() else 0.0
