extends RefCounted
## Level 1's custom-drawn pieces: the register and the move tray. (The corridor of gates that
## every gate level shares is ui/corridor.gd.)
## Colours, fonts, and drawing helpers come from ui/style.gd so every screen matches.

const Style := preload("res://ui/style.gd")
const Registers := preload("res://ui/registers.gd")
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
		draw_string(MONO, Vector2(0, live_y + 8), Registers.abi(register), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, CYAN)
		draw_string(font, Vector2(0, live_y + 28), "%s · %d-bit" % [register, bits], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(TEXT, 0.45))
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
			draw_string(MONO, rect.position + Vector2(10, 21), "%s = %d" % [Registers.abi(reg), extras[reg]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
			draw_string(MONO, rect.position + Vector2(0, 20), reg, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8, 10,
				Color(TEXT, 0.4))
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
