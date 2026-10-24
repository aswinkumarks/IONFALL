extends SceneTree
## Generates IONFALL's sound effects and ambient music loop (our own
## synthesis, no third-party audio; PLAN §4). Deterministic: the same seed
## always produces the same files. Output: res://audio/generated/*.wav
##
##   godot --headless -s tools/gen_sounds.gd

const RATE := 22050
const OUT := "res://audio/generated/"

var _rng := RandomNumberGenerator.new()
## Music noise has its own generator, so the music can change without
## changing any sound effect.
var _music_rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 7741
	_music_rng.seed = 2401
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_save("pulse_rifle", _gun(0.16, 520.0, 160.0, 0.55, 0.9))
	_save("mag_pistol", _gun(0.22, 380.0, 110.0, 0.7, 1.0))
	_save("arc_launch", _launch())
	_save("explosion", _explosion())
	_save("footstep_1", _step(0.0))
	_save("footstep_2", _step(0.35))
	_save("footstep_3", _step(0.7))
	_save("land", _land())
	_save("jump", _whoosh(0.16, 900.0))
	_save("slide", _slide())
	_save("hit_marker", _tick(2400.0, 0.05))
	_save("kill_confirm", _chime([1320.0, 1760.0], 0.35))
	_save("shield_break", _shield_break())
	_save("shield_recharge", _sweep(300.0, 900.0, 0.6, 0.25))
	_save("reload", _reload())
	_save("switch", _tick(900.0, 0.06))
	_save("ui_click", _tick(1600.0, 0.03))
	_save("spawn", _sweep(200.0, 700.0, 0.5, 0.3))
	_save_loop("ambient_loop", _pad_loop(24.0, 0.55, 0.0))
	# M3 weapons (appended so the earlier sounds keep their random sequence).
	_save("burst_rifle", _gun(0.12, 600.0, 200.0, 0.5, 0.85))
	_save("scatter_gun", _gun(0.38, 240.0, 60.0, 1.0, 1.1))
	_save("rail_sniper", _gun(0.5, 1900.0, 180.0, 0.8, 1.0))
	_save("frag_grenade", _whoosh(0.22, 700.0))
	_save("melee", _melee_swing())
	# M4 audio pass.
	_save("footstep_ally_1", _soft_step(0.0))
	_save("footstep_ally_2", _soft_step(0.4))
	_save("footstep_ally_3", _soft_step(0.8))
	_save("pickup", _chime([880.0, 1108.73, 1318.51], 0.4))
	_save("countdown", _tick(880.0, 0.12))
	_save("go", _chime([659.25, 987.77, 1318.51], 0.5))
	_save("reload_shell", _tick(700.0, 0.05))
	_save_loop("menu_theme", _pad_loop(32.0, 1.0, 1.0))
	# Post-v1 weapons (appended).
	_save("flux_smg", _gun(0.1, 760.0, 260.0, 0.45, 0.75))
	_save("melee_hit", _melee_hit())
	print("gen_sounds: done")
	quit()


# --- Building blocks ---

func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## One-pole low-pass state helper.
func _lp(prev: float, x: float, cutoff: float) -> float:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	return prev + a * (x - prev)


func _env(t: float, attack: float, decay: float) -> float:
	return clampf(t / attack, 0.0, 1.0) * exp(-t / decay) if attack > 0.0 else exp(-t / decay)


# --- Sounds ---

## Energy weapon shot: filtered noise crack + a falling tone.
func _gun(length: float, f0: float, f1: float, noise_amt: float, gain: float) -> PackedFloat32Array:
	var b := _buffer(length)
	var phase := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, minf(t / length, 1.0))
		phase += TAU * f / RATE
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 3500.0)
		var tone := sin(phase) * 0.6 + sin(phase * 2.01) * 0.25
		b[i] = (tone * _env(t, 0.002, length * 0.35) + lp * noise_amt * _env(t, 0.0005, 0.03)) * gain
	return b


func _launch() -> PackedFloat32Array:
	var b := _buffer(0.5)
	var lp := 0.0
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 900.0 + 1500.0 * exp(-t / 0.1))
		phase += TAU * lerpf(140.0, 60.0, t / 0.5) / RATE
		b[i] = (lp * 1.4 * _env(t, 0.003, 0.18) + sin(phase) * 0.5 * _env(t, 0.005, 0.12))
	return b


func _explosion() -> PackedFloat32Array:
	var b := _buffer(1.4)
	var lp := 0.0
	var lp2 := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var n := _rng.randf_range(-1.0, 1.0)
		lp = _lp(lp, n, 400.0 + 2500.0 * exp(-t / 0.05))
		lp2 = _lp(lp2, lp, 180.0)
		b[i] = (lp * 0.9 * _env(t, 0.002, 0.25) + lp2 * 2.5 * _env(t, 0.01, 0.5)) * 0.9
	return b


## Footstep on metal panels: a short thump plus a bright tick, varied.
func _step(variant: float) -> PackedFloat32Array:
	var b := _buffer(0.14)
	var lp := 0.0
	var phase := 0.0
	var f := 95.0 + variant * 30.0
	for i in b.size():
		var t := float(i) / RATE
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 1800.0 + variant * 900.0)
		phase += TAU * f / RATE
		b[i] = sin(phase) * 0.7 * _env(t, 0.002, 0.03) + lp * 0.55 * _env(t, 0.0005, 0.015)
	return b


## A teammate's footstep (PLAN §3.12): duller and lower than an enemy's, so
## enemy steps stand out.
func _soft_step(variant: float) -> PackedFloat32Array:
	var b := _buffer(0.12)
	var lp := 0.0
	var phase := 0.0
	var f := 70.0 + variant * 20.0
	for i in b.size():
		var t := float(i) / RATE
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 600.0 + variant * 300.0)
		phase += TAU * f / RATE
		b[i] = sin(phase) * 0.6 * _env(t, 0.003, 0.035) + lp * 0.5 * _env(t, 0.001, 0.02)
	return b


func _land() -> PackedFloat32Array:
	var b := _buffer(0.3)
	var lp := 0.0
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 900.0)
		phase += TAU * 70.0 / RATE
		b[i] = sin(phase) * 0.9 * _env(t, 0.003, 0.07) + lp * 0.7 * _env(t, 0.001, 0.04)
	return b


func _whoosh(length: float, cutoff: float) -> PackedFloat32Array:
	var b := _buffer(length)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), cutoff)
		b[i] = lp * 0.8 * sin(PI * t / length)
	return b


func _slide() -> PackedFloat32Array:
	var b := _buffer(0.8)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 2200.0)
		b[i] = lp * 0.5 * _env(t, 0.03, 0.4)
	return b


func _tick(freq: float, length: float) -> PackedFloat32Array:
	var b := _buffer(length)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += TAU * freq / RATE
		b[i] = sin(phase) * 0.6 * _env(t, 0.0005, length * 0.3)
	return b


func _chime(freqs: Array, length: float) -> PackedFloat32Array:
	var b := _buffer(length)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for j in freqs.size():
			var start := j * 0.06
			if t >= start:
				v += sin(TAU * freqs[j] * (t - start)) * _env(t - start, 0.002, 0.12)
		b[i] = v * 0.4
	return b


## Shield break: glassy inharmonic partials over a noise burst.
func _shield_break() -> PackedFloat32Array:
	var b := _buffer(0.7)
	var partials := [1870.0, 2630.0, 3410.0, 4170.0]
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for p: float in partials:
			v += sin(TAU * p * t) * _env(t, 0.001, 0.08 + p / 40000.0)
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 5000.0)
		b[i] = v * 0.22 + lp * 0.4 * _env(t, 0.0005, 0.05)
	return b


func _sweep(f0: float, f1: float, length: float, gain: float) -> PackedFloat32Array:
	var b := _buffer(length)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / length) / RATE
		b[i] = (sin(phase) + 0.3 * sin(phase * 2.0)) * gain * sin(PI * t / length)
	return b


func _reload() -> PackedFloat32Array:
	var b := _buffer(0.6)
	for click: float in [0.0, 0.32]:
		var phase := 0.0
		var lp := 0.0
		for i in range(int(click * RATE), mini(int((click + 0.08) * RATE), b.size())):
			var t := float(i) / RATE - click
			phase += TAU * 1300.0 / RATE
			lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 4000.0)
			b[i] += (sin(phase) * 0.3 + lp * 0.5) * _env(t, 0.0005, 0.02)
	return b


## Ambient pad: slow detuned chord changes, seamless loop.
## Music (menu theme and the in-match bed): a slow, filtered pad of detuned
## saws over open chords (D, Bm, G, Asus), crossfading with no beat, a soft
## sub and a band of air; `bells` adds sparse soft bell tones with an echo.
## `brightness` scales the filter (the match bed is darker). Rendered with a
## tail that is crossfaded into the start, so the loop is seamless.
func _pad_loop(seconds: float, brightness: float, bells: float) -> PackedFloat32Array:
	var chords := [
		[73.42, [146.83, 220.0, 329.63, 369.99]],  # D(add9)
		[61.74, [185.0, 246.94, 293.66, 440.0]],  # Bm7
		[49.0, [146.83, 246.94, 369.99, 440.0]],  # Gmaj9
		[55.0, [164.81, 220.0, 293.66, 329.63]],  # Asus
	]
	var tail := 4.0
	var n := int((seconds + tail) * RATE)
	var b := PackedFloat32Array()
	b.resize(n)
	var per := seconds / chords.size()
	var fade_s := 2.5
	var detune := [0.9965, 1.0, 1.0035]
	var phases := PackedFloat32Array()
	phases.resize(chords.size() * 4 * detune.size())
	var sub_phase := [0.0, 0.0, 0.0, 0.0]
	var lp1 := 0.0
	var lp2 := 0.0
	var air_lp := 0.0
	var air_hp := 0.0
	var bell := PackedFloat32Array()
	bell.resize(n)
	if bells > 0.0:
		# A soft bell every half chord, on a chord tone two octaves up.
		var picks := [3, 1, 2, 0, 1, 3, 0, 2]
		var count := int(seconds / (per * 0.5))
		for k in count:
			var start := k * per * 0.5 + 0.6
			var chord: Array = chords[int(start / per) % chords.size()][1]
			var f: float = chord[picks[k % picks.size()]] * 2.0
			var i0 := int(start * RATE)
			for i in int(3.0 * RATE):
				if i0 + i >= n:
					break
				var t := float(i) / RATE
				var mod := 1.2 * exp(-t / 0.35) * sin(TAU * f * 2.0 * t)
				bell[i0 + i] += sin(TAU * f * t + mod) * _env(t, 0.004, 0.9) * 0.5
		# Echo: 3/8 s feedback delay.
		var d := int(0.375 * RATE)
		for i in range(d, n):
			bell[i] += bell[i - d] * 0.42
	for i in n:
		var t := float(i) / RATE
		var x := fmod(t, seconds) / per
		var idx := int(x) % chords.size()
		var local := (x - floorf(x)) * per
		var w_next := smoothstep(per - fade_s, per, local)
		var pad := 0.0
		var sub := 0.0
		for c in chords.size():
			var w := 0.0
			if c == idx:
				w = 1.0 - w_next
			elif c == (idx + 1) % chords.size():
				w = w_next
			var notes: Array = chords[c][1]
			for j in notes.size():
				for k in detune.size():
					var pi := (c * 4 + j) * detune.size() + k
					phases[pi] = fmod(phases[pi] + notes[j] * detune[k] / RATE, 1.0)
					if w > 0.0:
						pad += (2.0 * phases[pi] - 1.0) * w
			sub_phase[c] = fmod(sub_phase[c] + chords[c][0] / RATE, 1.0)
			if w > 0.0:
				sub += sin(TAU * sub_phase[c]) * w
		# The filter breathes once per loop.
		var cutoff := (520.0 + 380.0 * sin(TAU * t / seconds)) * brightness + 180.0
		lp1 = _lp(lp1, pad, cutoff)
		lp2 = _lp(lp2, lp1, cutoff)
		var noise := _music_rng.randf_range(-1.0, 1.0)
		air_lp = _lp(air_lp, noise, 2400.0)
		air_hp = _lp(air_hp, air_lp, 900.0)
		var air := (air_lp - air_hp) * (0.5 + 0.5 * sin(TAU * t / (seconds * 0.5)))
		b[i] = lp2 * 0.05 + sub * 0.07 + air * 0.025 + bell[i] * 0.05 * bells
	# Seamless loop: the tail crossfades into the head.
	var tn := int(tail * RATE)
	var out := PackedFloat32Array()
	out.resize(int(seconds * RATE))
	for i in out.size():
		out[i] = b[i]
		if i < tn:
			var a := float(i) / tn
			out[i] = b[i] * sin(a * PI * 0.5) + b[int(seconds * RATE) + i] * cos(a * PI * 0.5)
	return out


## Melee swing: the whoosh (same noise as before) over a low thump.
func _melee_swing() -> PackedFloat32Array:
	var b := _whoosh(0.18, 1500.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] += sin(TAU * (95.0 - 220.0 * t) * t) * _env(t, 0.004, 0.045) * 0.7
	return b


## Melee hit: a dull body impact (low drop, a short crack, a mid knock).
func _melee_hit() -> PackedFloat32Array:
	var b := _buffer(0.28)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp = _lp(lp, _rng.randf_range(-1.0, 1.0), 2600.0)
		var low := sin(TAU * (130.0 - 260.0 * t) * t) * _env(t, 0.002, 0.08)
		var knock := sin(TAU * 310.0 * t) * _env(t, 0.001, 0.025)
		b[i] = low * 0.9 + lp * _env(t, 0.0005, 0.015) * 0.8 + knock * 0.35
	return b


# --- Output ---

func _to_wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	var peak := 0.0
	for v in b:
		peak = maxf(peak, absf(v))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	for i in b.size():
		bytes.encode_s16(i * 2, clampi(roundi(b[i] * gain * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _save(sound_name: String, b: PackedFloat32Array) -> void:
	_to_wav(b).save_to_wav(OUT + sound_name + ".wav")


func _save_loop(sound_name: String, b: PackedFloat32Array) -> void:
	var w := _to_wav(b)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = b.size()
	w.save_to_wav(OUT + sound_name + ".wav")
