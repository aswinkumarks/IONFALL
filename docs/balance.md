# Balance configuration

Every value that changes how the game plays lives in a resource file under `data/`. Open one in
the Godot editor (double-click it in the FileSystem dock) to edit it in the Inspector, where the
fields are grouped and each has a tooltip. You can also edit the `.tres` files as text.

| File | What it tunes |
|---|---|
| `data/weapons/<weapon>.tres` | One per weapon: damage, headshot multiplier, range falloff, spread, pellets, recoil (kick up and sideways per shot, cap, recovery delay and speed, scoped share), fire rate, bursts, reload, magazine and reserve (`infinite_reserve`: loadout weapons never run out; the map's power weapons have limited ammo), scope zoom and spread, projectile speed, splash and self-damage, grenade fuse and bounce. Melee is `melee.tres`, grenades `frag_grenade.tres`. |
| `data/player.tres` | Shield and health maxima, regeneration delays and rates, spawn protection, grenades per life and throw cooldown, melee cone and back-stab angle, assists, pickup radius, dropped-weapon lifetime. |
| `data/movement_config.tres` | Walk, sprint and crouch speeds, acceleration, gravity, jumps and double jump, slide, mantle, body size. |
| `data/modes.tres` | Score limits per mode, respawn delays, countdown, post-match, default time limit, sudden death, Capture the Flag (flag return, capture points), co-op wave count and size. |
| `data/bots.tres` | Bot difficulty levels (Easy, Normal, Hard, Insane): reaction time, turn speed, aim error, extra error on moving targets, grenade chance, how much recoil they pull back down. Also what bots see (range, field of view), their fighting ranges, when they retreat and what they fetch. |

Units: times are ticks (the simulation runs at 60 ticks per second, so 60 = 1 s, 300 = 5 s),
distances are metres, angles are degrees.

Things to know:

- Everything in `data/` is part of the build's compatibility hash, so host and players must run
  builds with the same values to play together. Change values, then make a new build for everyone.
- `tests/unit/test_balance.gd` checks each weapon's time-to-kill against the design table in
  `PLAN.md` §2.3, and `tests/unit/test_balance_config.gd` checks that the bot levels still get
  harder from Easy to Insane. When you change a weapon's damage or fire rate on purpose, update the
  expected numbers in the test too.
- Map-specific values (pickup spots, their respawn times, which power weapons a map has) are in each
  map's layout script under `maps/`.
