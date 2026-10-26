#pragma once

// Native lag-compensation rewind (PLAN §3.17): the per-player
// hitbox history of sim/hitbox_history.gd plus the capsule ray tests of
// sim/hitbox.gd, behind one batched trace() call. It mirrors the GDScript
// arithmetic exactly (Vector3 in float, scalars in double), so both give the
// same hits; tests/unit/test_hitbox_native.gd checks that.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <unordered_map>

namespace ionfall {

class HitboxRewindNative : public godot::RefCounted {
	GDCLASS(HitboxRewindNative, godot::RefCounted)

public:
	// Same as HitboxHistory.LENGTH.
	static constexpr int LENGTH = 30;

	struct Entry {
		int tick = -1;
		godot::Vector3 position;
		int stance = 0;
		bool alive = false;
		int life_gen = 0;
		int discontinuity_gen = 0;
	};

	struct Ring {
		Entry entries[LENGTH];
	};

	void record(int net_id, int tick, const godot::Vector3 &position, int stance, bool alive, int life_gen, int discontinuity_gen);
	void remove(int net_id);
	void clear();

	// [position, stance, life_gen], or [] where HitboxHistory.sample() gives null.
	godot::Array sample(int net_id, double view_tick) const;

	// Nearest hit of the ray against the players `ids` rewound to `view_tick`,
	// skipping any whose sampled life_gen isn't the matching `life_gens` entry
	// (SimWorld._pose). [index into ids, distance, part], or [] on a miss.
	godot::PackedFloat64Array trace(const godot::PackedInt32Array &ids, const godot::PackedInt32Array &life_gens, double view_tick,
			const godot::Vector3 &from, const godot::Vector3 &dir, double max_dist) const;

	// The same against explicit poses (no rewind): [index, distance, part] or [].
	static godot::PackedFloat64Array trace_poses(const godot::PackedVector3Array &feet, const godot::PackedInt32Array &stances,
			const godot::Vector3 &from, const godot::Vector3 &dir, double max_dist);

	// Hitbox.intersect(): [distance, part] or [].
	static godot::PackedFloat64Array intersect(const godot::Vector3 &feet, int stance, const godot::Vector3 &from, const godot::Vector3 &dir, double max_dist);

protected:
	static void _bind_methods();

private:
	std::unordered_map<int, Ring> rings;

	const Entry *at(const Ring &ring, int tick) const;
	bool sample_entry(int net_id, double view_tick, Entry &out) const;
};

} // namespace ionfall
