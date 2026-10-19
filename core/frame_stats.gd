class_name FrameStats
extends RefCounted
## Rolling frame-time statistics (PLAN §3.10, §3.15).
##
## Performance targets are frame-time percentiles, e.g. "p95 <= 16.7 ms",
## meaning 95% of frames finish within that time.

var _samples: PackedFloat32Array
var _capacity: int
var _next: int = 0
var _count: int = 0


func _init(capacity: int = 600) -> void:
	_capacity = maxi(capacity, 1)
	_samples.resize(_capacity)


func add(frame_ms: float) -> void:
	_samples[_next] = frame_ms
	_next = (_next + 1) % _capacity
	_count = mini(_count + 1, _capacity)


func count() -> int:
	return _count


func clear() -> void:
	_next = 0
	_count = 0


## Nearest-rank percentile of the stored frame times, `p` in [0, 100].
func percentile(p: float) -> float:
	if _count == 0:
		return 0.0
	var sorted := _samples.slice(0, _count) if _count < _capacity else _samples.duplicate()
	sorted.sort()
	var rank := int(ceil(clampf(p, 0.0, 100.0) / 100.0 * _count))
	return sorted[clampi(rank - 1, 0, _count - 1)]


func average() -> float:
	if _count == 0:
		return 0.0
	var total := 0.0
	for i in _count:
		total += _samples[i]
	return total / _count
