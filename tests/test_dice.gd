# Headless test: checks the face reader and simulates many throws.
#   godot --headless --path . --fixed-fps 60 -s tests/test_dice.gd
# --fixed-fps makes every frame advance exactly 1/60 s, so the simulation runs
# as fast as the CPU allows. Exit code 0 = pass, 1 = fail.
extends SceneTree

const DieShapes = preload("res://scripts/die_shapes.gd")
const Tray = preload("res://scripts/tray.gd")
const Roller = preload("res://scripts/roller.gd")

const SEED := 20261003
const D6_STATIONS := 4
const D6_THROWS := 50  # Per station; 6 dice per throw -> 1200 D6 results.
const MIXED_STATIONS := 2
const MIXED_THROWS := 40
const MIXED_SET := [4, 8, 10, 12, 20, 20]
const MAX_ROLL_TIME := 40.0  # Simulated seconds before a roll counts as stuck.
const CHI2_LIMIT := 20.52  # 5 degrees of freedom, p = 0.001.

var failures: Array[String] = []
var counts := {}  # sides -> PackedInt32Array of hits per value
var rolls := 0
var total_nudges := 0
var max_time := 0.0
var pending := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_specs()
	var started := Time.get_ticks_msec()
	for sides in DieShapes.TYPES:
		var arr := PackedInt32Array()
		arr.resize(sides + 1)
		counts[sides] = arr
	var station := 0
	for i in D6_STATIONS:
		_station(station, [6, 6, 6, 6, 6, 6], D6_THROWS)
		station += 1
	for i in MIXED_STATIONS:
		_station(station, MIXED_SET, MIXED_THROWS)
		station += 1
	while pending > 0:
		await process_frame
	_check_distribution()
	print("rolls: %d, nudges: %d, slowest roll: %.1f s simulated, wall time: %.1f s" % [
		rolls, total_nudges, max_time, (Time.get_ticks_msec() - started) / 1000.0])
	for sides in DieShapes.TYPES:
		print("  D%d hits per value: %s" % [sides, Array(counts[sides].slice(1))])
	if failures.is_empty():
		print("PASS")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


# Static checks: every face reads back as itself and values form 1..N.
func _check_specs() -> void:
	for sides in DieShapes.TYPES:
		var spec := DieShapes.spec(sides)
		if spec.faces.size() != sides:
			failures.append("D%d has %d faces" % [sides, spec.faces.size()])
		var values := []
		for f in spec.faces:
			values.append(f.value)
		values.sort()
		if values != range(1, sides + 1):
			failures.append("D%d face values %s" % [sides, values])
		for i in spec.read_dirs.size():
			var basis := Basis(Quaternion(spec.read_dirs[i], Vector3.UP))
			var r := DieShapes.read(spec, basis)
			if r.value != spec.read_values[i] or r.alignment < 0.999:
				failures.append("D%d reader: expected %d got %d" % [sides, spec.read_values[i], r.value])


func _station(index: int, types: Array, throws: int) -> void:
	pending += 1
	var origin := Node3D.new()
	origin.position = Vector3(index * 40.0, 0, 0)  # Far apart: independent trays.
	root.add_child(origin)
	var tray := Tray.new()
	tray.visuals = false
	origin.add_child(tray)
	var roller := Roller.new()
	roller.rng.seed = SEED + index
	origin.add_child(roller)
	for t in throws:
		roller.throw_random(types)
		while roller.rolling and roller.elapsed < MAX_ROLL_TIME:
			await physics_frame
		rolls += 1
		total_nudges += roller.nudges
		max_time = maxf(max_time, roller.elapsed)
		if roller.rolling:
			failures.append("station %d throw %d did not settle" % [index, t])
			roller.rolling = false
		for d in roller.dice:
			var r: Dictionary = d.read()
			if r.value < 1 or r.value > d.sides or r.alignment < Roller.FLAT_DOT:
				failures.append("D%d ended on invalid face (value %d, alignment %.3f)" % [d.sides, r.value, r.alignment])
			else:
				counts[d.sides][r.value] += 1
	roller.clear()
	pending -= 1


func _check_distribution() -> void:
	var hits: PackedInt32Array = counts[6].slice(1)
	var n := 0
	for h in hits:
		n += h
	var expected := n / 6.0
	var chi2 := 0.0
	for h in hits:
		chi2 += pow(h - expected, 2) / expected
	print("D6 chi-square: %.2f over %d results (limit %.2f)" % [chi2, n, CHI2_LIMIT])
	if n < D6_STATIONS * D6_THROWS * 6:
		failures.append("only %d D6 results" % n)
	if chi2 > CHI2_LIMIT:
		failures.append("D6 distribution not uniform: %s chi2=%.2f" % [Array(hits), chi2])
