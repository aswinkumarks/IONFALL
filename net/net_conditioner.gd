class_name NetConditioner
extends RefCounted
## Software network simulator for tests and the debug menu (PLAN §5): delays,
## jitters and drops packets in both directions on one endpoint. Conditions are
## given as RTT: each direction gets half. Reliable packets are delayed but
## never dropped or reordered (ENet guarantees those).

var rtt_ms: float = 0.0
var jitter_ms: float = 0.0
var loss: float = 0.0  ## 0..1, unreliable packets only
## Forces the next N unreliable outgoing packets to drop (loss tests).
var drop_next_outgoing: int = 0
## Wi-Fi power-save bursts: every `burst_every_ms`, outgoing packets are held
## for `burst_hold_ms` and then released together.
var burst_every_ms: int = 0
var burst_hold_ms: int = 0

var _rng := RandomNumberGenerator.new()
var _queue: Array = []  ## [release_ms, kind, peer, data, reliable, channel]
var _last_reliable_release: float = 0.0


func _init(seed_value: int = 1) -> void:
	_rng.seed = seed_value


func is_active() -> bool:
	return rtt_ms > 0.0 or jitter_ms > 0.0 or loss > 0.0 or drop_next_outgoing > 0 or burst_every_ms > 0


## Returns false if the packet is dropped; otherwise it's queued for later.
func push(kind: String, peer: int, data: PackedByteArray, reliable: bool, channel: int) -> bool:
	if not reliable:
		if kind == "out" and drop_next_outgoing > 0:
			drop_next_outgoing -= 1
			return false
		if _rng.randf() < loss:
			return false
	var delay := rtt_ms * 0.5 + _rng.randf_range(-jitter_ms, jitter_ms)
	var now := Time.get_ticks_msec()
	var release := now + maxf(delay, 0.0)
	if kind == "out" and burst_every_ms > 0:
		var phase := now % burst_every_ms
		if phase < burst_hold_ms:
			release = maxf(release, now - phase + burst_hold_ms)
	if reliable:
		release = maxf(release, _last_reliable_release)
		_last_reliable_release = release
	_queue.append([release, kind, peer, data, reliable, channel])
	return true


## Packets whose delay has passed, in release order.
func pop_due() -> Array:
	var now := Time.get_ticks_msec()
	var due: Array = []
	var keep: Array = []
	for item in _queue:
		if item[0] <= now:
			due.append(item)
		else:
			keep.append(item)
	_queue = keep
	due.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return due
