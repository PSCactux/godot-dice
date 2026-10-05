# Non-headless capture tool: runs the demo, throws, flings with a simulated
# mouse drag and saves docs/screenshot.png plus numbered frames for a GIF.
#   godot --path . --fixed-fps 30 --resolution 1280x720 -s tools/capture.gd -- --frames=/tmp/dice-frames
# Then: tools/make_gif.sh /tmp/dice-frames
# Without --frames only the screenshot is written.
extends SceneTree

var main: Node3D
var frames_dir := ""
var frame := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames_dir = arg.trim_prefix("--frames=")
			DirAccess.make_dir_recursive_absolute(frames_dir)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	main.roller.rng.seed = 7
	seed(7)
	main.counts = {4: 1, 6: 2, 8: 1, 10: 1, 12: 1, 20: 1}
	main._refresh_counts()
	main.throw_random()
	await _record_until_settled()
	await _record(1.2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screenshot.png")
	print("saved docs/screenshot.png")

	# Second throw: a few pawns, then a drag from bottom-left toward the right.
	for i in 3:
		main.drop_pawn()
	await _record(0.8)
	var size := root.get_visible_rect().size
	var start := Vector2(size.x * 0.25, size.y * 0.78)
	var end := Vector2(size.x * 0.55, size.y * 0.45)
	_mouse_button(start, true)
	for i in 8:
		_mouse_motion(start.lerp(end, (i + 1) / 8.0))
		await _record(1.0 / 30.0)
	_mouse_button(end, false)
	await _record_until_settled()
	await _record(1.5)
	print("frames: %d" % frame)
	quit()


func _record_until_settled() -> void:
	await _record(0.1)
	var t := 0.0
	while main.roller.rolling and t < 20.0:
		await _record(1.0 / 30.0)
		t += 1.0 / 30.0


func _record(seconds: float) -> void:
	var steps := maxi(1, roundi(seconds * 30.0))
	for i in steps:
		await RenderingServer.frame_post_draw
		if frames_dir != "":
			root.get_texture().get_image().save_png(frames_dir.path_join("f%04d.png" % frame))
			frame += 1


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev)


func _mouse_motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev)
