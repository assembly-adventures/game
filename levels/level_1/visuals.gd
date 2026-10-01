extends RefCounted
## Level 1's custom-drawn pieces: the corridor of gates, the register, and the move tray.
## Colours, fonts, and drawing helpers come from ui/style.gd so every screen matches.

const Style := preload("res://ui/style.gd")
const Characters := preload("res://ui/characters.gd")
const CircuitBackdrop := preload("res://ui/circuit_backdrop.gd")
const BG := Style.BG
const CYAN := Style.CYAN
const PURPLE := Style.PURPLE
const GOLD := Style.GOLD
const GREEN := Style.GREEN
const RED := Style.RED
const ORANGE := Style.ORANGE
const DIM := Style.DIM
const SOCKET := Style.SOCKET
const TEXT := Style.TEXT
const MONO := Style.MONO


## The level as a corridor of gates. The robot walks on as each gate opens, and the Chip
## Chomper trails behind, one step closer for each strike. On the last strike it bites the
## robot and drags it back a gate.
class Corridor extends Control:
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
		custom_minimum_size = Vector2(0, 132)
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
		get_tree().create_timer(0.9).timeout.connect(func():
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


## The register as a row of bulbs under the target pattern. A column's connector turns
## green when that bit matches. Changes animate the way each instruction works: shifts
## slide, adds ripple a carry from the right, and logic operations sweep across.
class RegisterStrip extends Control:
	const LEFT := 104.0
	const TARGET_Y := 22.0
	const LIVE_Y := 80.0
	const SPACING := 50.0
	var bits := 8
	var signed_view := false
	var hex_view := false
	var register := "x5"
	var value := 0
	var from_value := 0
	var target := 0
	var style := ""
	var amount := 0
	var progress := 1.0:
		set(new_progress):
			progress = new_progress
			queue_redraw()
	var extras: Dictionary = {}
	var message := ""
	var message_color := RED
	var message_alpha := 0.0
	var win := 0.0
	var font: Font
	var anim: Tween

	func _init(width: int, signed_numbers: bool, hex_numbers: bool, register_name: String) -> void:
		bits = width
		signed_view = signed_numbers
		hex_view = hex_numbers
		register = register_name
		custom_minimum_size = Vector2(LEFT + bits * SPACING + 16 + 290, 134)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_value(new_value: int) -> void:
		value = new_value
		from_value = new_value
		style = ""
		progress = 1.0

	func animate_to(new_value: int, how: String, shift: int = 0) -> void:
		from_value = value
		value = new_value
		style = how
		amount = shift
		progress = 0.0
		if anim:
			anim.kill()
		anim = create_tween()
		anim.tween_property(self, "progress", 1.0, 0.32)
		anim.finished.connect(_sparkle.bind(from_value, new_value))

	func _sparkle(before: int, after: int) -> void:
		for i in range(bits):
			if _bit(after, i) and not _bit(before, i):
				Style.burst(self, Vector2(slot_x(i), LIVE_Y), [GOLD, Color.WHITE], 8, 130.0, 150.0, 300.0, 4.0, 0.45)

	func flash_message(text: String, color: Color) -> void:
		message = text
		message_color = color
		message_alpha = 1.0

	func celebrate() -> void:
		var tween := create_tween()
		tween.tween_property(self, "win", 1.0, 0.2)
		tween.tween_property(self, "win", 0.4, 0.6)
		for i in range(bits):
			if _bit(value, i):
				Style.burst(self, Vector2(slot_x(i), LIVE_Y), [GREEN, GOLD, Color.WHITE], 10, 210.0, 110.0, 400.0, 5.0, 0.8)

	func _process(delta: float) -> void:
		message_alpha = move_toward(message_alpha, 0.0, delta * 0.5)
		queue_redraw()

	## Slot centres count from the most significant bit; indices past either end continue the row.
	func slot_x(i: int) -> float:
		return LEFT + SPACING * (i + 0.5) + (16.0 if i * 2 >= bits else 0.0)

	func _bit(number: int, i: int) -> bool:
		return (number >> (bits - 1 - i)) & 1 == 1

	func _shown(number: int) -> String:
		if hex_view:
			return "0x%02X" % number
		return str(number - (1 << bits) if signed_view and _bit(number, 0) else number)

	func _draw() -> void:
		font = get_theme_default_font()
		var target_y := TARGET_Y
		var live_y := LIVE_Y
		draw_string(font, Vector2(0, target_y + 5), "TARGET", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(GOLD, 0.9))
		draw_string(MONO, Vector2(0, live_y + 8), register, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, CYAN)
		draw_string(font, Vector2(0, live_y + 28), "%d-bit" % bits, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT, 0.45))
		if win > 0.0:
			Style.rounded(self, Rect2(LEFT - 8, 2, slot_x(bits - 1) - LEFT + 42, 108), Color(GREEN, 0.08 * win), 14,
				Color(GREEN, win), 2)
		for i in range(bits):
			var x := slot_x(i)
			var want := _bit(target, i)
			if want:
				draw_circle(Vector2(x, target_y), 15, Color(GOLD, 0.15))
				draw_circle(Vector2(x, target_y), 11, Color(GOLD, 0.9))
			else:
				draw_arc(Vector2(x, target_y), 11, 0, TAU, 24, Color(TEXT, 0.25), 2, true)
			var matched := progress >= 1.0 and want == _bit(value, i)
			draw_line(Vector2(x, target_y + 14), Vector2(x, live_y - 24), Color(GREEN, 0.9) if matched else Color(TEXT, 0.12),
				3.0 if matched else 2.0)
			_socket(Vector2(x, live_y))
			var place := str(1 << (bits - 1 - i))
			if i == 0 and signed_view:
				place = "-" + place
			draw_string(MONO, Vector2(x - 25, live_y + 46), place, HORIZONTAL_ALIGNMENT_CENTER, 50, 13,
				RED if place.begins_with("-") else Color(TEXT, 0.6))
		_draw_live(live_y)
		var readout := slot_x(bits - 1) + 48
		draw_string(MONO, Vector2(readout, target_y + 8), "= " + _shown(target), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GOLD)
		draw_string(MONO, Vector2(readout, live_y + 11), "= " + _shown(value), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, TEXT)
		var other := str(value) if hex_view else "0x%02X" % value
		draw_string(MONO, Vector2(readout, live_y + 34), other, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(TEXT, 0.5))
		var chip_y := 50.0
		for reg in extras:
			var rect := Rect2(Vector2(readout + 150, chip_y), Vector2(120, 30))
			Style.rounded(self, rect, Color(CYAN, 0.12), 8, Color(CYAN, 0.6), 1)
			draw_string(MONO, rect.position + Vector2(10, 21), "%s = %d" % [reg, extras[reg]], HORIZONTAL_ALIGNMENT_LEFT,
				-1, 16, TEXT)
			chip_y += 36.0
		if message_alpha > 0.0:
			draw_string(font, Vector2(readout, live_y - 30), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
				Color(message_color, message_alpha))

	func _draw_live(y: float) -> void:
		match style:
			"slide":
				var landed := {}
				for i in range(bits):
					if _bit(from_value, i):
						var j := i - amount
						var inside := j >= 0 and j < bits
						_lit(Vector2(lerpf(slot_x(i), slot_x(j), progress), y), 1.0 if inside else 1.0 - progress)
						if inside:
							landed[j] = true
				for j in range(bits):
					if _bit(value, j) and not landed.has(j):
						_lit(Vector2(slot_x(j), y), progress)
			"ripple", "sweep":
				var front := progress * bits
				for i in range(bits):
					var order := bits - 1 - i if style == "ripple" else i
					var settled := front > order + 0.5
					if _bit(value if settled else from_value, i):
						_lit(Vector2(slot_x(i), y), 1.0)
				if progress < 1.0:
					var ends := [slot_x(bits - 1) + 25, slot_x(0) - 25]
					if style == "sweep":
						ends.reverse()
					var x: float = lerpf(ends[0], ends[1], progress)
					draw_circle(Vector2(x, y + 28), 9, Color(GOLD, 0.25))
					draw_circle(Vector2(x, y + 28), 4, GOLD)
			_:
				for i in range(bits):
					if _bit(value, i):
						_lit(Vector2(slot_x(i), y), 1.0)

	func _socket(center: Vector2) -> void:
		draw_rect(Rect2(center.x - 8, center.y + 17, 16, 7), Color("7d8494"))
		draw_circle(center, 18, SOCKET)
		draw_arc(center, 18, 0, TAU, 32, Color(1, 1, 1, 0.15), 2, true)
		draw_string(MONO, center + Vector2(-10, 7), "0", HORIZONTAL_ALIGNMENT_CENTER, 20, 18, Color(TEXT, 0.35))

	func _lit(center: Vector2, alpha: float) -> void:
		if alpha <= 0.0:
			return
		var glow := GOLD.lerp(GREEN, win)
		for k in range(3):
			draw_circle(center, 20 + k * 6, Color(glow, 0.12 * alpha * (3 - k) / 3.0))
		draw_circle(center, 18, Color(glow, alpha))
		draw_arc(center + Vector2(-6, -6), 8, PI, PI * 1.5, 8, Color(1, 1, 1, 0.45 * alpha), 2, true)
		draw_string(MONO, center + Vector2(-10, 7), "1", HORIZONTAL_ALIGNMENT_CENTER, 20, 18, Color(BG, alpha))


## The instructions pressed so far, one slot per allowed move.
class MoveTray extends Control:
	var limit := 3
	var used: Array = []
	var shake := 0.0
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 42)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_moves(lines: Array, max_moves: int) -> void:
		used = lines
		limit = max_moves
		queue_redraw()

	func _process(delta: float) -> void:
		t += delta
		if shake > 0.0:
			shake = move_toward(shake, 0.0, delta * 20)
			queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var jitter := sin(t * 50) * shake
		draw_string(font, Vector2(0, 26), "MOVES", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(TEXT, 0.6))
		var slot := 168.0
		for i in range(limit):
			var rect := Rect2(Vector2(64 + i * (slot + 8) + jitter, 4), Vector2(slot, 32))
			if i < used.size():
				Style.rounded(self, rect, Color(CYAN, 0.16), 8, Color(CYAN, 0.7), 1)
				draw_string(MONO, rect.position + Vector2(10, 21), "%d  %s" % [i + 1, used[i]], HORIZONTAL_ALIGNMENT_LEFT,
					slot - 14, 13, TEXT)
			else:
				Style.rounded(self, rect, Color(0, 0, 0, 0.25), 8, Color(TEXT, 0.15), 1)
				draw_string(font, rect.position + Vector2(10, 21), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(TEXT, 0.3))
		var left := limit - used.size()
		draw_string(font, Vector2(64 + limit * (slot + 8) + jitter, 26), "%d left" % left, HORIZONTAL_ALIGNMENT_LEFT, -1,
			14, GOLD if left > 0 else RED)
