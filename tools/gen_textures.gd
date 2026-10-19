extends SceneTree
## Generates IONFALL's tiling environment textures (our own work, PLAN §4):
## panel grid and hazard stripes, used with world triplanar mapping.
## Deterministic. Output: res://art/textures/*.png
##
##   godot --headless -s tools/gen_textures.gd

const OUT := "res://art/textures/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_panels().save_png(OUT + "panel_grid.png")
	_hazard().save_png(OUT + "hazard.png")
	print("gen_textures: done")
	quit()


## 2 × 2 panels per tile: dark seams, a soft bevel, slight per-panel tone
## variation and corner bolts.
func _panels() -> Image:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var tones := [1.0, 0.94, 0.97, 0.91]
	for y in size:
		for x in size:
			var px := x % 128
			var py := y % 128
			var e := mini(mini(px, 127 - px), mini(py, 127 - py))
			var v: float = tones[int(x / 128) + 2 * int(y / 128)]
			if e <= 1:
				v = 0.45
			elif e <= 3:
				v *= 0.8
			elif e <= 6:
				v *= 0.97
			var bx := mini(px, 127 - px)
			var by := mini(py, 127 - py)
			if Vector2(bx - 10, by - 10).length() < 3.0:
				v *= 0.7
			img.set_pixel(x, y, Color(v, v, v))
	return img


## Diagonal black/yellow-orange stripes.
func _hazard() -> Image:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var band := int((x + y) / 32) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.62, 0.12) if band else Color(0.08, 0.08, 0.09))
	return img
