class_name AdaptiveQuality
extends RefCounted
## Automatic quality step-down (PLAN §3.10): when frame times stay above the
## target, or the phone reports thermal pressure, lower one video setting at a
## time for the rest of the session (Settings.adaptive, never saved). Order:
## MSAA off (when anti-aliasing is on "auto"; phones' Medium has 2x), then
## render scale in 0.1 steps down to 0.5, then effects density, then sun
## shadows. Glow is left alone: toggling it changes pipeline specializations,
## and on the Mi 11X the resulting compile burst made frames worse (M4). It
## never steps back up by itself: heat builds slowly and the player can always
## restore settings by hand.

const WINDOW_SECONDS := 10.0
const SLOW_WINDOWS := 3  ## consecutive slow windows (30 s) before a step
const SLOW_FACTOR := 1.2  ## p95 above the target frame time × this is slow
const COOLDOWN_WINDOWS := 2  ## windows to wait after a step
const MIN_SCALE := 0.5
const LOW_EFFECTS := 0.4
const THERMAL_SEVERE := 3  ## PowerManager.THERMAL_STATUS_SEVERE
const HEADROOM_LIMIT := 0.95  ## getThermalHeadroom: 1.0 = throttling

## Returns Vector2(thermal status, headroom); -1 / NAN where unknown.
var thermal: Callable = func() -> Vector2:
	return Vector2(Platform.thermal_status(), Platform.thermal_headroom())

var _window := FrameStats.new(2400)
var _elapsed: float = 0.0
var _slow: int = 0
var _cooldown: int = 0


## Feed every frame of a match. Returns a description of the step taken
## (for the log), or "".
func add_frame(delta: float, target_fps: int) -> String:
	_window.add(delta * 1000.0)
	_elapsed += delta
	if _elapsed < WINDOW_SECONDS:
		return ""
	_elapsed = 0.0
	var p95 := _window.percentile(95.0)
	_window.clear()
	var t: Vector2 = thermal.call()
	if _cooldown > 0:
		_cooldown -= 1
		return ""
	_slow = _slow + 1 if p95 > 1000.0 / maxf(target_fps, 1.0) * SLOW_FACTOR else 0
	var hot := t.x >= THERMAL_SEVERE or (not is_nan(t.y) and t.y >= HEADROOM_LIMIT)
	if not hot and _slow < SLOW_WINDOWS:
		return ""
	_slow = 0
	var step := step_down()
	if step.is_empty():
		return ""
	_cooldown = COOLDOWN_WINDOWS
	return "%s (p95 %.1f ms, thermal %d, headroom %.2f)" % [step, p95, t.x, t.y]


## Lowers the next setting; returns "key=value", or "" at the floor.
static func step_down() -> String:
	if Settings.get_value("video", "anti_aliasing") == "auto" and int(Settings.video("msaa")) > 0:
		return _lower("msaa", 0)
	var scale := float(Settings.video("render_scale"))
	if scale > MIN_SCALE + 0.01:
		return _lower("render_scale", maxf(snappedf(scale - 0.1, 0.05), MIN_SCALE))
	if float(Settings.video("effects")) > LOW_EFFECTS + 0.01:
		return _lower("effects", LOW_EFFECTS)
	if Settings.video("shadows"):
		return _lower("shadows", false)
	return ""


static func _lower(key: String, value: Variant) -> String:
	Settings.set_adaptive(key, value)
	return "%s=%s" % [key, value]
