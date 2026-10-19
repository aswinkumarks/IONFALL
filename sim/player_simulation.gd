class_name PlayerSimulation
extends RefCounted
## The part of a tick that only depends on one player's own command: movement
## and weapon state. The server and client-side prediction both run exactly
## this function, which is what makes reconciliation replays match (PLAN §3.2).


static func step(p: SimPlayer, cmd: PlayerCommand, executed: int, match_seed: int) -> Array[WeaponSim.Shot]:
	PlayerMovement.step(p, cmd, executed)
	return WeaponSim.step(p, cmd, executed, match_seed)
