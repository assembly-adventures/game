extends RefCounted
## Level 2's custom-drawn pieces: the room of memory the robot walks through, the register chips,
## and the program listing. Colours, fonts, and drawing helpers come from ui/style.gd.

const Style := preload("res://ui/style.gd")
const Characters := preload("res://ui/characters.gd")
const Registers := preload("res://ui/registers.gd")
const BG := Style.BG
const CYAN := Style.CYAN
const PURPLE := Style.PURPLE
const GOLD := Style.GOLD
const GREEN := Style.GREEN
const RED := Style.RED
const ORANGE := Style.ORANGE
const DIM := Style.DIM
const TEXT := Style.TEXT
const MONO := Style.MONO
const MASK := 0xFFFFFFFF
const BRANCHES := ["beq", "bne", "blt", "bge", "bltu", "bgeu"]
## Listing and key colours by what an instruction does; steps and arithmetic are gold.
const KINDS := {"lw": CYAN, "sw": ORANGE, "label": GREEN, "beq": PURPLE, "bne": PURPLE, "blt": PURPLE,
	"bge": PURPLE, "bltu": PURPLE, "bgeu": PURPLE}


static func kind_color(op: String) -> Color:
	return KINDS.get(op, GOLD)


## The room seen from above: one tile per memory word, in row-major order. Walls are protected
## memory, glass holds a word you can reach but not stand on, and doors are words that open when
## they hold their code. The robot stands on the word a0 points to; a load flies a copy of a word
## to it and a store flies one back. In a race, a small Chip Chomper eats its way along a row.
class MazeBoard extends Control:
	signal cell_clicked(index: int)
	signal cell_hovered(index: int)
	const HEADER := 20.0
	var tiles := ""
	var width := 1
	var height := 1
	var base := 0x100
	var words: Array = []
	var doors: Dictionary = {}  # Cell → the code that opens it.
	var goal_words: Dictionary = {}
	var exit_needs: Dictionary = {}  # Register goals, shown on the exit.
	var regs: Dictionary = {}  # Values of the registers the board shows (exit goals and flags).
	var flags: Dictionary = {}  # Address registers other than a0, drawn as flags on their word.
	var labels: Dictionary = {}  # Cell → its array name, like "arr[3]".
	var eaten: Dictionary = {}
	var robot_at := Vector2.ZERO  # In cells (column, row), so the robot can glide between them.
	var chomper_at := Vector2(-1, 0)
	var chomper_row := -1
	var robot
	var chomper
	var overlay
	var walk: Tween
	var flights: Array = []
	var flashes: Dictionary = {}
	var hover := -1
	var help := ""
	var status := ""
	var status_color := TEXT
	var message := ""
	var message_color := RED
	var message_alpha := 0.0
	var bad_cell := -1
	var bad := 0.0
	var win := 0.0
	var t := 0.0

	func _init(room: Dictionary) -> void:
		custom_minimum_size = Vector2(0, 236)
		mouse_filter = Control.MOUSE_FILTER_STOP
		for row in room.map:
			tiles += str(row)
		width = str(room.map[0]).length()
		height = room.map.size()
		base = int(room.base)
		for address in room.get("doors", {}):
			doors[_index(address)] = int(room.doors[address]) & MASK
		var goal: Dictionary = room.goal
		for address in goal.get("memory", {}):
			goal_words[_index(address)] = int(goal.memory[address]) & MASK
		for name in goal.get("registers", {}):
			exit_needs[str(name)] = int(goal.registers[name]) & MASK
		# A starting register that holds one of the room's addresses is drawn as a flag there.
		for name in room.get("registers", {}):
			var value := int(room.registers[name])
			if value >= base and value < base + 4 * tiles.length() and value % 4 == 0:
				flags[str(name)] = value
		for array in room.get("arrays", []):
			var first := _index(array.at)
			for k in range(int(array.length)):
				labels[first + k] = str(array.name) if int(array.length) == 1 else "%s[%d]" % [array.name, k]
		if room.has("chomper"):
			chomper_row = int(room.chomper.row)
			chomper = Characters.Chomper.new()
			add_child(chomper)
		robot = Characters.Robot.new()
		add_child(robot)
		# Labels go on a layer above the characters, so the robot never hides a word's address.
		overlay = Overlay.new()
		overlay.board = self
		add_child(overlay)

	func _index(address) -> int:
		return (str(address).hex_to_int() - base) / 4

	func cell_size() -> float:
		return floorf(minf(92.0, minf((size.x - 16.0) / width, (size.y - HEADER - 14.0) / height)))

	func origin() -> Vector2:
		var side := cell_size()
		return Vector2((size.x - width * side) / 2.0, HEADER + (size.y - HEADER - height * side) / 2.0).floor()

	func cell_rect(index: int) -> Rect2:
		var side := cell_size()
		return Rect2(origin() + Vector2(index % width, index / width) * side, Vector2(side, side))

	func cell_center(index: int) -> Vector2:
		return cell_rect(index).get_center()

	func at(cell: Vector2) -> Vector2:
		return origin() + (cell + Vector2(0.5, 0.5)) * cell_size()

	func cell_at(point: Vector2) -> int:
		var local := (point - origin()) / cell_size()
		if local.x < 0 or local.y < 0 or local.x >= width or local.y >= height:
			return -1
		return int(local.y) * width + int(local.x)

	## Snap to a run's result; `animate` glides the robot there and lights what changed.
	func show_state(state: Dictionary, animate: bool = false) -> void:
		var new_words: Array = state.words
		for i in range(new_words.size()):
			if animate and i < words.size() and new_words[i] != words[i]:
				flashes[i] = 1.0
		words = new_words.duplicate()
		eaten.clear()
		for index in state.eaten:
			eaten[index] = true
		for name in exit_needs.keys() + flags.keys():
			regs[name] = state.regs[Registers.number(str(name))]
		var cell := (int(state.regs[10]) - base) / 4
		_glide(Vector2(cell % width, cell / width), 0.3 if animate else 0.0)
		if chomper:
			var bites: int = state.eaten.size()
			chomper_at = Vector2(bites - 1, chomper_row) if bites > 0 else Vector2(-0.85, chomper_row)

	## One instruction from the interpreter's trace, played over `duration` seconds. `landed` is
	## called when a loaded value reaches the robot, so the register chips change at that moment.
	func apply_step(step: Dictionary, duration: float, landed: Callable) -> void:
		var op := str(step.op)
		if op == "lw" or op == "sw":
			var cell := int(step.cell)
			var hand: Vector2 = robot.position + Vector2(0, -cell_size() * 0.45)
			var value := int(step.value)
			if op == "lw":
				_fly(cell_center(cell), hand, value, CYAN, duration * 0.8, landed)
			else:
				_fly(hand, cell_center(cell), value, ORANGE, duration * 0.8, func():
					words[cell] = value
					flashes[cell] = 1.0
					if step.get("opened", false):
						Style.burst(self, cell_center(cell), [GREEN, GOLD, Color.WHITE], 18, 200.0, 180.0, 300.0, 4.0, 0.6))
		elif op in BRANCHES:
			if step.taken:
				var hop := create_tween()
				hop.tween_property(robot, "hop", 6.0, duration * 0.3)
				hop.tween_property(robot, "hop", 0.0, duration * 0.4)
		elif step.has("cell"):
			var cell := int(step.cell)
			_glide(Vector2(cell % width, cell / width), duration * 0.9)
		if step.has("reg") and regs.has(Registers.name(int(step.reg))) and op != "lw":
			regs[Registers.name(int(step.reg))] = int(step.value)
		if int(step.bite) >= 0:
			_bite(int(step.bite), duration)

	func set_register(name: String, value: int) -> void:
		if regs.has(name):
			regs[name] = value

	func _bite(index: int, duration: float) -> void:
		var tween := create_tween()
		tween.tween_property(self, "chomper_at", Vector2(index % width, index / width), duration * 0.5)
		tween.tween_callback(func():
			words[index] = 0
			eaten[index] = true
			chomper.mouth = 1.0
			Style.burst(self, cell_center(index), [RED, PURPLE, Color.WHITE], 10, 160.0, 180.0, 300.0, 3.5, 0.5))
		tween.tween_property(chomper, "mouth", 0.1, duration * 0.4)

	## A key that would crash: mark the cell it aimed at (if any) and flash why.
	func fault(text: String, cell: int) -> void:
		flash_message(text, RED)
		robot.hurt = 0.9
		create_tween().tween_property(robot, "hurt", 0.0, 0.8).set_delay(0.5)
		bad_cell = cell
		bad = 1.0 if cell >= 0 else 0.0
		create_tween().tween_property(self, "bad", 0.0, 0.4).set_delay(1.1)

	func flash_message(text: String, color: Color) -> void:
		message = text
		message_color = color
		message_alpha = 1.0

	func celebrate() -> void:
		var tween := create_tween()
		tween.tween_property(self, "win", 1.0, 0.2)
		tween.tween_property(self, "win", 0.6, 0.6)
		robot.cheer = 1.5
		var cells: Array = goal_words.keys()
		if tiles.contains("E"):
			cells.append(tiles.find("E"))
		for index in cells:
			Style.burst(self, cell_center(index), [GREEN, GOLD, Color.WHITE], 14, 220.0, 120.0, 420.0, 5.0, 0.8)

	func _glide(cell: Vector2, duration: float) -> void:
		if walk:
			walk.kill()
		if duration <= 0.0:
			robot_at = cell
			return
		walk = create_tween().set_trans(Tween.TRANS_SINE)
		walk.tween_property(self, "robot_at", cell, duration)

	func _fly(from: Vector2, to: Vector2, value: int, color: Color, duration: float, land: Callable) -> void:
		var flight := {"from": from, "to": to, "text": Style.word_text(value), "color": color, "t": 0.0}
		flights.append(flight)
		var tween := create_tween()
		tween.tween_method(func(progress: float): flight.t = progress, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func():
			flights.erase(flight)
			land.call())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var cell := cell_at(event.position)
			if cell != hover:
				hover = cell
				cell_hovered.emit(cell)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var cell := cell_at(event.position)
			if cell >= 0:
				cell_clicked.emit(cell)
				accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and hover != -1:
			hover = -1
			cell_hovered.emit(-1)

	func _process(delta: float) -> void:
		t += delta
		message_alpha = move_toward(message_alpha, 0.0, delta * 0.5)
		for key in flashes.keys():
			flashes[key] = move_toward(flashes[key], 0.0, delta * 1.6)
		var side := cell_size()
		robot.scale = Vector2.ONE * side / 80.0
		robot.position = at(robot_at) + Vector2(0, side * 0.3)
		robot.walking = walk != null and walk.is_running()
		if chomper:
			# It sits on the last word it ate, drawn to fit inside one cell.
			chomper.scale = Vector2.ONE * side / 112.0
			chomper.position = at(chomper_at) + Vector2(0, -side * 0.12)
		queue_redraw()
		overlay.queue_redraw()

	func robot_cell() -> int:
		return int(roundf(robot_at.y)) * width + int(roundf(robot_at.x))

	## The tiles, under the characters: floor, walls, doors, glass, the exit, and each word's value.
	func _draw() -> void:
		var font := get_theme_default_font()
		draw_string(font, Vector2(4, 14), help, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.68, 13, Color(TEXT, 0.55))
		draw_string(font, Vector2(0, 14), status, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 13, status_color)
		var here := robot_cell()
		for i in range(tiles.length()):
			_tile(font, i, i == here)

	## Everything that labels the tiles, above the characters: addresses, array names, tags, flags,
	## values in flight, and messages. A label on the robot's (or the Chomper's) cell gets a dark
	## backing so it reads over the sprite.
	func draw_overlay(canvas: CanvasItem) -> void:
		var font := get_theme_default_font()
		var here := robot_cell()
		var eating := -1
		if chomper and chomper_at.x >= 0:
			eating = int(roundf(chomper_at.y)) * width + int(roundf(chomper_at.x))
		for i in range(tiles.length()):
			if tiles[i] != "#":
				_labels(canvas, font, i, i == here, i == here or i == eating)
		for name in flags:
			_flag(canvas, name)
		if bad > 0.0 and bad_cell >= 0:
			var center := cell_center(bad_cell)
			var arm := cell_size() * 0.22
			canvas.draw_line(center - Vector2(arm, arm), center + Vector2(arm, arm), Color(RED, bad), 4)
			canvas.draw_line(center + Vector2(arm, -arm), center - Vector2(arm, -arm), Color(RED, bad), 4)
		for flight in flights:
			var progress: float = flight.t
			var point: Vector2 = flight.from.lerp(flight.to, progress) + Vector2(0, -sin(progress * PI) * 22.0)
			var chip := Rect2(point - Vector2(22, 13), Vector2(44, 26))
			Style.rounded(canvas, chip.grow(4), Color(flight.color, 0.2), 9)
			Style.rounded(canvas, chip, Color(BG, 0.95), 7, flight.color, 2)
			canvas.draw_string(MONO, chip.position + Vector2(0, 19), flight.text, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x,
				15, TEXT)
		if message_alpha > 0.0:
			var alpha := minf(1.0, message_alpha * 2.0)
			var text_width := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var box := Rect2(Vector2((size.x - text_width) / 2.0 - 14, size.y / 2.0 - 16), Vector2(text_width + 28, 32))
			Style.rounded(canvas, box, Color(BG, 0.94 * alpha), 10, Color(message_color, alpha), 2)
			canvas.draw_string(font, box.position + Vector2(14, 22), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				Color(message_color, alpha))

	func _tile(font: Font, i: int, robot_here: bool) -> void:
		var rect := cell_rect(i).grow(-2.5)
		var side := rect.size.x
		var kind := tiles[i]
		var glow: float = flashes.get(i, 0.0)
		var value: int = words[i]
		if kind == "#":
			Style.rounded(self, rect, Color("222838"), 6, Color(DIM, 0.35), 1)
			for k in range(1, 4):
				var y := rect.position.y + side * k / 4.0
				draw_line(Vector2(rect.position.x + 6, y), Vector2(rect.end.x - 6, y), Color(DIM, 0.18), 1)
			return
		var fill := Color("161d2a").lerp(Color("2b3a52"), glow)
		var border := Color(CYAN, 0.22)
		var border_width := 1
		var open: bool = doors.has(i) and value == doors[i]
		match kind:
			"E":
				fill = Color(GREEN, 0.12 + 0.05 * sin(t * 3.0)).lerp(Color(GREEN, 0.3), win)
				border = GREEN
				border_width = 2
			"D":
				fill = Color(GREEN, 0.06) if open else Color("2b2512")
				border = GREEN if open else GOLD
				border_width = 2
			"B":
				fill = Color("15202b").lerp(Color("2b3a52"), glow)
				border = Color(CYAN, 0.45)
		if robot_here:
			border = CYAN
			border_width = 2
		if hover == i:
			Style.rounded(self, rect.grow(2), Color(CYAN, 0.16), 9)
		if goal_words.has(i) and value == goal_words[i] and win > 0.0:
			Style.rounded(self, rect.grow(4), Color(GREEN, 0.25 * win), 10)
		Style.rounded(self, rect, fill, 8, border, border_width)
		if eaten.has(i):
			Style.rounded(self, rect, Color(RED, 0.1), 8, Color(RED, 0.55), 1)
			for k in range(3):
				var notch := rect.position + Vector2(side * (0.3 + 0.2 * k), 0)
				draw_arc(notch, side * 0.09, 0, PI, 8, Color(RED, 0.6), 2, true)
		if kind == "B":
			for k in range(1, 4):
				var x := rect.position.x + side * k / 4.0
				draw_line(Vector2(x, rect.position.y + 4), Vector2(x, rect.end.y - 4), Color(TEXT, 0.28), 2)
		if kind == "D" and not open:
			var lock := rect.position + Vector2(side - 13, side - 16)
			draw_arc(lock + Vector2(0, -3), 4, PI, TAU, 10, GOLD, 2, true)
			draw_rect(Rect2(lock + Vector2(-6, -3), Vector2(12, 9)), GOLD)
		if kind == "E":
			draw_string(font, rect.position + Vector2(0, 14), "EXIT", HORIZONTAL_ALIGNMENT_CENTER, side, 11, GREEN)
		var bright := value != 0 or kind in ["D", "B"] or goal_words.has(i)
		var number_size := int(clampf(side * 0.34, 13.0, 21.0))
		var color := RED if eaten.has(i) else TEXT.lerp(Color.WHITE, glow) if bright else Color(TEXT, 0.18)
		draw_string(MONO, rect.position + Vector2(0, side * 0.5 + number_size * 0.36), Style.word_text(value),
			HORIZONTAL_ALIGNMENT_CENTER, side, number_size, color)

	## A tile's address along its bottom, its array name in the corner, and its tags.
	func _labels(canvas: CanvasItem, font: Font, i: int, robot_here: bool, covered: bool) -> void:
		var rect := cell_rect(i).grow(-2.5)
		var side := rect.size.x
		var small := int(clampf(side * 0.15, 9.0, 12.0))
		var address := "0x%X" % (base + 4 * i)
		var baseline := rect.position.y + side - 6
		if covered:
			var plate := MONO.get_string_size(address, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x + 10
			Style.rounded(canvas, Rect2(Vector2(rect.get_center().x - plate / 2.0, baseline - small - 1), Vector2(plate, small + 6)),
				Color(BG, 0.88), 5)
		canvas.draw_string(MONO, Vector2(rect.position.x, baseline), address, HORIZONTAL_ALIGNMENT_CENTER, side, small,
			Color(CYAN, 0.75) if robot_here else Color(TEXT, 0.32 if not covered else 0.6))
		if labels.has(i):
			var name: String = labels[i]
			if covered:
				var plate := MONO.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, small).x + 8
				Style.rounded(canvas, Rect2(rect.position + Vector2(2, 1), Vector2(plate, small + 6)), Color(BG, 0.88), 5)
			canvas.draw_string(MONO, rect.position + Vector2(6, 13), name, HORIZONTAL_ALIGNMENT_LEFT, side - 10, small,
				Color(CYAN, 0.6))
		var kind := tiles[i]
		if kind == "D" and words[i] != doors[i]:
			_tag(canvas, Vector2(rect.get_center().x, rect.position.y - 1), "needs %d" % doors[i], GOLD)
		elif goal_words.has(i):
			var met: bool = words[i] == goal_words[i]
			_tag(canvas, Vector2(rect.end.x - 14, rect.position.y - 1), ("✓ " if met else "→ ") + Style.word_text(goal_words[i]),
				GREEN if met else GOLD)
		if kind == "E":
			var y := rect.end.y + 9
			for name in exit_needs:
				var met: bool = regs.get(name, 0) == exit_needs[name]
				_tag(canvas, Vector2(rect.get_center().x, y), "%s = %s" % [name, Style.word_text(exit_needs[name])],
					GREEN if met else GOLD)
				y += 18

	## A small label hanging off a tile, centred on `point`.
	func _tag(canvas: CanvasItem, point: Vector2, text: String, color: Color) -> void:
		var text_width := MONO.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var rect := Rect2(point - Vector2(text_width / 2.0 + 6, 8), Vector2(text_width + 12, 16))
		Style.rounded(canvas, rect, color.darkened(0.6), 8, color, 1)
		canvas.draw_string(MONO, rect.position + Vector2(6, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color.lightened(0.3))

	## An address register other than a0, flagged on the word it points to (its top-left corner).
	func _flag(canvas: CanvasItem, name: String) -> void:
		var cell: int = (int(regs.get(name, flags[name])) - base) / 4
		if cell < 0 or cell >= tiles.length():
			return
		var corner := cell_rect(cell).grow(-2.5).position
		var label_width := MONO.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var rect := Rect2(corner + Vector2(-4, -8), Vector2(label_width + 12, 16))
		Style.rounded(canvas, rect, PURPLE.darkened(0.6), 8, PURPLE, 1)
		canvas.draw_string(MONO, rect.position + Vector2(6, 12), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, PURPLE.lightened(0.35))


## The board's top layer: it draws above the robot and the Chomper, so labels stay readable.
class Overlay extends Node2D:
	var board

	func _draw() -> void:
		board.draw_overlay(self)


## The registers a room uses, as chips: a0 (the robot's address), the hands, and any others, with
## a tag on each register that has a goal. A code room adds the pc and wraps its chips onto rows.
class RegisterChips extends Control:
	const CHIP := Vector2(110, 44)
	var names: Array = []
	var captions: Dictionary = {}
	var pointers: Array = []
	var values: Dictionary = {}
	var goals: Dictionary = {}
	var flashes: Dictionary = {}
	var per_row := 0  # Chips to a row; 0 keeps them all on one.
	var address_floor := 0  # When set, values from here up to the sign bit read as addresses, in hex.

	func _init() -> void:
		custom_minimum_size = Vector2(0, CHIP.y + 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Sizes the strip for its chips, `per_row` to a row.
	func fit() -> void:
		var rows := ceili(names.size() / float(_columns()))
		custom_minimum_size.y = 8 + rows * CHIP.y + (rows - 1) * 10

	func _columns() -> int:
		return maxi(1, names.size() if per_row <= 0 else mini(per_row, names.size()))

	func show_state(state: Dictionary, animate: bool = false) -> void:
		for name in names:
			var value: int = int(state.get("pc", 0)) if name == "pc" else state.regs[Registers.number(str(name))]
			if animate and values.get(name, value) != value:
				flashes[name] = 1.0
			values[name] = value

	func set_value(name: String, value: int) -> void:
		if name in names:
			values[name] = value
			flashes[name] = 1.0

	func _process(delta: float) -> void:
		for key in flashes.keys():
			flashes[key] = move_toward(flashes[key], 0.0, delta * 1.6)
		queue_redraw()

	func _draw() -> void:
		var columns := _columns()
		var chip_width := minf(CHIP.x, (size.x - 8.0 * (columns - 1)) / columns)
		for k in range(names.size()):
			var name: String = names[k]
			var rect := Rect2(Vector2(k % columns * (chip_width + 8), 8 + k / columns * (CHIP.y + 10)),
				Vector2(chip_width, CHIP.y))
			var value: int = values.get(name, 0)
			var accent := CYAN if captions.get(name) == "robot" else PURPLE if name in pointers else Color(TEXT, 0.4)
			var glow: float = flashes.get(name, 0.0)
			Style.rounded(self, rect, Color("141a26").lerp(Color("2b3a52"), glow), 9, accent, 2 if accent == CYAN else 1)
			# The ABI name, with its x-name small beside it, and what the register is for.
			var name_width := MONO.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(MONO, rect.position + Vector2(9, 16), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent.lightened(0.2))
			if name != "pc":
				draw_string(MONO, rect.position + Vector2(12 + name_width, 15), "x%d" % Registers.number(name),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(TEXT, 0.35))
			draw_string(MONO, rect.position + Vector2(0, 15), str(captions.get(name, "")), HORIZONTAL_ALIGNMENT_RIGHT,
				chip_width - 8, 10, Color(TEXT, 0.45))
			var address := address_floor > 0 and value >= address_floor and value < 0x80000000
			var text := "0x%X" % value if name in pointers or address else Style.word_text(value)
			draw_string(MONO, rect.position + Vector2(9, 37), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, TEXT.lerp(Color.WHITE, glow))
			if goals.has(name):
				var met: bool = value == goals[name]
				var label := ("✓ " if met else "→ ") + Style.word_text(goals[name])
				var label_width := MONO.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12
				var tag := Rect2(Vector2(rect.end.x - label_width - 4, rect.position.y - 7), Vector2(label_width, 16))
				var color := GREEN if met else GOLD
				Style.rounded(self, tag, color.darkened(0.6), 8, color, 1)
				draw_string(MONO, tag.position + Vector2(6, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color.lightened(0.3))


## The program so far, one line per action. loop: sits flush left with a bracket down to the
## branches that jump back to it; while a key runs, the running line lights up and a taken branch
## draws its jump. Long programs scroll to keep the newest (or running) line in view.
class ProgramListing extends Control:
	const TOP := 26.0
	const LINE := 19.0
	var lines: Array = []  # {"text", "op"}, plus "refused" on a key that is about to be taken back.
	var limit := 3
	var count := 0
	var running := -1
	var glow := 0.0
	var jump := 0.0
	var jump_from := -1
	var jump_to := -1
	var loops: Dictionary = {}  # Line → times its branch jumped back over the program so far.
	var shake := 0.0
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, TOP + LINE * 6 + 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_program(program_lines: Array, used: int, max_moves: int, taken: Dictionary) -> void:
		lines = program_lines
		count = used
		limit = max_moves
		loops = taken
		queue_redraw()

	func run_line(step: Dictionary, duration: float) -> void:
		running = int(step.line)
		glow = 1.0
		if step.get("taken", false):
			jump_from = running
			jump_to = _label_line()
			jump = 1.0
			create_tween().tween_property(self, "jump", 0.0, maxf(duration * 1.6, 0.25))

	func stop() -> void:
		running = -1

	func _label_line() -> int:
		for i in range(lines.size()):
			if lines[i].op == "label":
				return i
		return -1

	func _process(delta: float) -> void:
		t += delta
		glow = move_toward(glow, 0.0, delta * 1.5)
		shake = move_toward(shake, 0.0, delta * 20.0)
		queue_redraw()

	func _rows() -> int:
		return maxi(1, int((size.y - TOP - 6.0) / LINE))

	## The first line shown: everything fits, or the window ends at the newest (or running) line.
	func _first() -> int:
		var rows := _rows()
		if lines.size() <= rows:
			return 0
		var focus := running if running >= 0 else lines.size() - 1
		return clampi(focus - rows + 2, 0, lines.size() - rows)

	func _draw() -> void:
		var font := get_theme_default_font()
		var jitter := sin(t * 50.0) * shake
		var first := _first()
		var rows := _rows()
		Style.rounded(self, Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3), 10, Color(TEXT, 0.12), 1)
		draw_string(font, Vector2(12 + jitter, 18), "PROGRAM", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(TEXT, 0.6))
		var left := limit - count
		draw_string(font, Vector2(0, 18), "%d of %d instructions" % [count, limit], HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - 12, 13, GOLD if left > 0 else RED)
		var label := _label_line()
		var last_branch := -1
		for i in range(lines.size()):
			if str(lines[i].op) in BRANCHES:
				last_branch = i
		if label >= 0 and last_branch > label and last_branch >= first:
			var top := _y(maxi(label, first), first) - 5
			var bottom := _y(mini(last_branch, first + rows - 1), first) - 5
			draw_polyline(PackedVector2Array([Vector2(16, top), Vector2(8, top), Vector2(8, bottom), Vector2(16, bottom)]),
				Color(PURPLE, 0.55), 2)
		var number := 0
		for i in range(lines.size()):
			var line: Dictionary = lines[i]
			if line.op != "label":
				number += 1
			if i < first or i >= first + rows:
				continue
			var y := _y(i, first)
			if i == running and glow > 0.0:
				Style.rounded(self, Rect2(Vector2(20, y - 14), Vector2(size.x - 30, 19)), Color(GOLD, 0.25 * glow), 5)
			var refused: bool = line.get("refused", false)
			var color: Color = RED if refused else KINDS.get(str(line.op), GOLD)
			if line.op == "label":
				draw_string(MONO, Vector2(22 + jitter, y), str(line.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
			else:
				draw_string(font, Vector2(20 + jitter, y), str(number), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(TEXT, 0.35))
				draw_string(MONO, Vector2(46 + jitter, y), str(line.text), HORIZONTAL_ALIGNMENT_LEFT, size.x - 54, 14,
					color if refused else TEXT.lerp(color, 0.35))
				if loops.get(i, 0) > 0:
					draw_string(font, Vector2(0, y), "↑ %d×" % loops[i], HORIZONTAL_ALIGNMENT_RIGHT, size.x - 10, 12,
						Color(PURPLE, 0.9))
		if first > 0:
			draw_string(font, Vector2(0, TOP + 2), "▲ %d more" % first, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 12, 11,
				Color(TEXT, 0.35))
		for k in range(lines.size() - first, mini(rows, lines.size() - first + maxi(left, 0))):
			draw_string(font, Vector2(22, TOP + 15.0 + k * LINE), "·", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(TEXT, 0.25))
		if jump > 0.0 and jump_to >= 0 and jump_from >= first and jump_from < first + rows:
			var from := Vector2(18, _y(jump_from, first) - 5)
			var to := Vector2(18, _y(maxi(jump_to, first), first) - 5)
			var points := PackedVector2Array()
			for k in range(13):
				var along := k / 12.0
				points.append(from.lerp(to, along) + Vector2(-sin(along * PI) * 14.0, 0))
			draw_polyline(points, Color(PURPLE, jump), 3, true)
			draw_colored_polygon(PackedVector2Array([to + Vector2(6, 0), to + Vector2(-2, -5), to + Vector2(-2, 5)]),
				Color(PURPLE, jump))

	func _y(i: int, first: int) -> float:
		return TOP + 15.0 + (i - first) * LINE
