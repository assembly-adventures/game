extends Control
## The level as a corridor of gates. The robot walks on as each gate opens, and the Chip
## Chomper trails behind, one step closer for each strike. On the last strike it bites the
## robot and drags it back a gate.
## Every gate level (levels/gate_level.gd) shows one above its puzzle.

const Style := preload("res://ui/style.gd")
const Characters := preload("res://ui/characters.gd")
const BG := Style.BG
const CYAN := Style.CYAN
const PURPLE := Style.PURPLE
const GOLD := Style.GOLD
const GREEN := Style.GREEN
const RED := Style.RED
const ORANGE := Style.ORANGE
const DIM := Style.DIM
const TEXT := Style.TEXT

signal bitten  ## The moment the Chomper's jaws close on the robot.

var total := 0
var opened: Array = []
var stars: Dictionary = {}
var index := 0
var robot_pos := 0.0  # Measured in gates, so positions survive resizes; total means at the CPU.
var hop := 0.0
var tilt := 0.0
var hurt := 0.0
var chomper_x := 0.0
var strikes := 0
var max_strikes := 3
var mouth := 0.3
var lunge := 0.0
var rush := 0.0  # Pulls the Chomper onto the robot while it bites and drags.
var pop := 0.0
var fled := 0.0
var t := 0.0
var last_pos := 0.0
var skids := 0
var robot_sprite
var chomper_sprite

func _init() -> void:
	custom_minimum_size = Vector2(0, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The robot is added last so it stays in front: the Chomper clamps onto its back and drags
	# it, rather than swallowing it.
	chomper_sprite = Characters.Chomper.new()
	add_child(chomper_sprite)
	robot_sprite = Characters.Robot.new()
	add_child(robot_sprite)

func setup(count: int, solved_flags: Array) -> void:
	total = count
	opened.clear()
	for i in range(count):
		opened.append(1.0 if i < solved_flags.size() and solved_flags[i] else 0.0)
	index = 0
	robot_pos = 0.0
	chomper_x = -60.0

func gate_x(i: int) -> float:
	return 150.0 + (size.x - 280.0) * i / maxf(total - 1, 1)

func _stand_x(i: int) -> float:
	return gate_x(i) - 44.0 if i < total else size.x - 84.0

func robot_x() -> float:
	var i := floori(robot_pos)
	return lerpf(_stand_x(i), _stand_x(i + 1), robot_pos - i)

func walk_to(i: int) -> void:
	index = i
	var duration := clampf(absf(i - robot_pos) * 0.45, 0.25, 1.8)
	create_tween().set_trans(Tween.TRANS_SINE).tween_property(self, "robot_pos", float(i), duration)
	var bounce := create_tween().set_loops(maxi(1, int(duration / 0.25)))
	bounce.tween_property(self, "hop", 5.0, 0.12)
	bounce.tween_property(self, "hop", 0.0, 0.13)

func open_gate(i: int, star_count: int) -> void:
	stars[i] = star_count
	strikes = 0
	create_tween().tween_method(func(value: float): opened[i] = value, 0.0, 1.0, 0.45)
	Style.burst(self, Vector2(gate_x(i), size.y - 100), [GREEN, GOLD, CYAN, Color.WHITE], 26, 240.0, 70.0, 480.0)
	robot_sprite.cheer = 0.9
	var jump := create_tween()
	jump.tween_property(self, "hop", 16.0, 0.15).set_ease(Tween.EASE_OUT)
	jump.tween_property(self, "hop", 0.0, 0.25).set_ease(Tween.EASE_IN)

func set_strikes(count: int) -> void:
	strikes = count

func chomp(count: int) -> void:
	strikes = count
	var tween := create_tween()
	tween.tween_property(self, "lunge", 1.0, 0.12)
	for k in range(2):
		tween.tween_property(self, "mouth", 1.0, 0.07)
		tween.tween_property(self, "mouth", 0.05, 0.07)
	tween.tween_property(self, "lunge", 0.0, 0.3)
	tween.tween_property(self, "mouth", 0.3, 0.1)

## The last strike: the Chomper rushes in, clamps onto the robot's back, drags it back to gate
## `to_index` and lets go, and the gate it was dragged back through closes again. With no gate
## to go back to, it clamps on and lets go where the robot stands.
func bite(to_index: int) -> void:
	var dragged := to_index < index
	index = to_index
	var tween := create_tween()
	tween.tween_property(self, "rush", 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "mouth", 1.0, 0.28)
	tween.tween_property(self, "mouth", 0.0, 0.06)
	tween.parallel().tween_property(self, "hurt", 1.0, 0.06)
	tween.tween_callback(_impact)
	tween.tween_interval(0.09)  # A beat of freeze-frame sells the hit.
	tween.tween_property(self, "mouth", 0.5, 0.08)
	tween.tween_property(self, "mouth", 0.0, 0.06)
	if dragged:
		tween.tween_property(self, "tilt", -0.4, 0.12)
		tween.tween_property(self, "robot_pos", float(to_index), 0.9).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_method(_skid, 0.0, 1.0, 0.9)
	tween.tween_property(self, "mouth", 1.0, 0.1)
	tween.tween_callback(_let_go.bind(to_index, dragged))
	tween.tween_property(self, "rush", 0.0, 0.4).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "tilt", 0.0, 0.3)
	tween.parallel().tween_property(self, "hurt", 0.0, 0.5)
	tween.parallel().tween_method(func(value: float): hop = sin(value * PI) * 6.0, 0.0, 1.0, 0.3)
	if dragged:
		tween.parallel().tween_method(func(value: float): opened[to_index] = value, 1.0, 0.0, 0.25)
	tween.tween_property(self, "mouth", 0.3, 0.2)
	await tween.finished

func _impact() -> void:
	pop = 1.0
	bitten.emit()
	Style.burst(self, Vector2(robot_x(), size.y - 58), [PURPLE, CYAN, Color.WHITE], 22, 210.0, 160.0, 520.0)

## Sparks off the robot's wheels, three times over the drag.
func _skid(progress: float) -> void:
	var puff := int(progress * 3.0)
	if puff > skids:
		skids = puff
		Style.burst(self, Vector2(robot_x() + 8, size.y - 32), [GOLD, ORANGE, Color.WHITE], 6, 120.0, 70.0, 300.0, 3.0, 0.4)

func _let_go(to_index: int, dragged: bool) -> void:
	skids = 0
	strikes = 0
	if dragged:
		stars.erase(to_index)

func finish() -> void:
	walk_to(total)
	create_tween().tween_property(self, "fled", 1.0, 1.4)
	get_tree().create_timer(0.9, false).timeout.connect(func():
		robot_sprite.cheer = 4.0
		Style.burst(self, Vector2(size.x - 34, size.y - 64), [GREEN, GOLD, CYAN, PURPLE, Color.WHITE], 44, 320.0, 80.0, 520.0, 6.0, 1.1))

func _process(delta: float) -> void:
	t += delta
	pop = move_toward(pop, 0.0, delta * 1.2)
	chomper_x = lerpf(chomper_x, robot_x() - (130.0 - 30.0 * mini(strikes, max_strikes - 1)), minf(1.0, delta * 2.5))
	robot_sprite.position = Vector2(robot_x(), size.y - 32.0)
	robot_sprite.hop = hop
	robot_sprite.tilt = tilt
	robot_sprite.hurt = hurt
	robot_sprite.walking = absf(robot_pos - last_pos) > 0.0001 and rush == 0.0
	last_pos = robot_pos
	chomper_sprite.position = _chomper_center()
	chomper_sprite.mouth = mouth
	chomper_sprite.chew = rush == 0.0 and lunge == 0.0
	chomper_sprite.modulate.a = 1.0 - fled
	queue_redraw()

func _chomper_center() -> Vector2:
	var chase := lerpf(maxf(chomper_x, 26.0) + lunge * 26.0, robot_x() - 44.0, rush)
	return Vector2(chase - fled * 260.0, size.y - 55.0)

func _draw() -> void:
	var font := get_theme_default_font()
	var floor_y := size.y - 30.0
	draw_line(Vector2(0, floor_y), Vector2(size.x, floor_y), Color(CYAN, 0.35), 3)
	for k in range(6):
		draw_circle(Vector2(fmod(t * 90.0 + k * size.x / 6.0, size.x), floor_y), 3, Color(CYAN, 0.6))
	# The CPU core at the end of the corridor is where the robot is headed.
	var core := Vector2(size.x - 34, floor_y - 34)
	for k in range(4):
		draw_line(core + Vector2(-14 + k * 9, -28), core + Vector2(-14 + k * 9, 28), Color("7d8494"), 2)
	Style.rounded(self, Rect2(core - Vector2(22, 22), Vector2(44, 44)), Color("1d2331"), 6,
		GREEN if fled > 0.0 else CYAN, 2)
	draw_string(font, core + Vector2(-22, 5), "CPU", HORIZONTAL_ALIGNMENT_CENTER, 44, 12, TEXT)
	for i in range(total):
		_gate(font, i, floor_y)
	var chomper_center := _chomper_center()
	if fled <= 0.0:
		for k in range(max_strikes):
			var dot := chomper_center + Vector2((k - (max_strikes - 1) / 2.0) * 14.0, -62)
			if k < strikes:
				draw_circle(dot, 5, RED)
			else:
				draw_arc(dot, 5, 0, TAU, 12, Color(TEXT, 0.3), 1.5, true)
	if pop > 0.0:
		# Beside the robot, outlined, so it stays readable over the Chomper and the gates.
		var at := Vector2(robot_x() + 26, floor_y - 44 - 10 * (1.0 - pop))
		draw_string_outline(font, at, "CHOMP!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color(BG, pop))
		draw_string(font, at, "CHOMP!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(RED, pop))

func _gate(font: Font, i: int, floor_y: float) -> void:
	var x := gate_x(i)
	var top := floor_y - 66.0
	var open: float = opened[i]
	var current := i == index and open < 1.0
	var frame := GREEN if open >= 1.0 else GOLD if current else DIM
	if current:
		draw_rect(Rect2(x - 24, top - 8, 48, 74), Color(GOLD, 0.08 + 0.06 * sin(t * 4)))
	draw_rect(Rect2(x - 18, top, 5, 66), frame)
	draw_rect(Rect2(x + 13, top, 5, 66), frame)
	draw_rect(Rect2(x - 20, top - 5, 40, 6), frame)
	var door := 60.0 * (1.0 - open)
	if door > 0.5:
		Style.rounded(self, Rect2(x - 13, top + 1, 26, door), Color(frame.darkened(0.55), 0.95), 3)
		if door > 30.0:
			var lock := Vector2(x, top + door - 20)
			draw_arc(lock + Vector2(0, -4), 5, PI, TAU, 10, frame, 2, true)
			draw_rect(Rect2(lock + Vector2(-7, -4), Vector2(14, 11)), frame)
	draw_string(font, Vector2(x - 15, floor_y + 22), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 30, 14,
		Color(TEXT, 0.95 if current else 0.5))
	if stars.has(i):
		draw_string(font, Vector2(x - 30, top - 10), "★".repeat(stars[i]), HORIZONTAL_ALIGNMENT_CENTER, 60, 13, GOLD)
