extends RefCounted
## Level 2's code rooms, drawn: the program as words of code memory (one instruction every 4 bytes
## from 0x100) with the robot walking it as the PC, the data and stack words beside it, and the
## room's test cards. Colours, fonts, and drawing helpers come from ui/style.gd.

const Style := preload("res://ui/style.gd")
const Characters := preload("res://ui/characters.gd")
const Assembly := preload("res://levels/level_2/assembly.gd")
const BG := Style.BG
const CYAN := Style.CYAN
const PURPLE := Style.PURPLE
const GOLD := Style.GOLD
const GREEN := Style.GREEN
const RED := Style.RED
const TEXT := Style.TEXT
const MONO := Style.MONO
const CODE_BASE := Assembly.CODE_BASE
const EXIT := Assembly.EXIT
const JUNK := Assembly.JUNK


## The program on the left, memory on the right. Labels get rows of their own and every instruction
## shows its address. Blanks are slots to click. While a test runs, the robot stands beside the
## instruction the PC points to, and a taken branch or a jump draws an arc to where it lands.
class CodeView extends Control:
	signal blank_clicked(index: int)  ## -1 for a click anywhere else.
	const TOP := 20.0
	const ROW := 18.0
	const LABEL_ROW := 15.0
	const LEFT := 44.0  # The code panel's left edge; the robot and the jump arcs use the margin.
	const SLOT := 106.0  # Where an instruction (or a blank's slot) starts.
	const WORD := 28.0  # A memory word's row.
	var rows: Array = []  # {"kind": "label"/"line"/"blank", "text", "address", "blank"}
	var choices: Array = []
	var end := CODE_BASE  # Just past the last instruction: running off the end finishes the program.
	var returns := false  # Whether a jalr can return to main's caller, so the OS gets a row.
	var ends := true  # Whether the program can finish by running off its end, so the end gets a row.
	var memory_rows: Array = []  # {"address", "label", "stack"}
	var memory: Dictionary = {}
	var stack_top := -1
	var sp := -1
	var flashes: Dictionary = {}
	var running_row := -1
	var open_blank := -1
	var editable := true
	var robot
	var robot_y := 0.0
	var glide: Tween
	var jumps: Array = []
	var hover := -1
	var message := ""
	var message_color := RED
	var message_alpha := 0.0
	var win := 0.0

	func _init(room: Dictionary) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var address := CODE_BASE
		for entry in room.code:
			if entry.has("label"):
				rows.append({"kind": "label", "text": str(entry.label) + ":"})
				continue
			if entry.has("line"):
				rows.append({"kind": "line", "text": str(entry.line), "address": address})
			else:
				rows.append({"kind": "blank", "text": "", "address": address, "blank": choices.size()})
				choices.append("")
			for line in entry.get("blank", [entry.get("line", "")]):
				returns = returns or str(line).begins_with("jalr")
			address += 4
		end = address
		# A program that must return to the OS (main's caller) never ends by running off its last line.
		for test in room.tests:
			ends = ends and not test.expect.get("returned", false)
		if room.has("data"):
			var at := int(room.data.base)
			for block in room.data.blocks:
				for k in range(block.words.size()):
					var name := str(block.label) if block.words.size() == 1 else "%s[%d]" % [block.label, k]
					memory_rows.append({"address": at, "label": name, "stack": false})
					at += 4
		if room.has("stack"):
			stack_top = int(room.stack.top)
			for k in range(1, int(room.stack.words) + 1):
				memory_rows.append({"address": stack_top - 4 * k, "label": "", "stack": true})
		var memory_height := TOP + WORD * memory_rows.size() + (22.0 if stack_top >= 0 else 0.0)
		custom_minimum_size = Vector2(0, maxf(_os_y() + (ROW if returns else 0.0), memory_height) + 4)
		robot = Characters.Robot.new()
		add_child(robot)

	func code_width() -> float:
		return minf(size.x, 560.0) if memory_rows.is_empty() else size.x * 0.58

	func row_y(i: int) -> float:
		var y := TOP
		for k in range(i):
			y += LABEL_ROW if rows[k].kind == "label" else ROW
		return y

	func _end_y() -> float:
		return row_y(rows.size()) + 4

	func _os_y() -> float:
		return _end_y() + (ROW + 2 if ends else 0.0)

	## The row of the instruction at `address`, or -1.
	func row_of(address: int) -> int:
		for i in range(rows.size()):
			if rows[i].kind != "label" and rows[i].address == address:
				return i
		return -1

	## Where the robot stands for `address`: beside its instruction, on the OS row when main returns,
	## or on the end row when the program runs off its last line.
	func address_y(address: int) -> float:
		var row := row_of(address)
		if row >= 0:
			return row_y(row) + ROW / 2.0
		if address == EXIT and returns:
			return _os_y() + ROW / 2.0
		return _end_y() + ROW / 2.0

	func blank_rect(blank: int) -> Rect2:
		for i in range(rows.size()):
			if rows[i].kind == "blank" and int(rows[i].blank) == blank:
				return Rect2(Vector2(SLOT - 6, row_y(i) + 1), Vector2(code_width() - SLOT + 2, ROW - 2))
		return Rect2()

	func _row_at(point: Vector2) -> int:
		if point.x < LEFT or point.x > code_width():
			return -1
		for i in range(rows.size()):
			var height := LABEL_ROW if rows[i].kind == "label" else ROW
			if point.y >= row_y(i) and point.y < row_y(i) + height:
				return i
		return -1

	func show_memory(values: Dictionary, stack_pointer: int) -> void:
		memory = values.duplicate()
		sp = stack_pointer

	func set_word(address: int, value: int) -> void:
		memory[address] = value
		flashes[address] = 1.0

	func flash_word(address: int) -> void:
		flashes[address] = 0.6

	## Moves the robot beside the instruction at `address`, gliding there over `duration`.
	func walk_to(address: int, duration: float = 0.0) -> void:
		if glide:
			glide.kill()
		if duration <= 0.0:
			robot_y = address_y(address)
			return
		glide = create_tween().set_trans(Tween.TRANS_SINE)
		glide.tween_property(self, "robot_y", address_y(address), duration)

	## A taken branch or a jump: an arc in the margin from one instruction to where it lands.
	func jump(from: int, to: int, color: Color) -> void:
		var arc := {"from": address_y(from), "to": address_y(to), "color": color, "alpha": 1.0}
		jumps.append(arc)
		var tween := create_tween()
		tween.tween_method(func(alpha: float): arc.alpha = alpha, 1.0, 0.0, 0.9)
		tween.tween_callback(func(): jumps.erase(arc))

	## Clears what the last run left on the code: the highlight, the arcs, and the message.
	func reset_run() -> void:
		running_row = -1
		jumps.clear()
		message_alpha = 0.0
		win = 0.0

	func flash_message(text: String, color: Color) -> void:
		message = text
		message_color = color
		message_alpha = 1.6

	func fault(text: String) -> void:
		flash_message(text, RED)
		robot.hurt = 1.0
		create_tween().tween_property(robot, "hurt", 0.0, 1.2)

	func celebrate() -> void:
		var tween := create_tween()
		tween.tween_property(self, "win", 1.0, 0.2)
		tween.tween_property(self, "win", 0.5, 0.6)
		robot.cheer = 1.5
		Style.burst(self, Vector2(code_width() / 2.0, size.y / 2.0), [GREEN, GOLD, CYAN, Color.WHITE], 30, 260.0, 180.0,
			300.0, 5.0, 0.9)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var row := _row_at(event.position)
			hover = row if editable and row >= 0 and rows[row].kind == "blank" else -1
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover >= 0 else Control.CURSOR_ARROW
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var row := _row_at(event.position)
			if editable:
				blank_clicked.emit(int(rows[row].blank) if row >= 0 and rows[row].kind == "blank" else -1)
				accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hover = -1

	func _process(delta: float) -> void:
		message_alpha = move_toward(message_alpha, 0.0, delta * 0.4)
		for key in flashes.keys():
			flashes[key] = move_toward(flashes[key], 0.0, delta * 1.6)
		robot.scale = Vector2.ONE * 0.42
		robot.position = Vector2(LEFT - 24, robot_y + 8)
		robot.walking = glide != null and glide.is_running()
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var width := code_width()
		draw_string(font, Vector2(LEFT, 14), "CODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT, 0.5))
		draw_string(font, Vector2(LEFT + 42, 14), "one instruction every 4 bytes", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(TEXT, 0.3))
		Style.rounded(self, Rect2(Vector2(LEFT, TOP - 4), Vector2(width - LEFT, row_y(rows.size()) - TOP + 8)),
			Color(0, 0, 0, 0.25).lerp(Color(GREEN, 0.12), win), 8, Color(TEXT, 0.1).lerp(GREEN, win), 1)
		for i in range(rows.size()):
			_row(font, i, width)
		if ends:
			var y := _end_y()
			draw_string(MONO, Vector2(LEFT + 8, y + 14), "0x%X" % end, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT, 0.25))
			draw_string(font, Vector2(SLOT, y + 14), "end of the program", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(TEXT, 0.3))
		if returns:
			var y := _os_y()
			Style.rounded(self, Rect2(Vector2(LEFT, y), Vector2(width - LEFT, ROW)), Color(PURPLE, 0.1), 6,
				Color(PURPLE, 0.35), 1)
			draw_string(MONO, Vector2(LEFT + 8, y + 14), "0x%X" % EXIT, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(PURPLE, 0.8))
			draw_string(font, Vector2(SLOT, y + 14), "the OS, main's caller (ra starts here)", HORIZONTAL_ALIGNMENT_LEFT,
				width - SLOT - 8, 12, Color(PURPLE, 0.85))
		for arc in jumps:
			var points := PackedVector2Array()
			for k in range(15):
				var along := k / 14.0
				points.append(Vector2(LEFT - 2 - sin(along * PI) * 12.0, lerpf(arc.from, arc.to, along)))
			draw_polyline(points, Color(arc.color, arc.alpha), 3, true)
			var tip: Vector2 = points[points.size() - 1]
			draw_colored_polygon(PackedVector2Array([tip + Vector2(7, 0), tip + Vector2(-1, -5), tip + Vector2(-1, 5)]),
				Color(arc.color, arc.alpha))
		if not memory_rows.is_empty():
			_memory(font, width + 18)
		if message_alpha > 0.0:
			var alpha := minf(1.0, message_alpha * 2.0)
			var text_width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var box := Rect2(Vector2((width + LEFT - text_width) / 2.0 - 14, size.y / 2.0 - 16), Vector2(text_width + 28, 32))
			box.position.x = clampf(box.position.x, 0.0, maxf(size.x - box.size.x, 0.0))
			Style.rounded(self, box, Color(BG, 0.95 * alpha), 10, Color(message_color, alpha), 2)
			draw_string(font, box.position + Vector2(14, 22), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(message_color, alpha))

	func _row(font: Font, i: int, width: float) -> void:
		var row: Dictionary = rows[i]
		var y := row_y(i)
		if row.kind == "label":
			draw_string(MONO, Vector2(LEFT + 8, y + 12), row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(PURPLE, 0.95))
			return
		var here := running_row == i
		if here:
			Style.rounded(self, Rect2(Vector2(LEFT + 2, y + 1), Vector2(width - LEFT - 4, ROW - 2)), Color(GOLD, 0.2), 5)
		draw_string(MONO, Vector2(LEFT + 8, y + 14), "0x%X" % int(row.address), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			GOLD if here else Color(TEXT, 0.35))
		if row.kind == "line":
			draw_string(MONO, Vector2(SLOT, y + 14), row.text, HORIZONTAL_ALIGNMENT_LEFT, width - SLOT - 6, 14, TEXT)
			return
		var chosen: String = choices[int(row.blank)]
		var slot := Rect2(Vector2(SLOT - 6, y + 1), Vector2(width - SLOT + 2, ROW - 2))
		var lit := hover == i or open_blank == int(row.blank)
		var color := GOLD if chosen.is_empty() else CYAN
		Style.rounded(self, slot, Color(color, 0.16 if lit else 0.07), 5, Color(color, 1.0 if lit else 0.55), 1)
		if chosen.is_empty():
			draw_string(font, slot.position + Vector2(8, 13), "pick a line", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(GOLD, 0.9))
		else:
			draw_string(MONO, slot.position + Vector2(6, 13), chosen, HORIZONTAL_ALIGNMENT_LEFT, slot.size.x - 24, 14,
				CYAN.lightened(0.45))
		# A small caret: the slot opens a list.
		var caret := slot.position + Vector2(slot.size.x - 12, slot.size.y / 2.0)
		draw_colored_polygon(PackedVector2Array([caret + Vector2(-4, -2), caret + Vector2(4, -2), caret + Vector2(0, 3)]),
			Color(color, 0.8))

	## The data words and the stack, each with its address, and sp pointing at its word.
	func _memory(font: Font, left: float) -> void:
		draw_string(font, Vector2(left, 14), "MEMORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT, 0.5))
		var y := TOP - 4
		var stacked := false
		var right := size.x - 52
		for row in memory_rows:
			if row.stack and not stacked:
				stacked = true
				y += 4
				draw_string(font, Vector2(left, y + 11), "STACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(TEXT, 0.45))
				if sp >= stack_top:
					draw_string(MONO, Vector2(left + 48, y + 11), "sp = 0x%X%s" % [sp, " (the top)" if sp == stack_top else ""],
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, CYAN if sp == stack_top else RED)
				y += 18
			var address: int = row.address
			var value: int = memory.get(address, 0)
			var rect := Rect2(Vector2(left, y), Vector2(right - left, WORD - 4))
			var glow: float = flashes.get(address, 0.0)
			var pointed: bool = row.stack and address == sp
			Style.rounded(self, rect, Color("161d2a").lerp(Color("2b3a52"), glow), 6,
				Color(CYAN, 0.85) if pointed else Color(CYAN, 0.2), 2 if pointed else 1)
			if row.label.is_empty():
				draw_string(MONO, rect.position + Vector2(8, 17), "0x%X" % address, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
					Color(TEXT, 0.45))
			else:
				draw_string(MONO, rect.position + Vector2(8, 17), row.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
					Color(CYAN, 0.8))
				var label_width := MONO.get_string_size(row.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				draw_string(MONO, rect.position + Vector2(14 + label_width, 16), "0x%X" % address, HORIZONTAL_ALIGNMENT_LEFT,
					-1, 10, Color(TEXT, 0.3))
			draw_string(MONO, rect.position + Vector2(0, 18), Assembly.word_text(value), HORIZONTAL_ALIGNMENT_RIGHT,
				rect.size.x - 8, 15, Color(TEXT, 0.3) if value == JUNK else TEXT.lerp(Color.WHITE, glow))
			if row.stack and sp >= 0 and address >= sp and address - sp < 64:
				var offset := address - sp
				draw_string(MONO, Vector2(rect.end.x + 6, y + 17), "sp" if offset == 0 else "sp+%d" % offset,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN if offset == 0 else Color(CYAN, 0.55))
			y += WORD


## The room's tests: each one's inputs and what it expects, then how the last run went.
class TestCards extends Control:
	const CARD := 38.0
	var lines: Array = []  # One description per test.
	var results: Array = []  # "" until run, then "pass" or "fail".
	var details: Array = []
	var running := -1
	var shake := 0.0
	var t := 0.0

	func _init(descriptions: Array) -> void:
		lines = descriptions
		for k in range(lines.size()):
			results.append("")
			details.append("")
		custom_minimum_size = Vector2(0, 20 + (CARD + 4) * lines.size())
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func clear() -> void:
		running = -1
		for k in range(results.size()):
			results[k] = ""
			details[k] = ""

	func mark(k: int, passed: bool, detail: String) -> void:
		results[k] = "pass" if passed else "fail"
		details[k] = detail

	func _process(delta: float) -> void:
		t += delta
		shake = move_toward(shake, 0.0, delta * 16.0)
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var jitter := sin(t * 50.0) * shake
		draw_string(font, Vector2(2, 14), "TESTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT, 0.5))
		draw_string(font, Vector2(48, 14), "the program must pass every one", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(TEXT, 0.3))
		for k in range(lines.size()):
			var rect := Rect2(Vector2(jitter, 20 + (CARD + 4) * k), Vector2(size.x, CARD))
			var color := GREEN if results[k] == "pass" else RED if results[k] == "fail" else GOLD if running == k \
				else Color(TEXT, 0.3)
			Style.rounded(self, rect, Color(color, 0.08), 8, color, 2 if running == k else 1)
			var badge := rect.position + Vector2(16, CARD / 2.0)
			draw_circle(badge, 10, Color(color, 0.18))
			if results[k] == "pass":
				draw_polyline(PackedVector2Array([badge + Vector2(-5, 0), badge + Vector2(-1, 4), badge + Vector2(5, -4)]),
					color, 2.5, true)
			elif results[k] == "fail":
				draw_line(badge + Vector2(-4, -4), badge + Vector2(4, 4), color, 2.5, true)
				draw_line(badge + Vector2(-4, 4), badge + Vector2(4, -4), color, 2.5, true)
			else:
				draw_string(font, badge + Vector2(-4, 5), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
			draw_string(MONO, rect.position + Vector2(34, 15), lines[k], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40, 12,
				TEXT)
			var detail: String = "running…" if running == k else details[k]
			if not detail.is_empty():
				draw_string(MONO, rect.position + Vector2(34, 31), detail, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 40, 11,
					color.lightened(0.25))
