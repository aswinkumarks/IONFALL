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


## Texels per unit of the original 256 px design: the textures are drawn at
## 4x that resolution, each texel averaging SAMPLES² sub-samples, so seams,
## bevels and bolts stay crisp up close and their edges are anti-aliased.
const DETAIL := 4
const SAMPLES := 4


## 2 × 2 panels per tile: dark seams, a soft bevel, slight per-panel tone
## variation and corner bolts. Measured in design units (256 per tile).
func _panels() -> Image:
	return _supersampled(256, _panel_value)


func _panel_value(x: float, y: float) -> float:
	var tones := [1.0, 0.94, 0.97, 0.91]
	var px := fmod(x, 128.0)
	var py := fmod(y, 128.0)
	var e := minf(minf(px, 128.0 - px), minf(py, 128.0 - py))
	var v: float = tones[int(x / 128.0) + 2 * int(y / 128.0)]
	if e < 2.0:
		v = 0.45
	elif e < 4.0:
		v *= 0.8
	elif e < 7.0:
		v *= 0.97
	if Vector2(minf(px, 128.0 - px) - 10.5, minf(py, 128.0 - py) - 10.5).length() < 3.0:
		v *= 0.7
	return v


## A grey image `design` units across, DETAIL texels per unit, each the mean
## of `value` over its sub-samples.
func _supersampled(design: int, value: Callable) -> Image:
	var size := design * DETAIL
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var step := 1.0 / (DETAIL * SAMPLES)
	for y in size:
		for x in size:
			var sum := 0.0
			for sy in SAMPLES:
				for sx in SAMPLES:
					sum += value.call((x * SAMPLES + sx + 0.5) * step, (y * SAMPLES + sy + 0.5) * step)
			var v := sum / (SAMPLES * SAMPLES)
			img.set_pixel(x, y, Color(v, v, v))
	return img


## Diagonal black/yellow-orange stripes (128 design units across).
func _hazard() -> Image:
	var mask := _supersampled(128, func(x: float, y: float) -> float:
		return 1.0 if int((x + y) / 32.0) % 2 == 0 else 0.0)
	var yellow := Color(0.95, 0.62, 0.12)
	var black := Color(0.08, 0.08, 0.09)
	for y in mask.get_height():
		for x in mask.get_width():
			mask.set_pixel(x, y, black.lerp(yellow, mask.get_pixel(x, y).r))
	return mask
