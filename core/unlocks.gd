class_name Unlocks
extends RefCounted
## Cosmetic unlocks by profile level (PLAN §3.13: cosmetic only). Locked
## picks fall back to the defaults, so an older profile's choice never
## shows something it hasn't earned.

## Level needed for each PlayerVisual.PALETTE index (0 = auto).
const COLOR_LEVELS := [1, 1, 1, 1, 1, 2, 4, 6, 8, 10, 12, 15]
## Level needed for each CharacterRig.SELECTABLE entry.
const CHARACTER_LEVELS := {"sentinel": 1, "vanguard": 2, "operative": 3, "spacer": 5}


static func level() -> int:
	return ProfileData.level_for(Profile.data.xp()).level


static func color_level(index: int) -> int:
	return COLOR_LEVELS[index] if index >= 0 and index < COLOR_LEVELS.size() else 1


static func character_level(style: String) -> int:
	return CHARACTER_LEVELS.get(style, 1)


## What reaching `to` from `from` unlocks: translation keys / colour labels.
static func unlocked_between(from: int, to: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in CharacterRig.SELECTABLE.size():
		var need := character_level(CharacterRig.SELECTABLE[i])
		if need > from and need <= to:
			out.append(CharacterRig.SELECTABLE_KEYS[i])
	for i in COLOR_LEVELS.size():
		if COLOR_LEVELS[i] > from and COLOR_LEVELS[i] <= to:
			out.append("UNLOCK_COLOR_%d" % i)
	return out
