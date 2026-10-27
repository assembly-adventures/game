extends RefCounted
## Level 3's custom-drawn pieces: the program listing and the Call Stack Tower, the stack drawn as
## floors (frames) hanging from the top of memory and growing down, with the robot riding sp like
## an elevator. Colours, fonts, and drawing helpers come from ui/style.gd.

const Style := preload("res://ui/style.gd")
const Characters := preload("res://ui/characters.gd")
const Assembly := preload("res://levels/level_2/assembly.gd")
const BG := Style.BG
const CYAN := Style.CYAN
const PURPLE := Style.PURPLE
const GOLD := Style.GOLD
const GREEN := Style.GREEN
const RED := Style.RED
const ORANGE := Style.ORANGE
const TEXT := Style.TEXT
const MONO := Style.MONO
const CODE_BASE := 0x100
const STACK_TOP := 0x7FF0
const JUNK := 0xDEADBEEF


## The program, one instruction every 4 bytes, labels on rows of their own. Lines a frame room's
## layout wrote are tinted and tagged, and while the frame is empty a dim row marks where they will
## go. The running line glows; in a Code Lawyer room any line can be clicked to accuse it. While a
## walkthrough waits for a move, its slot opens into a gold drop zone for a block from the bank.
class ListingView extends Control:
	signal line_clicked(address: int)
	signal move_dropped(option: int)  # A bank block landed in the drop zone.
	signal drag_ended(dropped: bool)  # A bank block was let go, in the drop zone or anywhere else.
	const TOP := 22.0
	const LEFT := 4.0
	var row_height := 17.0  # Shrinks (down to 12) so a long program fits the space it has.
	const TEXT_X := 64.0
	const DROP_ROWS := 2.4  # The drop zone's height, in lines.
	const SLOTS := {"prologue": "(prologue: nothing saved yet)", "epilogue": "(epilogue: nothing restored yet)",
		"moment": "(your move goes here)"}
	var rows: Array = []  # {"kind": "label"/"line"/"slot", "text", "address", "part", and a move's "moment"}
	var note := "one instruction every 4 bytes"  # Beside the CODE heading.
	var step := 0  # When the listing is where a numbered step happens, its number (drawn before the note).
	var running := -1
	var waiting := -1:  # The moment a walkthrough waits on, whose slot is the drop zone; -1 for none.
		set(value):
			waiting = value
			_fit()
			queue_redraw()
	var dragging := false  # A bank block is in the air: the drop zone lights up.
	var over := false  # It's over the drop zone.
	var nudge := 0.0:  # Flashes the drop zone, when a block is clicked instead of dragged.
		set(value):
			nudge = value
			queue_redraw()
	var drop_note := ""  # A smaller line in the drop zone, under what to do.
	var selectable := false
	var selected := -1
	var marks := {}  # Address → colour, for a verdict's lines.
	var hover := -1
	var win := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 160)

	func show_program(built: Dictionary) -> void:
		rows.clear()
		var at := {}
		for name in built.labels:
			var address := int(built.labels[name])
			if not at.has(address):
				at[address] = []
			at[address].append(str(name))
		var empty := {}  # Line index → the slots there: empty frame parts, and moves not made yet.
		for slot in built.get("slots", []):
			if not empty.has(int(slot.at)):
				empty[int(slot.at)] = []
			empty[int(slot.at)].append(slot)
		for k in range(built.lines.size() + 1):
			var address := CODE_BASE + 4 * k
			for name in at.get(address, []):
				rows.append({"kind": "label", "text": name + ":"})
			for slot in empty.get(k, []):
				rows.append({"kind": "slot", "text": SLOTS[str(slot.part)], "part": str(slot.part),
					"moment": int(slot.get("moment", -1))})
			if k < built.lines.size():
				rows.append({"kind": "line", "text": str(built.lines[k]), "address": address, "part": str(built.parts[k])})
		_fit()
		queue_redraw()

	func _fit() -> void:
		var weight := 0.0
		for i in range(rows.size()):
			weight += _weight(i)
		row_height = clampf((size.y - TOP - 8) / maxf(weight, 1.0), 12.0, 17.0)

	## A row's height in lines: labels and slots are a little shorter than code, and the drop zone taller.
	func _weight(i: int) -> float:
		if _is_drop(i):
			return DROP_ROWS
		return 1.0 if rows[i].kind == "line" else 0.85

	func _height(i: int) -> float:
		return row_height * _weight(i)

	func _is_drop(i: int) -> bool:
		return waiting >= 0 and rows[i].kind == "slot" and int(rows[i].get("moment", -1)) == waiting

	## Where a bank block can land: the slot the walk waits on (empty when it waits on none).
	func drop_rect() -> Rect2:
		for i in range(rows.size()):
			if _is_drop(i):
				return Rect2(Vector2(LEFT + 2, row_y(i) + 1), Vector2(size.x - LEFT - 4, _height(i) - 2))
		return Rect2()

	func row_y(i: int) -> float:
		var y := TOP
		for k in range(i):
			y += _height(k)
		return y

	func row_of(address: int) -> int:
		for i in range(rows.size()):
			if rows[i].kind == "line" and int(rows[i].address) == address:
				return i
		return -1

	func _row_at(y: float) -> int:
		for i in range(rows.size()):
			if y >= row_y(i) and y < row_y(i) + _height(i):
				return i
		return -1

	func _gui_input(event: InputEvent) -> void:
		if not selectable:
			return
		if event is InputEventMouseMotion:
			var row := _row_at(event.position.y)
			hover = row if row >= 0 and rows[row].kind == "line" else -1
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover >= 0 else Control.CURSOR_ARROW
			queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var row := _row_at(event.position.y)
			if row >= 0 and rows[row].kind == "line":
				line_clicked.emit(int(rows[row].address))
				accept_event()

	## A bank block lands only in the drop zone (or just around it), and only for the move it's for.
	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		var fits: bool = data is Dictionary and data.has("move") and int(data.moment) == waiting \
			and drop_rect().grow(6).has_point(at_position)
		if fits != over:
			over = fits
			queue_redraw()
		return fits

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		over = false
		move_dropped.emit(int(data.move))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and (hover >= 0 or over):
			hover = -1
			over = false
			queue_redraw()
		elif what == NOTIFICATION_RESIZED:
			_fit()
		elif what == NOTIFICATION_DRAG_BEGIN:
			var data = get_viewport().gui_get_drag_data()
			dragging = data is Dictionary and data.has("move")
			queue_redraw()
		elif what == NOTIFICATION_DRAG_END and dragging:
			dragging = false
			over = false
			queue_redraw()
			drag_ended.emit(get_viewport().gui_is_drag_successful())

	func _draw() -> void:
		var font := get_theme_default_font()
		draw_string(font, Vector2(LEFT, 14), "CODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT, 0.5))
		var note_x := LEFT + 42
		if step > 0:
			Style.draw_step_badge(self, Vector2(note_x + 9.5, 9), step)
			note_x += 26
		draw_string(font, Vector2(note_x, 14), note, HORIZONTAL_ALIGNMENT_LEFT, size.x - note_x - 4, 14 if step > 0 else 12,
			Color(TEXT, 0.92) if step > 0 else Color(TEXT, 0.3))
		Style.rounded(self, Rect2(Vector2(LEFT, TOP - 4), Vector2(size.x - LEFT, row_y(rows.size()) - TOP + 8)),
			Color(0, 0, 0, 0.25).lerp(Color(GREEN, 0.12), win), 8, Color(TEXT, 0.1).lerp(GREEN, win), 1)
		var tagged := {}
		var code_size := int(clampf(row_height - 4, 10, 13))
		var address_size := int(clampf(row_height - 6, 9, 11))
		var baseline := row_height * 0.76
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var y := row_y(i)
			if row.kind == "label":
				draw_string(MONO, Vector2(LEFT + 8, y + baseline * 0.85), row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, code_size,
					Color(PURPLE, 0.95))
				continue
			if row.kind == "slot":
				if _is_drop(i):
					_draw_drop(font, code_size)
					continue
				draw_string(font, Vector2(TEXT_X, y + baseline * 0.85), row.text, HORIZONTAL_ALIGNMENT_LEFT,
					size.x - TEXT_X - 8, address_size + 1, Color(CYAN, 0.6))
				continue
			var address := int(row.address)
			var band := Rect2(Vector2(LEFT + 2, y + 1), Vector2(size.x - LEFT - 4, row_height - 2))
			if marks.has(address):
				Style.rounded(self, band, Color(marks[address], 0.18), 5, marks[address], 2)
			elif address == selected:
				Style.rounded(self, band, Color(RED, 0.16), 5, RED, 2)
			elif address == running:
				Style.rounded(self, band, Color(GOLD, 0.22), 5)
			elif i == hover:
				Style.rounded(self, band, Color(TEXT, 0.06), 5, Color(TEXT, 0.25), 1)
			var generated: bool = row.part != "body"
			draw_string(MONO, Vector2(LEFT + 8, y + baseline), "0x%X" % address, HORIZONTAL_ALIGNMENT_LEFT, -1, address_size,
				GOLD if address == running else Color(TEXT, 0.35))
			draw_string(MONO, Vector2(TEXT_X, y + baseline), row.text, HORIZONTAL_ALIGNMENT_LEFT, size.x - TEXT_X - 70, code_size,
				CYAN.lightened(0.35) if generated else TEXT)
			if generated and not tagged.has(row.part):
				tagged[row.part] = true
				draw_string(font, Vector2(0, y + baseline), row.part, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10, address_size,
					Color(CYAN, 0.7))

	## The drop zone: a dashed gold outline while it waits, solid once a block is in the air, and
	## brightest with one over it.
	func _draw_drop(font: Font, font_size: int) -> void:
		var rect := drop_rect()
		var lit := 1.0 if over else 0.6 if dragging else nudge
		Style.rounded(self, rect, Color(GOLD, 0.08 + 0.22 * lit), 6, GOLD.lightened(0.3) if over else GOLD,
			3 if over else 2 if dragging else 0)
		if not dragging:
			Style.dashed_box(self, rect.grow(-1), GOLD)
		var text := "let go to write it here" if over else "drop it here" if dragging else "drag a block here"
		var baseline := rect.get_center().y + font_size * 0.35
		if not drop_note.is_empty():
			baseline -= font_size * 0.5
			draw_string(font, Vector2(rect.position.x, baseline + font_size), drop_note, HORIZONTAL_ALIGNMENT_CENTER,
				rect.size.x, font_size - 2, Color(GOLD, 0.75))
		draw_string(font, Vector2(rect.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size + 1,
			GOLD.lightened(0.3) if over else GOLD)


## The stack as a tower of floors hanging from the top of memory: the Chomper (the caller) at the
## ceiling, then one floor per call that is still running, each with its words (address, what is
## saved there, and its value). sp is the elevator: the robot stands beside the word it points
## to. In the finale the heap climbs from the bottom of the stack with the Chomper on top.
##
## Before a Frame Builder run the tower shows the frame being built instead ("design"): one slot
## per block, sp+0 at the bottom, with buttons to move a block up or down or take it out.
class TowerView extends Control:
	signal slot_action(index: int, action: String)
	const TOP := 22.0
	const LEFT := 40.0
	const DESIGN_ROW := 26.0
	var mode := "live"
	var caller := "the Chip Chomper"
	var floors: Array = []  # {"title", "words": [{"address", "label", "value"}], "current"}
	var sp := STACK_TOP
	var bottom := -1  # The lowest stack word, drawn in the finale so the heap shows.
	var heap := -1  # Words below this address are the heap's.
	var design: Array = []  # The frame being built: block names, sp+0 first.
	var design_title := ""
	var design_room := 0  # How many blocks the frame can hold.
	var read_back := {}  # Block name → true for blocks the code reads back rather than restores.
	var flashes := {}
	var hover := ""
	var robot
	var chomper
	var robot_y := -1.0
	var glide: Tween
	var message := ""
	var message_color := RED
	var message_alpha := 0.0
	var win := 0.0
	var idle := ""  # What to do, shown while no call is running.

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(300, 220)
		robot = Characters.Robot.new()
		add_child(robot)
		chomper = Characters.Chomper.new()
		chomper.visible = false
		add_child(chomper)

	## Shows the stack as a run left it: the open calls, the words between them, and sp.
	func show_live(open_floors: Array, stack_pointer: int, heap_address: int = -1) -> void:
		mode = "live"
		floors = open_floors
		sp = stack_pointer
		heap = heap_address
		_place_robot(0.12)
		queue_redraw()

	func show_design(frame: Array, title: String, room: int) -> void:
		mode = "design"
		design = frame
		design_title = title
		design_room = room
		_place_robot(0.15)
		queue_redraw()

	func flash(address: int) -> void:
		flashes[address] = 1.0

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
		Style.burst(self, Vector2(size.x / 2.0, size.y / 2.0), [GREEN, GOLD, CYAN, Color.WHITE], 30, 260.0, 180.0, 300.0,
			5.0, 0.9)

	## Every row the live tower draws, top to bottom: the caller, each floor's title and words, and
	## in the finale the free words and the heap below them.
	func _live_rows() -> Array:
		var rows: Array = [{"kind": "caller"}]
		var lowest := STACK_TOP
		for floor in floors:
			rows.append({"kind": "floor", "floor": floor})
			for word in floor.words:
				rows.append({"kind": "word", "word": word, "current": floor.current})
				lowest = mini(lowest, int(word.address))
		if bottom >= 0:
			var address := mini(lowest, sp) - 4
			while address >= bottom:
				rows.append({"kind": "heap" if heap >= 0 and address < heap else "free", "address": address})
				address -= 4
		return rows

	## A row's height in units: the stack words below the frames (free, or eaten by the heap) take
	## half a unit, so a deep finale still fits with its frames readable.
	func _weight(row: Dictionary) -> float:
		return 0.5 if str(row.kind) in ["free", "heap"] else 1.0

	## The height of one unit: every row fits the tower, but never too small to read or too big.
	func _unit(rows: Array) -> float:
		var total := 0.0
		for row in rows:
			total += _weight(row)
		return clampf((size.y - TOP - 6) / maxf(total, 1.0), 11.0, 22.0)

	## The top of each row, then the bottom of the last.
	func _tops(rows: Array, unit: float) -> Array:
		var tops: Array = []
		var y := TOP
		for row in rows:
			tops.append(y)
			y += unit * _weight(row)
		tops.append(y)
		return tops

	## The y of the row the robot should stand on: sp's word, or the floor it belongs to.
	func _sp_y() -> float:
		if mode == "design":
			return TOP + DESIGN_ROW * (2 + design.size()) - DESIGN_ROW / 2.0 if not design.is_empty() else TOP + DESIGN_ROW * 1.5
		var rows := _live_rows()
		var unit := _unit(rows)
		var tops := _tops(rows, unit)
		var target := -1
		for i in range(rows.size()):
			if rows[i].kind == "word" and int(rows[i].word.address) == sp:
				target = i
		if target < 0:
			# sp is at a floor with no words yet (or somewhere odd): stand on the deepest floor.
			for i in range(rows.size()):
				if rows[i].kind == "floor":
					target = i
		target = maxi(target, 0)
		return float(tops[target]) + unit * _weight(rows[target]) / 2.0

	func _place_robot(duration: float) -> void:
		var y := _sp_y()
		if robot_y < 0 or duration <= 0.0 or not is_inside_tree():
			robot_y = y
			return
		if glide:
			glide.kill()
		glide = create_tween().set_trans(Tween.TRANS_SINE)
		glide.tween_property(self, "robot_y", y, duration)

	func _process(delta: float) -> void:
		message_alpha = move_toward(message_alpha, 0.0, delta * 0.4)
		for key in flashes.keys():
			flashes[key] = move_toward(flashes[key], 0.0, delta * 1.8)
		var rows := _live_rows() if mode == "live" else []
		var h := _unit(rows) if mode == "live" else DESIGN_ROW
		robot.scale = Vector2.ONE * clampf(h / 30.0, 0.32, 0.5)
		robot.position = Vector2(12, robot_y + h * 0.42)
		robot.walking = glide != null and glide.is_running()
		chomper.visible = mode == "live" and bottom >= 0 and heap >= 0
		if chomper.visible:
			var tops := _tops(rows, h)
			var y := TOP
			for i in range(rows.size()):
				if rows[i].kind == "heap":
					y = tops[i]
					break
			chomper.scale = Vector2.ONE * 0.5
			chomper.position = Vector2(size.x / 2.0 + 40, y - 12)
			chomper.mouth = 0.8
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if mode != "design":
			return
		if event is InputEventMouseMotion:
			hover = _control_at(event.position)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var hit := _control_at(event.position)
			if not hit.is_empty():
				slot_action.emit(int(hit.get_slice(":", 0)), hit.get_slice(":", 1))
				accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hover = ""

	## The design row of block k (sp+4k), top to bottom from the highest offset.
	func _slot_rect(k: int) -> Rect2:
		var row := 2 + (design.size() - 1 - k)
		return Rect2(Vector2(LEFT + 6, TOP + DESIGN_ROW * row + 2), Vector2(size.x - LEFT - 10, DESIGN_ROW - 4))

	func _controls(k: int) -> Dictionary:
		var rect := _slot_rect(k)
		var y := rect.position.y + 3
		var right := rect.end.x - 4
		return {"remove": Rect2(Vector2(right - 20, y), Vector2(20, 16)),
			"down": Rect2(Vector2(right - 44, y), Vector2(20, 16)),
			"up": Rect2(Vector2(right - 68, y), Vector2(20, 16))}

	func _control_at(point: Vector2) -> String:
		for k in range(design.size()):
			var buttons := _controls(k)
			for action in buttons:
				if buttons[action].has_point(point) and _control_enabled(k, action):
					return "%d:%s" % [k, action]
		return ""

	func _control_enabled(k: int, action: String) -> bool:
		return action == "remove" or action == "up" and k < design.size() - 1 or action == "down" and k > 0

	func _draw() -> void:
		var font := get_theme_default_font()
		draw_string(font, Vector2(LEFT, 14), "STACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT, 0.5))
		draw_string(MONO, Vector2(LEFT + 48, 14), "top 0x%X · grows down" % STACK_TOP, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(TEXT, 0.3))
		draw_line(Vector2(LEFT, TOP - 2), Vector2(size.x - 4, TOP - 2), Color(TEXT, 0.35), 2)
		if mode == "design":
			_draw_design(font)
		else:
			_draw_live(font)
		if message_alpha > 0.0:
			var alpha := minf(1.0, message_alpha * 2.0)
			var lines := _wrap(font, message, size.x - 48, 14)  # The box's width less its margins.
			var height := 10.0 + 19.0 * lines.size()
			var box := Rect2(Vector2(12, size.y / 2.0 - height / 2.0), Vector2(size.x - 24, height))
			Style.rounded(self, box, Color(BG, 0.95 * alpha), 10, Color(message_color, alpha), 2)
			for i in range(lines.size()):
				draw_string(font, box.position + Vector2(12, 20 + 19 * i), lines[i], HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 24,
					14, Color(message_color, alpha))

	## Text broken into lines that fit the width; a newline always starts a new line.
	func _wrap(font: Font, text: String, width: float, font_size: int) -> Array:
		var lines: Array = []
		for paragraph in text.split("\n"):
			var current := ""
			for word in paragraph.split(" "):
				var attempt := word if current.is_empty() else current + " " + word
				if font.get_string_size(attempt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and not current.is_empty():
					lines.append(current)
					current = word
				else:
					current = attempt
			if not current.is_empty():
				lines.append(current)
		return lines

	func _draw_caller(font: Font, rect: Rect2) -> void:
		Style.rounded(self, rect, Color(PURPLE, 0.12), 5, Color(PURPLE, 0.45), 1)
		draw_string(font, rect.position + Vector2(8, rect.size.y / 2.0 + 5), caller, HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - 100, 12, Color(PURPLE, 0.95))
		draw_string(MONO, rect.position + Vector2(0, rect.size.y / 2.0 + 4), "ra = 0x400", HORIZONTAL_ALIGNMENT_RIGHT,
			rect.size.x - 8, 11, Color(PURPLE, 0.75))

	func _draw_live(font: Font) -> void:
		var rows := _live_rows()
		var h := _unit(rows)
		var tops := _tops(rows, h)
		var small := int(clampf(h * 0.58, 9.0, 12.0))
		for i in range(rows.size()):
			var row: Dictionary = rows[i]
			var rect := Rect2(Vector2(LEFT, float(tops[i]) + 1), Vector2(size.x - LEFT - 4, h * _weight(row) - 2))
			match str(row.kind):
				"caller":
					_draw_caller(font, rect)
				"floor":
					var current: bool = row.floor.current
					var color := GOLD if current else PURPLE
					Style.rounded(self, rect, Color(color, 0.16).lerp(Color(GREEN, 0.2), win), 5, Color(color, 0.7), 1)
					draw_string(MONO, rect.position + Vector2(8, h / 2.0 + small / 2.0 - 1), str(row.floor.title),
						HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16, small + 1, color.lightened(0.3))
					if row.floor.words.is_empty():
						draw_string(font, rect.position + Vector2(0, h / 2.0 + small / 2.0 - 1), "no frame", HORIZONTAL_ALIGNMENT_RIGHT,
							rect.size.x - 8, small, Color(TEXT, 0.4))
				"word":
					var word: Dictionary = row.word
					var address := int(word.address)
					var glow: float = flashes.get(address, 0.0)
					var value := int(word.value)
					var inner := Rect2(rect.position + Vector2(10, 0), rect.size - Vector2(10, 0))
					Style.rounded(self, inner, Color("161d2a").lerp(Color("2b3a52"), glow), 4,
						Color(CYAN, 0.8) if address == sp else Color(CYAN, 0.16), 2 if address == sp else 1)
					var base_y := inner.position.y + h / 2.0 + small / 2.0 - 2
					draw_string(MONO, Vector2(inner.position.x + 6, base_y), "0x%X" % address, HORIZONTAL_ALIGNMENT_LEFT, -1,
						small, Color(TEXT, 0.35))
					draw_string(MONO, Vector2(inner.position.x + 6 + small * 4.4, base_y), str(word.label),
						HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(CYAN, 0.85) if not str(word.label).is_empty() else Color(TEXT, 0.3))
					draw_string(MONO, Vector2(inner.position.x, base_y), Assembly.word_text(value), HORIZONTAL_ALIGNMENT_RIGHT,
						inner.size.x - 8, small + 1, Color(TEXT, 0.3) if value == JUNK else TEXT.lerp(Color.WHITE, glow))
				"free":
					var middle := rect.position.y + rect.size.y / 2.0
					draw_dashed_line(Vector2(LEFT + 12, middle), Vector2(rect.end.x - 4, middle), Color(TEXT, 0.12), 1.0, 4.0)
				"heap":
					Style.rounded(self, Rect2(rect.position + Vector2(10, 0), rect.size - Vector2(10, 0)), Color(ORANGE, 0.22), 3,
						Color(ORANGE, 0.5), 1)
		# sp, the elevator, on the left beside its word.
		var y := _sp_y()
		draw_string(MONO, Vector2(23, y + 4), "sp", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)
		if floors.is_empty() and not idle.is_empty():
			var lines := _wrap(font, idle, size.x - LEFT - 40, 14)
			for i in range(lines.size()):
				draw_string(font, Vector2(LEFT, size.y * 0.42 + 20 * i), lines[i], HORIZONTAL_ALIGNMENT_CENTER, size.x - LEFT - 4,
					14, Color(TEXT, 0.4))
		if bottom >= 0 and heap >= 0:
			var free := 0
			for row in rows:
				free += int(row.kind == "free")
			draw_string(MONO, Vector2(0, size.y - 4), "%d free words above the heap" % free, HORIZONTAL_ALIGNMENT_RIGHT,
				size.x - 6, 11, ORANGE if free < 4 else Color(TEXT, 0.45))

	func _draw_design(font: Font) -> void:
		_draw_caller(font, Rect2(Vector2(LEFT, TOP + 2), Vector2(size.x - LEFT - 4, DESIGN_ROW - 4)))
		var header := Rect2(Vector2(LEFT, TOP + DESIGN_ROW + 2), Vector2(size.x - LEFT - 4, DESIGN_ROW - 4))
		Style.rounded(self, header, Color(GOLD, 0.14), 5, Color(GOLD, 0.6), 1)
		draw_string(MONO, header.position + Vector2(8, 16), design_title, HORIZONTAL_ALIGNMENT_LEFT, header.size.x - 120, 12,
			GOLD.lightened(0.3))
		draw_string(MONO, header.position + Vector2(0, 16), "%d bytes" % (4 * design.size()) if not design.is_empty()
			else "no frame", HORIZONTAL_ALIGNMENT_RIGHT, header.size.x - 8, 11, Color(TEXT, 0.55))
		for k in range(design.size()):
			var rect := _slot_rect(k)
			var name := str(design[k])
			var back: bool = read_back.has(name)
			var color := PURPLE if back else CYAN
			Style.rounded(self, rect, Color("161d2a"), 5, Color(color, 0.6), 1)
			draw_string(MONO, rect.position + Vector2(8, 15), "sp+%d" % (4 * k), HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(TEXT, 0.45))
			draw_string(MONO, rect.position + Vector2(54, 15), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color.lightened(0.25))
			draw_string(font, rect.position + Vector2(92, 15), "read back" if back else "saved, restored", HORIZONTAL_ALIGNMENT_LEFT,
				rect.size.x - 170, 11, Color(TEXT, 0.45))
			var buttons := _controls(k)
			for action in buttons:
				var enabled := _control_enabled(k, action)
				var lit := hover == "%d:%s" % [k, action]
				var button: Rect2 = buttons[action]
				Style.rounded(self, button, Color(TEXT, 0.12 if lit else 0.05), 4, Color(TEXT, 0.35 if enabled else 0.1), 1)
				var glyph: String = {"up": "▲", "down": "▼", "remove": "×"}[action]
				draw_string(font, button.position + Vector2(0, 13), glyph, HORIZONTAL_ALIGNMENT_CENTER, button.size.x, 11,
					Color(TEXT, 0.85 if enabled else 0.2) if action != "remove" else Color(RED, 0.9 if enabled else 0.2))
		var spare := Rect2(Vector2(LEFT + 6, TOP + DESIGN_ROW * (2 + design.size()) + 2), Vector2(size.x - LEFT - 10, DESIGN_ROW - 4))
		if design.size() < design_room:
			draw_dashed_line(spare.position, Vector2(spare.end.x, spare.position.y), Color(GOLD, 0.35), 1.0, 5.0)
			draw_string(font, spare.position + Vector2(8, 16), "click a register on the right to save it here",
				HORIZONTAL_ALIGNMENT_LEFT, spare.size.x - 16, 12, Color(GOLD, 0.7))
		var y := _sp_y()
		draw_string(MONO, Vector2(23, y + 4), "sp", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)
