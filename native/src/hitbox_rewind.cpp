#include "hitbox_rewind.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cmath>
#include <limits>

using namespace godot;

namespace ionfall {

namespace {

constexpr double INF_D = std::numeric_limits<double>::infinity();

// Hitbox.SHAPES: [part, bottom height, top height, radius] per stance
// (PlayerSimState.Stance STAND, CROUCH, SLIDE; Hitbox.Part HEAD, TORSO, LEGS).
struct Shape {
	int part;
	double bottom;
	double top;
	double radius;
};

constexpr Shape SHAPES[3][3] = {
	{ { 0, 1.62, 1.62, 0.17 }, { 1, 1.0, 1.3, 0.28 }, { 2, 0.2, 0.95, 0.22 } },
	{ { 0, 1.05, 1.05, 0.17 }, { 1, 0.55, 0.72, 0.28 }, { 2, 0.2, 0.55, 0.24 } },
	{ { 0, 0.85, 0.85, 0.17 }, { 1, 0.42, 0.52, 0.28 }, { 2, 0.2, 0.4, 0.26 } },
};

// GDScript keeps Vector3 components in float and every scalar in double; the
// casts below follow it step for step.
double ray_sphere(const Vector3 &ro, const Vector3 &rd, const Vector3 &c, double r) {
	const Vector3 oc = ro - c;
	const double b = oc.dot(rd);
	const double cc = double(oc.dot(oc)) - r * r;
	const double h = b * b - cc;
	if (h < 0.0) {
		return INF_D;
	}
	double t = -b - std::sqrt(h);
	if (t < 0.0) {
		t = -b + std::sqrt(h);
	}
	return t >= 0.0 ? t : INF_D;
}

double ray_capsule(const Vector3 &ro, const Vector3 &rd, const Vector3 &a, const Vector3 &b, double r) {
	const Vector3 ba = b - a;
	const Vector3 oa = ro - a;
	const double baba = ba.dot(ba);
	if (baba < 1e-8) {
		return ray_sphere(ro, rd, a, r);
	}
	const double bard = ba.dot(rd);
	const double baoa = ba.dot(oa);
	const double rdoa = rd.dot(oa);
	const double oaoa = oa.dot(oa);
	const double qa = baba - bard * bard;
	const double qb = baba * rdoa - baoa * bard;
	const double qc = baba * oaoa - baoa * baoa - r * r * baba;
	if (std::fabs(qa) > 1e-8) {
		const double h = qb * qb - qa * qc;
		if (h >= 0.0) {
			const double t = (-qb - std::sqrt(h)) / qa;
			const double y = baoa + t * bard;
			if (y > 0.0 && y < baba && t >= 0.0) {
				return t;
			}
		}
	}
	const double t_a = ray_sphere(ro, rd, a, r);
	const double t_b = ray_sphere(ro, rd, b, r);
	return t_a < t_b ? t_a : t_b;
}

// Hitbox.intersect(); false on a miss.
bool intersect_pose(const Vector3 &feet, int stance, const Vector3 &from, const Vector3 &dir, double max_dist, double &distance, int &part) {
	if (stance < 0 || stance > 2) {
		return false;
	}
	bool found = false;
	for (const Shape &s : SHAPES[stance]) {
		const Vector3 a = feet + Vector3(0.0f, real_t(s.bottom), 0.0f);
		const Vector3 b = feet + Vector3(0.0f, real_t(s.top), 0.0f);
		const double t = ray_capsule(from, dir, a, b, s.radius);
		if (t <= max_dist && (!found || t < distance)) {
			found = true;
			distance = t;
			part = s.part;
		}
	}
	return found;
}

int posmod(int a, int b) {
	const int m = a % b;
	return m < 0 ? m + b : m;
}

} // namespace

void HitboxRewindNative::record(int net_id, int tick, const Vector3 &position, int stance, bool alive, int life_gen, int discontinuity_gen) {
	Entry &e = rings[net_id].entries[posmod(tick, LENGTH)];
	e.tick = tick;
	e.position = position;
	e.stance = stance;
	e.alive = alive;
	e.life_gen = life_gen;
	e.discontinuity_gen = discontinuity_gen;
}

void HitboxRewindNative::remove(int net_id) {
	rings.erase(net_id);
}

void HitboxRewindNative::clear() {
	rings.clear();
}

const HitboxRewindNative::Entry *HitboxRewindNative::at(const Ring &ring, int tick) const {
	const Entry &e = ring.entries[posmod(tick, LENGTH)];
	return e.tick == tick ? &e : nullptr;
}

// HitboxHistory.sample(); false where it returns null.
bool HitboxRewindNative::sample_entry(int net_id, double view_tick, Entry &out) const {
	const auto it = rings.find(net_id);
	if (it == rings.end()) {
		return false;
	}
	const int t0 = int(std::floor(view_tick));
	const Entry *a = at(it->second, t0);
	const Entry *b = at(it->second, t0 + 1);
	if (a == nullptr) {
		if (b != nullptr && Math::is_equal_approx(view_tick, double(t0 + 1))) {
			out = *b;
			return true;
		}
		return false;
	}
	if (!a->alive) {
		return false;
	}
	const double frac = view_tick - t0;
	if (b == nullptr || frac <= 0.0) {
		out = *a;
		return true;
	}
	if (!b->alive || b->discontinuity_gen != a->discontinuity_gen) {
		return false;
	}
	out = *a;
	out.tick = t0;
	out.position = a->position.lerp(b->position, real_t(frac));
	out.stance = frac < 0.5 ? a->stance : b->stance;
	out.alive = true;
	return true;
}

Array HitboxRewindNative::sample(int net_id, double view_tick) const {
	Array result;
	Entry e;
	if (sample_entry(net_id, view_tick, e)) {
		result.append(e.position);
		result.append(e.stance);
		result.append(e.life_gen);
	}
	return result;
}

PackedFloat64Array HitboxRewindNative::trace(const PackedInt32Array &ids, const PackedInt32Array &life_gens, double view_tick,
		const Vector3 &from, const Vector3 &dir, double max_dist) const {
	PackedFloat64Array result;
	const int64_t n = ids.size() < life_gens.size() ? ids.size() : life_gens.size();
	const int32_t *id_ptr = ids.ptr();
	const int32_t *gen_ptr = life_gens.ptr();
	int best_index = -1;
	double best_distance = INF_D;
	int best_part = 0;
	for (int64_t i = 0; i < n; i++) {
		Entry pose;
		if (!sample_entry(id_ptr[i], view_tick, pose) || pose.life_gen != gen_ptr[i]) {
			continue;
		}
		double d;
		int part;
		if (intersect_pose(pose.position, pose.stance, from, dir, max_dist, d, part) && (best_index < 0 || d < best_distance)) {
			best_index = int(i);
			best_distance = d;
			best_part = part;
		}
	}
	if (best_index >= 0) {
		result.append(best_index);
		result.append(best_distance);
		result.append(best_part);
	}
	return result;
}

PackedFloat64Array HitboxRewindNative::trace_poses(const PackedVector3Array &feet, const PackedInt32Array &stances,
		const Vector3 &from, const Vector3 &dir, double max_dist) {
	PackedFloat64Array result;
	const int64_t n = feet.size() < stances.size() ? feet.size() : stances.size();
	const Vector3 *feet_ptr = feet.ptr();
	const int32_t *stance_ptr = stances.ptr();
	int best_index = -1;
	double best_distance = INF_D;
	int best_part = 0;
	for (int64_t i = 0; i < n; i++) {
		double d;
		int part;
		if (intersect_pose(feet_ptr[i], stance_ptr[i], from, dir, max_dist, d, part) && (best_index < 0 || d < best_distance)) {
			best_index = int(i);
			best_distance = d;
			best_part = part;
		}
	}
	if (best_index >= 0) {
		result.append(best_index);
		result.append(best_distance);
		result.append(best_part);
	}
	return result;
}

PackedFloat64Array HitboxRewindNative::intersect(const Vector3 &feet, int stance, const Vector3 &from, const Vector3 &dir, double max_dist) {
	PackedFloat64Array result;
	double d;
	int part;
	if (intersect_pose(feet, stance, from, dir, max_dist, d, part)) {
		result.append(d);
		result.append(part);
	}
	return result;
}

void HitboxRewindNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("record", "net_id", "tick", "position", "stance", "alive", "life_gen", "discontinuity_gen"), &HitboxRewindNative::record);
	ClassDB::bind_method(D_METHOD("remove", "net_id"), &HitboxRewindNative::remove);
	ClassDB::bind_method(D_METHOD("clear"), &HitboxRewindNative::clear);
	ClassDB::bind_method(D_METHOD("sample", "net_id", "view_tick"), &HitboxRewindNative::sample);
	ClassDB::bind_method(D_METHOD("trace", "ids", "life_gens", "view_tick", "from", "dir", "max_dist"), &HitboxRewindNative::trace);
	ClassDB::bind_static_method("HitboxRewindNative", D_METHOD("trace_poses", "feet", "stances", "from", "dir", "max_dist"), &HitboxRewindNative::trace_poses);
	ClassDB::bind_static_method("HitboxRewindNative", D_METHOD("intersect", "feet", "stance", "from", "dir", "max_dist"), &HitboxRewindNative::intersect);
}

} // namespace ionfall
