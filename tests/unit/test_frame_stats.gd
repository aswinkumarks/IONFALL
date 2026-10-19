extends GutTest


func test_empty_stats_return_zero() -> void:
	var stats := FrameStats.new(10)
	assert_eq(stats.percentile(95.0), 0.0)
	assert_eq(stats.average(), 0.0)


func test_nearest_rank_percentiles() -> void:
	var stats := FrameStats.new(100)
	for i in range(1, 101):
		stats.add(float(i))
	assert_eq(stats.percentile(50.0), 50.0)
	assert_eq(stats.percentile(95.0), 95.0)
	assert_eq(stats.percentile(99.0), 99.0)
	assert_eq(stats.percentile(100.0), 100.0)


func test_ring_buffer_keeps_latest_samples() -> void:
	var stats := FrameStats.new(4)
	for v in [100.0, 100.0, 1.0, 2.0, 3.0, 4.0]:
		stats.add(v)
	assert_eq(stats.count(), 4)
	assert_eq(stats.percentile(100.0), 4.0, "old 100 ms samples were overwritten")
	assert_almost_eq(stats.average(), 2.5, 0.0001)
