# Pure geometry for the supported dice. Every die is generated from a list of
# vertices: we compute the convex hull faces, sort each face's corners, and
# assign face values so that opposite faces add up to sides + 1.
#
# A "spec" is a Dictionary:
#   sides      : int
#   faces      : Array of { normal: Vector3, center: Vector3, points: PackedVector3Array, value: int }
#   read_dirs  : PackedVector3Array  local directions that are tested against world UP
#   read_values: PackedInt32Array    value shown when read_dirs[i] points up
# For every die except the D4 the read directions are the face normals. A D4
# has no top face, so it is read by the vertex that points up (like real D4s).
extends RefCounted

const TYPES: Array[int] = [4, 6, 8, 10, 12, 20]
const PHI := 1.618033988749895
const EPS := 1e-4

static var _cache := {}


static func spec(sides: int) -> Dictionary:
	if not _cache.has(sides):
		_cache[sides] = _build_spec(sides)
	return _cache[sides]


# Unit-circumradius vertex list for each die.
static func vertices(sides: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	match sides:
		4:
			pts = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)])
		6:
			for x in [-1, 1]:
				for y in [-1, 1]:
					for z in [-1, 1]:
						pts.append(Vector3(x, y, z))
		8:
			pts = PackedVector3Array([Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK])
		10:
			# Pentagonal trapezohedron: two poles plus a zig-zag ring of 10 vertices.
			# The pole height keeps every kite face planar.
			var ring_offset := 0.1
			var c := cos(deg_to_rad(36.0))
			var pole := ring_offset * (1.0 + c) / (1.0 - c)
			pts.append(Vector3(0, pole, 0))
			pts.append(Vector3(0, -pole, 0))
			for k in 10:
				var a := deg_to_rad(36.0 * k)
				pts.append(Vector3(cos(a), ring_offset * (1 if k % 2 == 0 else -1), sin(a)))
		12:
			for x in [-1, 1]:
				for y in [-1, 1]:
					for z in [-1, 1]:
						pts.append(Vector3(x, y, z))
			for a in [-1, 1]:
				for b in [-1, 1]:
					pts.append(Vector3(0, a / PHI, b * PHI))
					pts.append(Vector3(a / PHI, b * PHI, 0))
					pts.append(Vector3(a * PHI, 0, b / PHI))
		20:
			for a in [-1, 1]:
				for b in [-1, 1]:
					pts.append(Vector3(0, a, b * PHI))
					pts.append(Vector3(a, b * PHI, 0))
					pts.append(Vector3(a * PHI, 0, b))
		_:
			push_error("Unsupported die: D%d" % sides)
	var radius := 0.0
	for p in pts:
		radius = max(radius, p.length())
	for i in pts.size():
		pts[i] /= radius
	return pts


# Brute-force convex hull: fine for at most 20 vertices, computed once per type.
static func hull_faces(points: PackedVector3Array) -> Array:
	var faces := []
	var n := points.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var normal := (points[j] - points[i]).cross(points[k] - points[i])
				if normal.length() < EPS:
					continue
				normal = normal.normalized()
				var d := normal.dot(points[i])
				var above := false
				var below := false
				for p in points:
					var s := normal.dot(p) - d
					if s > EPS:
						above = true
					elif s < -EPS:
						below = true
				if above and below:
					continue
				if above:
					normal = -normal
					d = -d
				if faces.any(func(f): return f.normal.dot(normal) > 1.0 - EPS):
					continue
				var on_plane := PackedVector3Array()
				for p in points:
					if absf(normal.dot(p) - d) < EPS:
						on_plane.append(p)
				faces.append(_make_face(normal, on_plane))
	return faces


static func _make_face(normal: Vector3, pts: PackedVector3Array) -> Dictionary:
	var center := Vector3.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	# Sort corners counter-clockwise when seen from outside.
	var u := (pts[0] - center).normalized()
	var w := normal.cross(u)
	var sorted := Array(pts)
	sorted.sort_custom(func(a, b):
		return atan2((a - center).dot(w), (a - center).dot(u)) < atan2((b - center).dot(w), (b - center).dot(u)))
	return {"normal": normal, "center": center, "points": PackedVector3Array(sorted), "value": 0}


static func _build_spec(sides: int) -> Dictionary:
	var pts := vertices(sides)
	var faces := hull_faces(pts)
	var result := {"sides": sides, "faces": faces, "read_dirs": PackedVector3Array(), "read_values": PackedInt32Array()}
	if sides == 4:
		# Vertex i shows value i + 1; the face opposite a vertex carries the same value.
		for i in pts.size():
			result.read_dirs.append(pts[i].normalized())
			result.read_values.append(i + 1)
		for f in faces:
			for i in pts.size():
				if not f.points.has(pts[i]):
					f.value = i + 1
		return result
	# Pair opposite faces: v on one side, sides + 1 - v on the other.
	var next_value := 1
	for f in faces:
		if f.value != 0:
			continue
		f.value = next_value
		for g in faces:
			if g.value == 0 and g.normal.dot(f.normal) < -1.0 + EPS:
				g.value = sides + 1 - next_value
		next_value += 1
	for f in faces:
		result.read_dirs.append(f.normal)
		result.read_values.append(f.value)
	return result


# Value whose read direction points most upward for a given orientation.
static func read(spec_data: Dictionary, basis: Basis) -> Dictionary:
	var best := -2.0
	var value := 0
	for i in spec_data.read_dirs.size():
		var dot: float = (basis * spec_data.read_dirs[i]).dot(Vector3.UP)
		if dot > best:
			best = dot
			value = spec_data.read_values[i]
	return {"value": value, "alignment": best}
