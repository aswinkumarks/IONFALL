class_name ColorGrade
extends RefCounted
## Per-map colour grading (PLAN §3.9): a SIZE³ LUT built at load from the
## grade the map builder stores on the presentation root (meta "grade":
## {shadows: Color, highlights: Color, contrast: float}; tints are added,
## ±0.1 is strong). Building it takes a few milliseconds.

const SIZE := 16

static var _cache: Dictionary = {}  ## str(grade) -> ImageTexture3D


static func lut(grade: Dictionary) -> ImageTexture3D:
	var key := str(grade)
	if _cache.has(key):
		return _cache[key]
	var images: Array[Image] = []
	for b in SIZE:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		for g in SIZE:
			for r in SIZE:
				img.set_pixel(r, g, graded(Color(r, g, b) / float(SIZE - 1), grade.shadows, grade.highlights, grade.contrast))
		images.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, SIZE, SIZE, SIZE, false, images)
	_cache[key] = tex
	return tex


static func graded(c: Color, shadows: Color, highlights: Color, contrast: float) -> Color:
	var lum := c.get_luminance()
	var out := Color(c.r, c.g, c.b)
	for i in 3:
		var v: float = c[i] + shadows[i] * (1.0 - lum) * (1.0 - lum) + highlights[i] * lum * lum
		v = clampf(v, 0.0, 1.0)
		out[i] = lerpf(v, v * v * (3.0 - 2.0 * v), contrast)
	return out
