extends Control
## Dark circuit board with traces that carry drifting data pulses. Every screen uses it
## as the bottom layer so the whole game shares one backdrop.

const Style := preload("res://ui/style.gd")

var traces: Array = []
var t := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_build)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build() -> void:
	traces.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 311
	for i in range(16):
		var point := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y)).snapped(Vector2(40, 40))
		var path: Array = [point]
		for step in range(rng.randi_range(3, 6)):
			var along_x := step % 2 == 0
			var delta := rng.randi_range(2, 7) * 40 * (1 if rng.randf() < 0.5 else -1)
			point += Vector2(delta, 0) if along_x else Vector2(0, delta)
			path.append(point)
		var total := 0.0
		for j in range(1, path.size()):
			total += path[j - 1].distance_to(path[j])
		traces.append({"points": PackedVector2Array(path), "length": total, "speed": rng.randf_range(60, 140),
			"offset": rng.randf_range(0, total), "color": [Style.CYAN, Style.PURPLE, Style.GOLD][i % 3]})

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Style.BG)
	var grid := Color(Style.CYAN, 0.04)
	for x in range(0, int(size.x), 40):
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid)
	for y in range(0, int(size.y), 40):
		draw_line(Vector2(0, y), Vector2(size.x, y), grid)
	for trace in traces:
		var points: PackedVector2Array = trace.points
		draw_polyline(points, Color(trace.color, 0.12), 2.0, true)
		draw_circle(points[0], 4, Color(trace.color, 0.25))
		draw_circle(points[points.size() - 1], 4, Color(trace.color, 0.25))
		var pulse := _point_along(points, fmod(trace.offset + t * trace.speed, trace.length))
		draw_circle(pulse, 7, Color(trace.color, 0.12))
		draw_circle(pulse, 3, Color(trace.color, 0.7))

func _point_along(points: PackedVector2Array, distance: float) -> Vector2:
	for j in range(1, points.size()):
		var segment := points[j - 1].distance_to(points[j])
		if distance <= segment:
			return points[j - 1].lerp(points[j], distance / max(segment, 0.001))
		distance -= segment
	return points[points.size() - 1]
