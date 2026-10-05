# One physical die: a RigidBody3D with a generated mesh, a convex collision
# shape and procedural markings (pips for the D6, Label3D numbers otherwise).
extends RigidBody3D

const DieShapes = preload("res://scripts/die_shapes.gd")

# Circumradius per type, so all dice look about the same size on the table.
const RADIUS := {4: 1.1, 6: 0.85, 8: 0.95, 10: 0.92, 12: 0.92, 20: 0.98}
const COLORS := {
	4: [Color("c8423b"), Color("fff4e8")],
	6: [Color("f3ead8"), Color("1f2a30")],
	8: [Color("1f8a80"), Color("f6fbf9")],
	10: [Color("6c4bb4"), Color("f7f2ff")],
	12: [Color("e08a2c"), Color("23170b")],
	20: [Color("2d5fb3"), Color("f3f7ff")],
}

static var _bold_font: Font

var sides := 6
var spec: Dictionary
var still_time := 0.0  # Seconds the die has been (almost) motionless.


func setup(p_sides: int) -> void:
	sides = p_sides
	spec = DieShapes.spec(sides)
	var r: float = RADIUS[sides]
	mass = 1.0
	continuous_cd = true
	linear_damp = 0.1
	angular_damp = 0.6
	var mat := PhysicsMaterial.new()
	mat.friction = 0.55
	mat.bounce = 0.3
	physics_material_override = mat

	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for p in DieShapes.vertices(sides):
		pts.append(p * r)
	shape.points = pts
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

	var body := MeshInstance3D.new()
	body.mesh = _build_mesh(r)
	var surface := StandardMaterial3D.new()
	surface.albedo_color = COLORS[sides][0]
	surface.roughness = 0.35
	surface.metallic_specular = 0.6
	body.material_override = surface
	add_child(body)

	if sides == 6:
		_add_pips(r)
	else:
		_add_numbers(r)


func _build_mesh(r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in spec.faces:
		st.set_normal(f.normal)
		var pts: PackedVector3Array = f.points
		for i in range(1, pts.size() - 1):
			# Godot treats clockwise triangles as front faces.
			st.add_vertex(pts[0] * r)
			st.add_vertex(pts[i + 1] * r)
			st.add_vertex(pts[i] * r)
	return st.commit()


func _add_pips(r: float) -> void:
	var pip_mat := StandardMaterial3D.new()
	pip_mat.albedo_color = COLORS[6][1]
	pip_mat.roughness = 0.6
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.085
	mesh.bottom_radius = 0.085
	mesh.height = 0.02
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.material = pip_mat
	# Pip positions on a 3x3 grid (-1..1), per face value.
	var layout := {
		1: [Vector2(0, 0)],
		2: [Vector2(-1, -1), Vector2(1, 1)],
		3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)],
	}
	var spacing := r * 0.33
	for f in spec.faces:
		var n: Vector3 = f.normal
		var u: Vector3 = (f.points[1] - f.points[0]).normalized()
		var w := n.cross(u)
		for g in layout[f.value]:
			var pip := MeshInstance3D.new()
			pip.mesh = mesh
			# Cylinder axis is +Y: align it with the face normal.
			pip.basis = Basis(u, n, -w)
			pip.position = f.center * r + n * 0.002 + (u * g.x + w * g.y) * spacing
			add_child(pip)


func _add_numbers(r: float) -> void:
	for f in spec.faces:
		var center: Vector3 = f.center * r
		var pts: PackedVector3Array = f.points
		# Size the text from the face's inner radius (distance to the closest edge).
		var inner := INF
		for i in pts.size():
			var a := pts[i] * r
			var b := pts[(i + 1) % pts.size()] * r
			inner = min(inner, _distance_to_segment(center, a, b))
		if sides == 4:
			# Real D4 style: each corner shows the value of the vertex it points to.
			for p in pts:
				var corner := p * r
				var value := 1 + Array(DieShapes.vertices(4)).find(p)
				_add_label(str(value), center.lerp(corner, 0.58), f.normal, (corner - center).normalized(), inner * 0.8)
		else:
			# Text "up" points to the farthest corner (the apex on D10 kites).
			var far := pts[0]
			for p in pts:
				if (p - f.center).length() > (far - f.center).length() + 1e-4:
					far = p
			var text := str(f.value)
			if sides >= 10 and (f.value == 6 or f.value == 9):
				text += "."
			var height := inner * (1.15 if text.length() == 1 else 0.95)
			var pos := center
			if sides == 10:
				pos = center.lerp(far * r, 0.18)
			_add_label(text, pos, f.normal, (far * r - center).normalized(), height)


func _add_label(text: String, pos: Vector3, normal: Vector3, up: Vector3, height: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = _font()
	label.font_size = 96
	label.pixel_size = height / 96.0
	label.outline_size = 0
	label.modulate = COLORS[sides][1]
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	# Label3D faces +Z, so build a basis whose Z is the face normal.
	var x := up.cross(normal).normalized()
	label.basis = Basis(x, normal.cross(x), normal)
	label.position = pos + normal * 0.004
	add_child(label)


static func _font() -> Font:
	if _bold_font == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.9
		_bold_font = fv
	return _bold_font


static func _distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	return p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))


# Face value that points up right now, plus how well it is aligned (1 = flat).
func read() -> Dictionary:
	return DieShapes.read(spec, global_basis.orthonormalized())


func is_still() -> bool:
	return linear_velocity.length() < 0.05 and angular_velocity.length() < 0.08
