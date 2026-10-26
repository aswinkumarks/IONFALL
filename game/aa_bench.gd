class_name AaBench
extends Node
## `--aa-bench` (with `--autopilot` for an unattended run on a phone): after
## START_DELAY seconds of the match, cycles the anti-aliasing modes for
## SEGMENT seconds each, ROUNDS times over, and logs each mode's GPU time
## and frame time (p50/p95) to the PERF log, then restores the setting.
## Answers m4.md's open question on the device: does MSAA (resolved in tile
## memory on Adreno and Mali) cost less than FXAA's full-screen pass?
##
##   adb shell run-as <app> ... launch_args.txt:
##   --play --autopilot --aa-bench --perf-log [--aa-bench-quit]

const MODES := ["off", "fxaa", "msaa_2x", "msaa_4x"]
const START_DELAY := 20.0
const SEGMENT := 20.0
const SETTLE := 2.0  ## seconds after a switch left out (pipelines compile)
const ROUNDS := 2

## While true, the match's adaptive quality holds still (its step-downs
## would change the render scale under the measurement).
static var running := false

var _time := 0.0
var _segment := -1
var _gpu := {}  ## mode -> FrameStats (ms)
var _frame := {}  ## mode -> FrameStats (ms)
var _scale := {}  ## mode -> lowest render scale seen (adaptive quality)


func _ready() -> void:
	for m: String in MODES:
		_gpu[m] = FrameStats.new(int(SEGMENT * 120.0 * ROUNDS))
		_frame[m] = FrameStats.new(int(SEGMENT * 120.0 * ROUNDS))
		_scale[m] = 1.0
	running = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _exit_tree() -> void:
	running = false


func _process(delta: float) -> void:
	_time += delta
	var t := _time - START_DELAY
	if t < 0.0:
		return
	var segment := int(t / SEGMENT)
	if segment >= MODES.size() * ROUNDS:
		_finish()
		return
	var mode: String = MODES[segment % MODES.size()]
	if segment != _segment:
		_segment = segment
		apply(get_viewport(), mode)
	if fmod(t, SEGMENT) < SETTLE:
		return
	_gpu[mode].add(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	_frame[mode].add(delta * 1000.0)
	_scale[mode] = minf(_scale[mode], get_viewport().scaling_3d_scale)


## Puts `vp` in anti-aliasing `mode` (Settings.ANTI_ALIASING) for now,
## without saving it.
static func apply(vp: Viewport, mode: String) -> void:
	var aa := Settings.anti_aliasing_for(mode, {})
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa.x]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa.y == 1 else Viewport.SCREEN_SPACE_AA_DISABLED


func _finish() -> void:
	for m: String in MODES:
		var gpu: FrameStats = _gpu[m]
		var frame: FrameStats = _frame[m]
		Platform.perf_log("AA_BENCH mode=%s gpu_p50=%.2f gpu_p95=%.2f frame_p50=%.2f frame_p95=%.2f frames=%d min_scale=%.2f" % [
				m, gpu.percentile(50.0), gpu.percentile(95.0), frame.percentile(50.0), frame.percentile(95.0),
				gpu.count(), _scale[m]])
	Settings.apply_video()
	if Platform.user_args.has("--aa-bench-quit"):
		get_tree().quit()
	queue_free()
