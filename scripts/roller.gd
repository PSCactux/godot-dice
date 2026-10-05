# Spawns, throws and watches a set of dice. Emits roll_finished once every die
# is still and lying flat; cocked dice (leaning on a wall or another die) get a
# small random nudge until they land on a face.
extends Node3D

signal roll_started
signal roll_finished(results: Array)  # [{ "sides": int, "value": int }]

const Die = preload("res://scripts/die.gd")
const Tray = preload("res://scripts/tray.gd")

const SETTLE_TIME := 0.35  # Seconds a die must stay still to count as stopped.
const FLAT_DOT := 0.97  # cos(~14 deg): below this the die is considered cocked.
const NUDGE_AFTER := 12.0  # Seconds before nudging dice that never stop moving.
const SPAWN_HEIGHT := 3.5

var dice: Array = []
var rolling := false
var elapsed := 0.0
var nudges := 0  # Nudges used in the current roll (handy for tests).
var rng := RandomNumberGenerator.new()


func clear() -> void:
	for d in dice:
		d.queue_free()
	dice.clear()
	rolling = false


# Default throw: from the near edge of the tray toward a random spot.
func throw_random(types: Array) -> void:
	var half := Tray.INNER / 2
	var origin := Vector3(rng.randf_range(-half.x + 2, half.x - 2), SPAWN_HEIGHT, half.y - 1.5)
	var target := Vector3(rng.randf_range(-half.x + 2, half.x - 2), 0, rng.randf_range(-half.y + 2, 1.0))
	var dir := (target - origin)
	dir.y = 0
	var velocity := dir.normalized() * rng.randf_range(6.0, 11.0) + Vector3.UP * rng.randf_range(0.0, 3.0)
	throw_dice(types, origin, velocity)


# Throw with a user-given direction and speed (from a mouse/touch drag).
func fling(types: Array, from: Vector3, velocity: Vector3) -> void:
	throw_dice(types, Vector3(from.x, SPAWN_HEIGHT, from.z), velocity + Vector3.UP * 1.5)


func throw_dice(types: Array, origin: Vector3, velocity: Vector3) -> void:
	clear()
	var half := Tray.INNER / 2
	var cols := 4
	# Keep the whole spawn grid inside the walls.
	origin.x = clampf(origin.x, -half.x + 4.3, half.x - 4.3)
	origin.z = clampf(origin.z, -half.y + 1.6, half.y - 1.6)
	for i in types.size():
		var d := Die.new()
		d.setup(types[i])
		# Small grid around the origin, stacked in layers, kept inside the walls.
		var offset := Vector3((i % cols - (cols - 1) / 2.0) * 2.1, (i / cols) * 2.1, rng.randf_range(-0.3, 0.3))
		d.position = origin + offset
		d.quaternion = _random_rotation()
		d.linear_velocity = velocity + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		d.angular_velocity = _random_unit() * rng.randf_range(8.0, 22.0)
		add_child(d)
		dice.append(d)
	rolling = not dice.is_empty()
	elapsed = 0.0
	nudges = 0
	roll_started.emit()
	if dice.is_empty():
		roll_finished.emit([])


func _physics_process(delta: float) -> void:
	if not rolling:
		return
	elapsed += delta
	var all_still := true
	for d in dice:
		if d.position.y < -2.0:  # Safety net, should never happen with the walls.
			d.position = Vector3(0, SPAWN_HEIGHT, 0)
			d.linear_velocity = Vector3.ZERO
		d.still_time = d.still_time + delta if d.is_still() else 0.0
		if d.still_time < SETTLE_TIME:
			all_still = false
	if not all_still:
		if elapsed > NUDGE_AFTER * (nudges + 1):
			for d in dice:
				if d.still_time < SETTLE_TIME:
					_nudge(d)
		return
	var cocked := dice.filter(func(d): return d.read().alignment < FLAT_DOT)
	if not cocked.is_empty():
		for d in cocked:
			_nudge(d)
		return
	rolling = false
	roll_finished.emit(results())


func results() -> Array:
	var out := []
	for d in dice:
		out.append({"sides": d.sides, "value": d.read().value})
	return out


func _nudge(d) -> void:
	nudges += 1
	d.still_time = 0.0
	d.sleeping = false
	d.apply_central_impulse(Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(4.0, 6.0), rng.randf_range(-1.5, 1.5)))
	d.apply_torque_impulse(_random_unit() * rng.randf_range(0.3, 0.8))


func _random_unit() -> Vector3:
	return Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()


# Uniformly distributed random rotation (Shoemake's method).
func _random_rotation() -> Quaternion:
	var u1 := rng.randf()
	var u2 := rng.randf() * TAU
	var u3 := rng.randf() * TAU
	var a := sqrt(1.0 - u1)
	var b := sqrt(u1)
	return Quaternion(a * sin(u2), a * cos(u2), b * sin(u3), b * cos(u3))
