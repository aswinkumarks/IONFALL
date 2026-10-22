extends Node
## Dev tool: renders the app icons and store graphics (PLAN §3.18 store art).
##   godot --path . res://tools/store_art.tscn --resolution 1024x500
## Writes art/icon/*.png (Android launcher and adaptive icons, used by the
## export presets), docs/release/art/icon-512.png and feature-graphic.png.

const BG := "res://art/icon/background.svg"
const FG := "res://art/icon/foreground.svg"
const OUT := "res://docs/release/art/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var bg := _svg(BG, 1024)
	var fg := _svg(FG, 1024)
	var full := bg.duplicate() as Image
	full.blend_rect(fg, Rect2i(Vector2i.ZERO, fg.get_size()), Vector2i.ZERO)
	_save(full, 512, OUT + "icon-512.png")
	_save(full, 192, "res://art/icon/main_192.png")
	_save(fg, 432, "res://art/icon/adaptive_foreground_432.png")
	_save(bg, 432, "res://art/icon/adaptive_background_432.png")
	await _feature_graphic(full)
	get_tree().quit()


func _svg(path: String, size: int) -> Image:
	var img := Image.new()
	img.load_svg_from_string(FileAccess.get_file_as_string(path), size / 1024.0)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(src: Image, size: int, path: String) -> void:
	var img := src.duplicate() as Image
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	img.save_png(path)
	print("saved ", path)


## 1024 × 500: the station backdrop, title, tagline and the icon mark.
func _feature_graphic(icon: Image) -> void:
	get_window().size = Vector2i(1024, 500)
	var backdrop := Node3D.new()
	backdrop.set_script(load("res://ui/main_menu/menu_backdrop.gd"))
	add_child(backdrop)
	var layer := CanvasLayer.new()
	add_child(layer)
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(UiStyle.BG, 0.92), Color(UiStyle.BG, 0.55), Color(UiStyle.BG, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_to = Vector2(1, 0)
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var box := VBoxContainer.new()
	box.theme = UiStyle.theme  # a CanvasLayer doesn't inherit the window's theme
	box.position = Vector2(80, 110)
	box.add_theme_constant_override("separation", 6)
	layer.add_child(box)
	var mark := TextureRect.new()
	var small := icon.duplicate() as Image
	small.resize(132, 132, Image.INTERPOLATE_LANCZOS)
	mark.texture = ImageTexture.create_from_image(small)
	mark.stretch_mode = TextureRect.STRETCH_KEEP
	mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(mark)
	var title := UiStyle.label("IONFALL", &"TitleLabel")
	title.add_theme_font_size_override("font_size", 150)
	box.add_child(title)
	var tagline := UiStyle.label("Arena combat in orbit · Play bots, LAN or online", &"DimLabel")
	tagline.add_theme_font_size_override("font_size", 34)
	box.add_child(tagline)
	for i in 90:  # let the backdrop settle and lightmaps stream in
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.resize(1024, 500, Image.INTERPOLATE_LANCZOS)
	shot.save_png(OUT + "feature-graphic.png")
	print("saved ", OUT + "feature-graphic.png")
