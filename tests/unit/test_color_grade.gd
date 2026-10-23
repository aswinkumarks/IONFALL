extends GutTest
## Per-map colour grading (PLAN §3.9): a neutral grade is the identity, tints
## move shadows and highlights, and both maps carry a grade.


func test_neutral_grade_is_identity() -> void:
	for c: Color in [Color(0, 0, 0), Color(0.25, 0.5, 0.75), Color(1, 1, 1)]:
		var g := ColorGrade.graded(c, Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0)
		assert_almost_eq(g.r, c.r, 1e-5)
		assert_almost_eq(g.b, c.b, 1e-5)


func test_tints_affect_their_range() -> void:
	var cool := Color(0, 0, 0.1, 0)
	assert_gt(ColorGrade.graded(Color(0.05, 0.05, 0.05), cool, Color(0, 0, 0, 0), 0.0).b, 0.12, "shadows tinted")
	assert_almost_eq(ColorGrade.graded(Color(1, 1, 0.9), cool, Color(0, 0, 0, 0), 0.0).b, 0.9, 0.01, "highlights not")


func test_lut_size_and_maps_have_grades() -> void:
	var lut := ColorGrade.lut({"shadows": Color(0, 0.02, 0.04), "highlights": Color(0.02, 0, 0), "contrast": 0.1})
	assert_eq(lut.get_depth(), ColorGrade.SIZE)
	for map: String in ["station", "spire", "foundry"]:
		var scene: Node = Maps.presentation(map)
		assert_true(scene.has_meta("grade"), map)
		assert_eq(scene.find_children("*", "ReflectionProbe").size(), 1, map + " has its reflection probe")
		scene.free()
