# Scene setup, input and UI. Everything is built in code so the project has no
# binary assets: click/tap or Space throws, dragging flings the dice.
extends Node3D

const DieShapes = preload("res://scripts/die_shapes.gd")
const Tray = preload("res://scripts/tray.gd")
const Roller = preload("res://scripts/roller.gd")

const MAX_DICE := 12
const DRAG_THRESHOLD := 14.0  # Pixels before a press becomes a fling.
const PAWN_COLORS := [Color("d9483b"), Color("2f6fd0"), Color("e9b934"), Color("3a9a54"), Color("f2f2f2"), Color("232323")]

var counts := {4: 0, 6: 2, 8: 0, 10: 0, 12: 0, 20: 1}
var roller: Node3D
var camera: Camera3D
var pawns: Node3D
var count_labels := {}
var result_box: HBoxContainer
var total_label: Label
var drag_overlay: Control
var drag_start := Vector2.ZERO
var drag_now := Vector2.ZERO
var drag_time := 0.0
var clock := 0.0  # Game time, used to measure drag speed.
var dragging := false
var floating_labels: Array = []


func _ready() -> void:
	_build_world()
	_build_ui()
	roller.roll_started.connect(_on_roll_started)
	roller.roll_finished.connect(_on_roll_finished)
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	throw_random()


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("120d0a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("ffe2c4")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 35, 0)
	sun.light_color = Color("fff1dc")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	sun.shadow_bias = 0.03
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-6, 7, 6)
	fill.light_color = Color("ffc58a")
	fill.light_energy = 0.7
	fill.omni_range = 22.0
	add_child(fill)

	camera = Camera3D.new()
	add_child(camera)

	add_child(Tray.new())
	roller = Roller.new()
	roller.rng.randomize()
	add_child(roller)
	pawns = Node3D.new()
	add_child(pawns)


func _process(delta: float) -> void:
	clock += delta


# Keep the whole tray visible on portrait screens too.
func _fit_camera() -> void:
	var window := get_window()
	var portrait := window.size.y > window.size.x
	# Bigger UI on phones held upright.
	window.content_scale_size = Vector2i(720, 1280) if portrait else Vector2i(1280, 720)
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	if portrait:
		camera.position = Vector3(0, 21, 10)
		camera.look_at_from_position(camera.position, Vector3(0, 0, 1.8))
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = 48.0
	else:
		# Landscape: look slightly left of center so the tray clears the dice panel.
		camera.look_at_from_position(Vector3(-1.4, 14.5, 9.5), Vector3(-1.4, 0, 0.6))
		camera.keep_aspect = Camera3D.KEEP_HEIGHT if aspect >= 1.45 else Camera3D.KEEP_WIDTH
		camera.fov = 44.0 if aspect >= 1.45 else 62.0


# ---------------------------------------------------------------- throwing

func selected_types() -> Array:
	var types := []
	for sides in DieShapes.TYPES:
		for i in counts[sides]:
			types.append(sides)
	return types


func throw_random() -> void:
	roller.throw_random(selected_types())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			throw_random()
		elif event.keycode == KEY_P:
			drop_pawn()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			drag_start = event.position
			drag_now = event.position
			drag_time = clock
		elif dragging:
			dragging = false
			drag_overlay.queue_redraw()
			_release(event.position)
	elif event is InputEventMouseMotion and dragging:
		drag_now = event.position
		drag_overlay.queue_redraw()


func _release(pos: Vector2) -> void:
	if pos.distance_to(drag_start) < DRAG_THRESHOLD:
		throw_random()
		return
	var a = _tray_point(drag_start)
	var b = _tray_point(pos)
	if a == null or b == null:
		throw_random()
		return
	var dt := maxf(clock - drag_time, 0.08)
	var dir: Vector3 = b - a
	# Faster and longer drags throw harder; clamp to keep the dice in the tray.
	var speed := clampf(dir.length() / dt * 0.9, 5.0, 26.0)
	roller.fling(selected_types(), a, dir.normalized() * speed)


# Mouse position projected onto the tray floor (y = 0).
func _tray_point(screen: Vector2):
	var from := camera.project_ray_origin(screen)
	var normal := camera.project_ray_normal(screen)
	return Plane(Vector3.UP, 0).intersects_ray(from, normal)


func drop_pawn() -> void:
	var half := Tray.INNER / 2
	var pawn := RigidBody3D.new()
	pawn.mass = 1.5
	pawn.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	pawn.center_of_mass = Vector3(0, -0.25, 0)
	pawn.continuous_cd = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PAWN_COLORS[pawns.get_child_count() % PAWN_COLORS.size()]
	mat.roughness = 0.3
	var base := CylinderMesh.new()
	base.top_radius = 0.16
	base.bottom_radius = 0.38
	base.height = 0.8
	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.48
	for part in [[base, Vector3.ZERO], [head, Vector3(0, 0.55, 0)]]:
		var m := MeshInstance3D.new()
		m.mesh = part[0]
		m.position = part[1]
		m.material_override = mat
		pawn.add_child(m)
	var body_shape := CylinderShape3D.new()
	body_shape.radius = 0.36
	body_shape.height = 0.8
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.24
	for part in [[body_shape, Vector3.ZERO], [head_shape, Vector3(0, 0.55, 0)]]:
		var c := CollisionShape3D.new()
		c.shape = part[0]
		c.position = part[1]
		pawn.add_child(c)
	var felt := PhysicsMaterial.new()
	felt.bounce = 0.05
	pawn.physics_material_override = felt
	pawn.position = Vector3(randf_range(-half.x + 1, half.x - 1), 3.0, randf_range(-half.y + 1, half.y - 1))
	pawn.rotation = Vector3(randf_range(-0.15, 0.15), randf() * TAU, randf_range(-0.15, 0.15))
	pawns.add_child(pawn)


func clear_pawns() -> void:
	for p in pawns.get_children():
		p.queue_free()


# ---------------------------------------------------------------- results

func _on_roll_started() -> void:
	for l in floating_labels:
		l.queue_free()
	floating_labels.clear()
	for c in result_box.get_children():
		c.queue_free()
	total_label.text = "Rolling…"


func _on_roll_finished(results: Array) -> void:
	var total := 0
	for i in results.size():
		var r: Dictionary = results[i]
		total += r.value
		var chip := Label.new()
		chip.text = "D%d: %d" % [r.sides, r.value]
		chip.add_theme_stylebox_override("normal", _chip_style(roller.Die.COLORS[r.sides][0]))
		chip.add_theme_color_override("font_color", roller.Die.COLORS[r.sides][1])
		result_box.add_child(chip)
		# Floating number above the die.
		var die: Node3D = roller.dice[i]
		var tag := Label3D.new()
		tag.text = str(r.value)
		tag.font_size = 72
		tag.pixel_size = 0.006
		tag.outline_size = 16
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.top_level = true
		add_child(tag)
		tag.global_position = die.global_position + Vector3.UP * 1.6
		floating_labels.append(tag)
	total_label.text = "Total: %d" % total if not results.is_empty() else "Pick some dice"


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	layer.add_child(root)

	drag_overlay = Control.new()
	drag_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	drag_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_overlay.draw.connect(_draw_drag)
	root.add_child(drag_overlay)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	root.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	col.add_child(grid)
	for sides in DieShapes.TYPES:
		var minus := Button.new()
		minus.text = "−"
		minus.pressed.connect(_change_count.bind(sides, -1))
		var name_label := Label.new()
		name_label.text = "D%d" % sides
		name_label.custom_minimum_size.x = 44
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_label.add_theme_color_override("font_color", roller.Die.COLORS[sides][0].lightened(0.25))
		var count := Label.new()
		count.custom_minimum_size.x = 22
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_labels[sides] = count
		var plus := Button.new()
		plus.text = "+"
		plus.pressed.connect(_change_count.bind(sides, 1))
		# Two dice types per row: D4 - n +   D6 - n +
		for c in [name_label, minus, count, plus]:
			grid.add_child(c)
	var buttons := HBoxContainer.new()
	col.add_child(buttons)
	for b in [["Roll", throw_random], ["Pawn", drop_pawn], ["Clear pawns", clear_pawns]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		buttons.add_child(btn)
	var hint := Label.new()
	hint.text = "Click or Space: throw\nDrag: fling with your own force"
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.65)
	col.add_child(hint)

	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 16
	root.add_child(bottom)
	var row := VBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(row)
	result_box = HBoxContainer.new()
	result_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(result_box)
	total_label = Label.new()
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 26)
	row.add_child(total_label)
	_refresh_counts()


func _change_count(sides: int, delta: int) -> void:
	var total := 0
	for s in counts:
		total += counts[s]
	if delta > 0 and total >= MAX_DICE:
		return
	counts[sides] = clampi(counts[sides] + delta, 0, MAX_DICE)
	_refresh_counts()


func _refresh_counts() -> void:
	for sides in count_labels:
		count_labels[sides].text = str(counts[sides])


func _draw_drag() -> void:
	if not dragging or drag_now.distance_to(drag_start) < DRAG_THRESHOLD:
		return
	var color := Color(1, 0.9, 0.7, 0.8)
	drag_overlay.draw_line(drag_start, drag_now, color, 4.0, true)
	var dir := (drag_now - drag_start).normalized()
	var side := dir.orthogonal() * 10.0
	drag_overlay.draw_colored_polygon(PackedVector2Array([drag_now + dir * 14, drag_now + side, drag_now - side]), color)
	drag_overlay.draw_circle(drag_start, 6.0, color)


func _theme() -> Theme:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.06, 0.05, 0.78)
	panel.set_corner_radius_all(12)
	panel.set_content_margin_all(12)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("3a2a1e")
	btn.set_corner_radius_all(8)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 4
	btn.content_margin_bottom = 4
	var hover := btn.duplicate()
	hover.bg_color = Color("5a4130")
	var pressed := btn.duplicate()
	pressed.bg_color = Color("7a5a40")
	theme.set_stylebox("normal", "Button", btn)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_font_size("font_size", "Button", 17)
	theme.set_font_size("font_size", "Label", 17)
	theme.set_color("font_color", "Label", Color("f4e9dc"))
	return theme


func _chip_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s
