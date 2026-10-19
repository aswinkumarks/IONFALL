# 0001: Physics backend is Jolt Physics

- **Status:** accepted (M0)
- **Context:** PLAN §3.2 requires the physics backend to be pinned, since it affects replay determinism and is part of the compatibility hash. Godot 4.7 offers `Jolt Physics` and `GodotPhysics3D`; the project default (`DEFAULT`) could change between engine versions.
- **Decision:** set `physics/3d/physics_engine="Jolt Physics"` explicitly.
- **Why Jolt:** it's built into Godot 4.7, actively maintained, and generally more stable for character-vs-world collision than GodotPhysics3D. Player movement only collides with static world geometry (players pass through each other), which keeps replays independent of other players.
- **Revisit if:** the M1a same-build replay tests or the M1b cross-platform bound (≤ 1 cm) fail because of the backend. Switching then needs this note updated and the compatibility hash changes automatically (the `[physics]` section is hashed).
