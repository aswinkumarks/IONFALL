class_name Sim
extends RefCounted
## Simulation-wide constants (PLAN §3.2). All gameplay timings are integer
## ticks at 60 Hz; seconds are only for readability.

const TICK_RATE := 60
const TICK_DT := 1.0 / 60.0

## Physics layers. Player bodies only collide with the world, so players pass
## through each other and replays depend only on the local player (PLAN §3.2).
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
## Jump pad trigger zones (JumpPads): only queried, never collided with.
const LAYER_PAD := 4


static func ticks(seconds: float) -> int:
	return int(round(seconds * TICK_RATE))


## Deterministic 32-bit hash used to seed per-shot randomness.
static func hash_ints(values: Array[int]) -> int:
	var h := 2166136261
	for v in values:
		for i in 4:
			h = ((h ^ ((v >> (i * 8)) & 0xFF)) * 16777619) & 0xFFFFFFFF
	return h
