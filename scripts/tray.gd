# Wooden dice tray: felt floor, low wooden rim and invisible tall walls plus a
# ceiling so nothing can leave the box. Textures are generated at runtime.
extends Node3D

const INNER := Vector2(14.0, 9.0)  # Playable area (x, z).
const RIM_HEIGHT := 0.9
const RIM_WIDTH := 0.7
const WALL_HEIGHT := 12.0

var visuals := true


func _ready() -> void:
	_build()


func _build() -> void:
	var felt := PhysicsMaterial.new()
	felt.friction = 0.8
	felt.bounce = 0.2
	var wood := PhysicsMaterial.new()
	wood.friction = 0.4
	wood.bounce = 0.45

	var floor_size := Vector3(INNER.x + RIM_WIDTH * 2, 0.4, INNER.y + RIM_WIDTH * 2)
	_box(Vector3(0, -0.2, 0), floor_size, felt, _felt_material() if visuals else null)

	var hx := INNER.x / 2 + RIM_WIDTH / 2
	var hz := INNER.y / 2 + RIM_WIDTH / 2
	var wood_mat := _wood_material() if visuals else null
	var long_side := Vector3(INNER.x + RIM_WIDTH * 2, RIM_HEIGHT, RIM_WIDTH)
	var short_side := Vector3(RIM_WIDTH, RIM_HEIGHT, INNER.y)
	for side in [-1, 1]:
		_box(Vector3(0, RIM_HEIGHT / 2, hz * side), long_side, wood, wood_mat)
		_box(Vector3(hx * side, RIM_HEIGHT / 2, 0), short_side, wood, wood_mat)
		# Invisible walls on top of the rim.
		_box(Vector3(0, WALL_HEIGHT / 2, hz * side), Vector3(long_side.x, WALL_HEIGHT, RIM_WIDTH), wood, null)
		_box(Vector3(hx * side, WALL_HEIGHT / 2, 0), Vector3(RIM_WIDTH, WALL_HEIGHT, INNER.y), wood, null)
	_box(Vector3(0, WALL_HEIGHT, 0), Vector3(floor_size.x, 0.4, floor_size.z), wood, null)

	if visuals:
		# A darker table under the tray so the scene does not float in the void.
		var table := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(240, 240)
		table.mesh = plane
		table.position.y = -0.41
		var table_mat := _wood_material(Color("1c120b"), Color("2a1b11"))
		table_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
		table.material_override = table_mat
		add_child(table)


func _box(pos: Vector3, size: Vector3, phys: PhysicsMaterial, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.physics_material_override = phys
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	if mat:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = mat
		body.add_child(mesh)
	add_child(body)


func _felt_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.35
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var base := Color("123c2c")
	for y in 128:
		for x in 128:
			var n := noise.get_noise_2d(x, y) * 0.06
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 1.0
	mat.uv1_scale = Vector3(6, 4, 1)
	return mat


# Simple procedural wood: stretched noise drives sine "growth rings".
func _wood_material(dark := Color("4a2c17"), light := Color("7a5030")) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.015
	noise.seed = 7
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var n := noise.get_noise_2d(x * 0.25, y * 2.0)
			var t := 0.5 + 0.5 * sin(y * 0.3 + n * 3.0)
			img.set_pixel(x, y, dark.lerp(light, t * t))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 0.55
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	return mat
