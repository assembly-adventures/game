extends RefCounted
## One Level 2 room: a maze made of memory words. The player steers the robot with the arrow keys
## (or WASD, or by clicking a neighbouring cell) and clicks any word to load it into a register or
## store one there: base + offset reaches the whole room. Every action is a real RISC-V line,
## written into the program as it runs. In teaching rooms, loop: marks where a lesson starts and a Repeat key closes it, so the
## robot replays the pass it was shown. An action that would crash (walking into a wall, glass, a
## locked door, or off the room; a loop that never ends) plays up to the crash, says why, and is
## taken back, so it never costs a strike. The room reports an attempt by itself when its goal
## holds or the instructions run out. The interpreter mirrors run_maze in server/puzzles.py; the
## server replays the program and has the final say.

signal attempt

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const MazeVisuals := preload("res://levels/level_2/maze_visuals.gd")
const Assembly := preload("res://levels/level_2/assembly.gd")
const Registers := preload("res://ui/registers.gd")
const Style := preload("res://ui/style.gd")
const BRANCHES := MazeVisuals.BRANCHES
const STEP_LIMIT := 200  ## Instructions a program may run before it counts as an endless loop; matches server/puzzles.py.
const MASK := 0xFFFFFFFF
const STEPS := {KEY_RIGHT: Vector2i(1, 0), KEY_D: Vector2i(1, 0), KEY_LEFT: Vector2i(-1, 0), KEY_A: Vector2i(-1, 0),
	KEY_DOWN: Vector2i(0, 1), KEY_S: Vector2i(0, 1), KEY_UP: Vector2i(0, -1), KEY_W: Vector2i(0, -1)}
## Why an action was refused, by fault.
const FAULTS := {
	"wall": "WALL: that word is protected memory.",
	"glass": "GLASS: you can reach the word behind it, but not stand there.",
	"locked": "LOCKED: this door opens when its word holds %d.",
	"edge": "EDGE: there's no more of this room that way.",
	"wrap": "WRAP: +4 from the end of a row is the next row's first word, not a neighbour.",
	"loop": "ENDLESS LOOP: the robot would repeat forever.",
	"label": "NO LABEL: tap loop: first, so Repeat has somewhere to jump back to.",
}

var payload: Dictionary
var tiles := ""
var width := 1
var base := 0x100
var lines: Array = []
var state: Dictionary = {}
var action_lines: Array = []
var hint := ""
var hint_used := false
var fails := 0
var locked := false
var playing := false
var disabled := false
var board
var chips
var listing
var bubble: Control
var keys: Array = []
var undo_button: Button
var restart_button: Button
var hint_button: Button
var hint_label: Label

func _init(room: Dictionary, box: VBoxContainer, hint_text) -> void:
	payload = room
	for row in room.map:
		tiles += str(row)
	width = str(room.map[0]).length()
	base = int(room.base)
	hint = "" if hint_text == null else str(hint_text)
	if room.get("loop", false):
		action_lines.append("loop:")
	action_lines.append_array(room.get("repeat", []) + room.get("keys", []))
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 14)
	box.add_child(main)
	board = MazeVisuals.MazeBoard.new(room)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_show_help)
	main.add_child(board)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(472, 0)
	side.add_theme_constant_override("separation", 8)
	main.add_child(side)
	chips = MazeVisuals.RegisterChips.new()
	_setup_chips()
	side.add_child(chips)
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 8)
	side.add_child(middle)
	listing = MazeVisuals.ProgramListing.new()
	listing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(listing)
	if not action_lines.is_empty():
		var column := VBoxContainer.new()
		column.custom_minimum_size = Vector2(206, 0)
		column.add_theme_constant_override("separation", 6)
		middle.add_child(column)
		for i in range(action_lines.size()):
			keys.append(_make_key(i))
			column.add_child(keys[i])
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	side.add_child(tools)
	undo_button = _tool("Undo", undo, "Backspace")
	restart_button = _tool("Restart", restart, "R")
	hint_button = _tool("Hint", show_hint, "")
	for tool in [undo_button, restart_button, hint_button]:
		tools.add_child(tool)
	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_color", Style.GOLD)
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.hide()
	box.add_child(hint_label)
	state = run(payload, [])
	board.show_state(state)
	chips.show_state(state)
	_sync()

func answer() -> Dictionary:
	return {"program": lines.duplicate()}

func retry_tip() -> String:
	return "The room resets: try again."

## Every line this room offers, and the registers it shows, for the instruction guide.
func guide() -> Dictionary:
	return {"lines": room_lines(payload).keys(), "registers": chips.names}

func stars() -> int:
	return 3 - int(_count() > int(payload.par)) - int(hint_used)

func set_disabled(value: bool) -> void:
	disabled = value
	_close_bubble()
	_sync()

## Arrow keys and WASD step the robot; Escape closes the action bubble.
func handle_key(key: int) -> bool:
	if STEPS.has(key):
		var direction: Vector2i = STEPS[key]
		_write("addi a0, a0, %d" % (4 * direction.x + 4 * width * direction.y))
		return true
	if key == KEY_ESCAPE and bubble != null:
		_close_bubble()
		return true
	return false

## Number keys press the room's keys: loop:, its Repeat branches, and any extras.
func press(index: int) -> void:
	if index >= 0 and index < action_lines.size():
		_write(action_lines[index])

func undo() -> void:
	if locked or playing or disabled or lines.is_empty():
		return
	lines.pop_back()
	_rewind()

func restart() -> void:
	if locked or playing or disabled or lines.is_empty():
		return
	lines.clear()
	_rewind()

func show_hint() -> void:
	if hint.is_empty() or hint_used:
		return
	hint_used = true
	Audio.play("hint", -4.0)
	hint_label.text = "Hint: " + hint
	hint_label.show()
	hint_button.modulate = Color.WHITE
	_sync()

## The room is open: celebrate, and put the hint away to make room for the explanation.
func solved() -> void:
	locked = true
	board.celebrate()
	hint_label.hide()
	_sync()

## The server did not accept the program: shake, then start the room over.
func failed() -> void:
	fails += 1
	listing.shake = 8.0
	board.flash_message("OUT OF INSTRUCTIONS", Style.RED)
	await board.get_tree().create_timer(0.9).timeout
	if not is_instance_valid(board):
		return
	reset()
	if fails >= 2 and not hint_used and not hint.is_empty():
		hint_button.text = "Need a hint?"
		hint_button.modulate = Style.GOLD

func reset() -> void:
	lines.clear()
	locked = false
	state = run(payload, [])
	board.show_state(state, true)
	chips.show_state(state, true)
	_sync()

## Runs one more line: plays its new steps, then keeps it, or shows why it would crash and takes it back.
func _write(line: String) -> void:
	_close_bubble()
	if locked or playing or disabled:
		return
	if line == "loop:" and _labelled() or line != "loop:" and _count() >= int(payload.max_moves):
		return
	var before := state
	var after := run(payload, lines + [line])
	# The program only grew at the end, so its new steps follow on from the old trace.
	var fresh: Array = after.trace.slice(before.trace.size())
	Audio.play("press", -2.0 if line in action_lines else -8.0, 0.1)
	if after.fault.is_empty():
		lines.append(line)
	playing = true
	_sync("" if after.fault.is_empty() else line)
	if after.fault == "loop":
		fresh = fresh.slice(0, 24)  # Enough to see it spin.
	await _play(fresh)
	if not is_instance_valid(board):
		return
	if not after.fault.is_empty():
		await _refuse(after, before)
		return
	state = after
	board.show_state(state)
	chips.show_state(state)
	listing.stop()
	playing = false
	if goal_met(payload, state) or _count() >= int(payload.max_moves):
		locked = true
		_sync()
		await board.get_tree().create_timer(0.45).timeout
		if is_instance_valid(board):
			attempt.emit()
		return
	_sync()

## Plays new trace steps one after another; a loop speeds up so it finishes in a few seconds.
func _play(steps: Array) -> void:
	var duration := 0.3 if steps.size() <= 1 else clampf(3.2 / steps.size(), 0.1, 0.26)
	for step in steps:
		if not is_instance_valid(board):
			return
		var landed := func(): pass
		if str(step.op) == "lw":
			landed = func():
				chips.set_value(Registers.name(int(step.reg)), int(step.value))
				board.set_register(Registers.name(int(step.reg)), int(step.value))
		elif step.has("reg") and str(step.op) != "sw":
			chips.set_value(Registers.name(int(step.reg)), int(step.value))
		board.apply_step(step, duration, landed)
		listing.run_line(step, duration)
		if payload.has("chomper"):
			_show_status(step)
		if step.get("opened", false):
			Audio.play("open", -9.0)
		elif int(step.bite) >= 0:
			Audio.play("chomp", -16.0, 0.1)
		elif steps.size() > 1:
			Audio.play("press", -16.0, 0.25)
		await board.get_tree().create_timer(duration).timeout

## Shows why the last action would crash, then puts everything back the way it was.
func _refuse(after: Dictionary, before: Dictionary) -> void:
	var message: String = FAULTS[after.fault]
	if after.fault == "locked":
		message = message % int(after.code)
	board.fault(message, int(after.cell))
	listing.shake = 6.0
	Audio.play("overflow", -4.0)
	await board.get_tree().create_timer(1.5).timeout
	if not is_instance_valid(board):
		return
	listing.stop()
	board.create_tween().tween_property(board, "message_alpha", 0.0, 0.25)
	board.show_state(before, true)
	chips.show_state(before, true)
	playing = false
	_sync()

func _rewind() -> void:
	_close_bubble()
	Audio.play("undo")
	state = run(payload, lines)
	board.show_state(state, true)
	chips.show_state(state, true)
	_sync()

func _on_cell_clicked(cell: int) -> void:
	_close_bubble()
	if locked or playing or disabled:
		return
	if tiles[cell] == "#":
		board.flash_message(FAULTS.wall, Style.ORANGE)
		return
	var options := _options_for(cell)
	if options.size() == 1:
		_write(options[0].line)
	elif not options.is_empty():
		_show_bubble(cell, options)
	elif cell != _robot_cell():
		board.flash_message("STEP: the robot moves one cell at a time.", Style.ORANGE)

## What the robot can do with a word: step onto it (if it's next door), load it into a hand, or
## store a hand there. Base + offset reaches every word of the room.
func _options_for(cell: int) -> Array:
	var here := _robot_cell()
	var offset := 4 * (cell - here)
	var options: Array = []
	if _next_to(cell) and tiles[cell] != "B":
		options.append({"line": "addi a0, a0, %d" % offset, "label": "step here"})
	for hand in payload.hands:
		options.append({"line": "lw %s, %d(a0)" % [hand, offset], "label": "load into %s" % hand})
	for hand in payload.hands:
		options.append({"line": "sw %s, %d(a0)" % [hand, offset], "label": "store %s here" % hand})
	return options

func _next_to(cell: int) -> bool:
	var here := _robot_cell()
	return absi(here / width - cell / width) + absi(here % width - cell % width) == 1

## Where a word is, the way the lecture writes it: its address is a0 plus an offset.
func _address_text(cell: int) -> String:
	var offset := 4 * (cell - _robot_cell())
	var label: String = board.labels.get(cell, "")
	return "%s0x%X = a0 %s %d" % ["" if label.is_empty() else label + " · ", base + 4 * cell,
		"-" if offset < 0 else "+", absi(offset)]

## The line above the board: how to play, or what a click on the hovered word would do.
func _show_help(cell: int = -1) -> void:
	var text := "Arrow keys or WASD step · " + ("click any word to load or store it" if not payload.hands.is_empty()
		else "or click the next cell")
	if cell >= 0 and not (locked or playing or disabled) and tiles[cell] != "#":
		var options := _options_for(cell)
		if options.size() == 1 and payload.hands.is_empty():
			text = "Click: %s  (%s)" % [options[0].label, options[0].line]
		elif not options.is_empty():
			text = "Click to %s %s" % ["step, load, or store:" if options[0].label == "step here" else "load or store:",
				_address_text(cell)]
	board.help = text

## The line's right side: teaching, and in the race, the cycle count and the Chomper's next bite.
func _show_status(step: Dictionary = {}) -> void:
	board.status = ""
	if _labelled() and not _branched():
		board.status = "● TEACHING: show one pass, then Repeat"
		board.status_color = Style.RED
	if not payload.has("chomper"):
		return
	var start := int(payload.chomper.start)
	var every := int(payload.chomper.every)
	var cycle := int(step.get("cycle", state.trace.size()))
	var bites := 0 if cycle < start else 1 + (cycle - start) / every
	if bites == 0:
		board.status = "cycle %d · the Chomper wakes at cycle %d" % [cycle, start]
	elif bites < int(payload.chomper.words):
		board.status = "cycle %d · next bite in %d" % [cycle, start + every * bites - cycle]
	else:
		board.status = "cycle %d · the Chomper ate the whole row" % cycle
	board.status_color = Style.ORANGE

func _show_bubble(cell: int, options: Array) -> void:
	bubble = PanelContainer.new()
	var look := Style.panel_style()
	look.set_content_margin_all(6)
	look.border_color = Style.CYAN
	bubble.add_theme_stylebox_override("panel", look)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	bubble.add_child(column)
	var heading := Label.new()
	heading.text = _address_text(cell)
	heading.add_theme_font_override("font", Style.MONO)
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Style.CYAN)
	column.add_child(heading)
	for option in options:
		var color: Color = MazeVisuals.kind_color(str(option.line).split(" ")[0])
		var button := Button.new()
		button.custom_minimum_size = Vector2(268, 30)
		button.focus_mode = Control.FOCUS_NONE
		for look_state in ["normal", "hover", "pressed", "disabled"]:
			var key_look := Style.key_style(color, look_state)
			key_look.set_content_margin_all(4)
			key_look.border_width_bottom = 2 if look_state == "pressed" else 3
			button.add_theme_stylebox_override(look_state, key_look)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.offset_right = -10
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for part in [[option.line, 14, Style.TEXT], [option.label, 12, color]]:
			var label := Label.new()
			label.text = part[0]
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.size_flags_vertical = Control.SIZE_FILL
			label.add_theme_font_size_override("font_size", part[1])
			label.add_theme_color_override("font_color", part[2])
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(label)
		row.get_child(0).add_theme_font_override("font", Style.MONO)
		row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_child(row)
		button.pressed.connect(_write.bind(str(option.line)))
		column.add_child(button)
	board.add_child(bubble)
	bubble.reset_size()
	var rect: Rect2 = board.cell_rect(cell)
	var place := Vector2(rect.end.x + 6, rect.position.y)
	if place.x + bubble.size.x > board.size.x:
		place.x = rect.position.x - bubble.size.x - 6
	place.y = clampf(place.y, 0.0, maxf(board.size.y - bubble.size.y, 0.0))
	bubble.position = place

func _close_bubble() -> void:
	if bubble != null and is_instance_valid(bubble):
		bubble.queue_free()
	bubble = null

## Refreshes the keys, the listing, and the board's help; `refused` is a line shown in red while it
## plays out before being taken back.
func _sync(refused: String = "") -> void:
	var off := disabled or locked or playing
	var full := _count() >= int(payload.max_moves)
	for i in range(keys.size()):
		keys[i].disabled = off or (_labelled() if action_lines[i] == "loop:" else full)
		keys[i].modulate.a = 0.45 if keys[i].disabled else 1.0
	undo_button.disabled = off or lines.is_empty()
	restart_button.disabled = off or lines.is_empty()
	hint_button.disabled = disabled or locked or hint_used or hint.is_empty()
	var shown: Array = []
	for line in lines + ([] if refused.is_empty() else [refused]):
		shown.append({"text": line, "op": parse(line).op})
	if not refused.is_empty():
		shown[-1].refused = true
	# How many times each branch jumped back over the program so far.
	var taken := {}
	for step in state.trace:
		if step.get("taken", false):
			taken[int(step.line)] = int(taken.get(int(step.line), 0)) + 1
	listing.set_program(shown, _count(), int(payload.max_moves), taken)
	_show_help(board.hover)
	_show_status()

func _setup_chips() -> void:
	var names := ["a0"]
	for name in payload.hands + payload.get("registers", {}).keys() + payload.goal.get("registers", {}).keys():
		if str(name) not in names:
			names.append(str(name))
	for line in action_lines:
		var ins := parse(line)
		for field in ["rd", "rs1", "rs2"]:
			if ins.has(field) and Registers.name(int(ins[field])) not in names:
				names.append(Registers.name(int(ins[field])))
	chips.names = names
	chips.pointers = ["a0"] + board.flags.keys()
	var nicknames: Dictionary = payload.get("names", {})
	for name in names:
		chips.captions[name] = "robot" if name == "a0" else nicknames.get(name, "always 0" if name == "x0"
			else "hand" if name in payload.hands else "end" if name in chips.pointers else "")
	for name in payload.goal.get("registers", {}):
		chips.goals[str(name)] = int(payload.goal.registers[name]) & MASK

func _robot_cell() -> int:
	return (int(state.regs[10]) - base) / 4

func _count() -> int:
	return lines.size() - int(_labelled())

func _labelled() -> bool:
	return "loop:" in lines

func _branched() -> bool:
	for line in lines:
		if parse(line).op in BRANCHES:
			return true
	return false

func _make_key(i: int) -> Button:
	var line: String = action_lines[i]
	var color: Color = MazeVisuals.kind_color(str(parse(line).op))
	var key := Button.new()
	key.custom_minimum_size = Vector2(206, 50)
	key.focus_mode = Control.FOCUS_NONE
	key.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for look in ["normal", "hover", "pressed", "disabled"]:
		var key_look := Style.key_style(color, look)
		key_look.set_content_margin_all(4)
		key_look.border_width_bottom = 2 if look == "pressed" else 4
		key.add_theme_stylebox_override(look, key_look)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in [[line, 14, Style.TEXT], [caption(line), 12, color]]:
		var label := Label.new()
		label.text = part[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", part[1])
		label.add_theme_color_override("font_color", part[2])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
	column.get_child(0).add_theme_font_override("font", Style.MONO)
	key.add_child(column)
	var hotkey := Label.new()
	hotkey.text = str(i + 1)
	hotkey.position = Vector2(8, 3)
	hotkey.add_theme_font_size_override("font_size", 11)
	hotkey.add_theme_color_override("font_color", Color(Style.TEXT, 0.4))
	hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_child(hotkey)
	key.pressed.connect(_write.bind(line))
	return key

func _tool(text: String, action: Callable, shortcut: String) -> Button:
	var tool := Button.new()
	tool.text = text
	tool.tooltip_text = shortcut
	tool.custom_minimum_size = Vector2(92, 30)
	tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool.add_theme_font_size_override("font_size", 14)
	tool.focus_mode = Control.FOCUS_NONE
	tool.pressed.connect(action)
	return tool

## A room key in plain words.
static func caption(line: String) -> String:
	if line == "loop:":
		return "start teaching here"
	var ins := parse(line)
	var op := str(ins.op)
	if op in BRANCHES:
		var test: String = {"beq": "=", "bne": "≠", "blt": "<", "bge": "≥", "bltu": "<", "bgeu": "≥"}[op]
		var other := "0" if int(ins.rs2) == 0 else Registers.name(int(ins.rs2))
		return "Repeat while %s %s %s" % [Registers.name(int(ins.rs1)), test, other]
	return PuzzleRoom.face_for(ins, MASK)[1]

## Every line the player can write in a room: a step each way, a load or store with each hand at
## any offset that could land on one of its words, and the room's keys. Mirrors maze_lines in
## server/puzzles.py.
static func room_lines(room: Dictionary) -> Dictionary:
	var row := 4 * str(room.map[0]).length()
	var words := 0
	for line in room.map:
		words += str(line).length()
	var allowed := {}
	for step in [4, -4, row, -row]:
		allowed["addi a0, a0, %d" % step] = true
	for hand in room.get("hands", []):
		for offset in range(-4 * (words - 1), 4 * words, 4):
			allowed["lw %s, %d(a0)" % [hand, offset]] = true
			allowed["sw %s, %d(a0)" % [hand, offset]] = true
	for line in room.get("keys", []) + room.get("repeat", []):
		allowed[str(line)] = true
	if room.get("loop", false):
		allowed["loop:"] = true
	return allowed

## One line, in the exact form the game writes it.
static func parse(line: String) -> Dictionary:
	return Assembly.parse(line)

static func branch_taken(op: String, a: int, b: int) -> bool:
	return Assembly.branch_taken(op, a, b)

## Runs a program from the room's start. Returns the registers and words it finished with, the
## cells the Chomper ate, the trace of every instruction it ran (for animation), and, if it would
## crash, why ("fault") with the line, the cell it aimed at, and a locked door's code.
static func run(room: Dictionary, program_lines: Array) -> Dictionary:
	var tiles := ""
	for row in room.map:
		tiles += str(row)
	var width := str(room.map[0]).length()
	var base := int(room.base)
	var words: Array = []
	words.resize(tiles.length())
	words.fill(0)
	for address in room.get("values", {}):
		words[(str(address).hex_to_int() - base) / 4] = int(room.values[address]) & MASK
	var doors := {}
	for address in room.get("doors", {}):
		doors[(str(address).hex_to_int() - base) / 4] = int(room.doors[address]) & MASK
	var regs: Array = []
	regs.resize(32)
	regs.fill(0)
	regs[10] = base + 4 * tiles.find("S")
	for name in room.get("registers", {}):
		regs[Registers.number(str(name))] = int(room.registers[name]) & MASK
	var chomper: Dictionary = room.get("chomper", {})
	var program: Array = []
	var label := -1
	for i in range(program_lines.size()):
		program.append(parse(program_lines[i]))
		if program[i].op == "label" and label < 0:
			label = i
	var result := {"regs": regs, "words": words, "eaten": [], "trace": [], "fault": "", "line": -1, "cell": -1, "code": 0}
	var pc := 0
	var steps := 0
	while pc < program.size():
		var ins: Dictionary = program[pc]
		var op := str(ins.op)
		var line := pc
		pc += 1
		if op == "label":
			continue
		steps += 1
		if steps > STEP_LIMIT:
			return _fault(result, "loop", line)
		var here: int = (regs[10] - base) / 4
		var step := {"line": line, "op": op, "cycle": steps, "bite": -1}
		if op in BRANCHES:
			if label < 0 or label >= pc:
				return _fault(result, "label", line)
			step.taken = branch_taken(op, regs[int(ins.rs1)], regs[int(ins.rs2)])
			if step.taken:
				pc = label + 1
		elif op == "lw" or op == "sw":
			var target := _cell(tiles, base, (regs[int(ins.rs1)] + int(ins.imm)) & MASK)
			if target < 0:
				return _fault(result, "edge", line)
			if tiles[target] == "#":
				return _fault(result, "wall", line, target)
			var reg := int(ins.rs2) if op == "sw" else int(ins.rd)
			if op == "sw":
				words[target] = regs[reg]
				step.opened = doors.has(target) and words[target] == doors[target]
			elif reg != 0:
				regs[reg] = words[target]
			step.merge({"reg": reg, "cell": target, "value": words[target], "offset": int(ins.imm)})
		else:
			var second: int = regs[int(ins.rs2)] if ins.has("rs2") else int(ins.imm) & MASK
			var value := PuzzleRoom.execute(op, regs[int(ins.rs1)], second, 32)
			var rd := int(ins.rd)
			if rd == 10:
				var target := _cell(tiles, base, value)
				if target < 0:
					return _fault(result, "edge", line)
				if _apart(here, target, width) != 1:
					return _fault(result, "wrap", line, target)
				if tiles[target] == "#":
					return _fault(result, "wall", line, target)
				if tiles[target] == "B":
					return _fault(result, "glass", line, target)
				if doors.has(target) and words[target] != doors[target]:
					result.code = doors[target]
					return _fault(result, "locked", line, target)
				step.cell = target
			if rd != 0:
				regs[rd] = value
			step.merge({"reg": rd, "value": regs[rd]})
		if not chomper.is_empty() and steps >= int(chomper.start) and (steps - int(chomper.start)) % int(chomper.every) == 0:
			var bite := (steps - int(chomper.start)) / int(chomper.every)
			if bite < int(chomper.words):
				var eaten := int(chomper.row) * width + bite
				words[eaten] = 0
				step.bite = eaten
				result.eaten.append(eaten)
		result.trace.append(step)
	return result

static func _cell(tiles: String, base: int, address: int) -> int:
	var offset := address - base
	if offset % 4 != 0 or offset < 0 or offset >= 4 * tiles.length():
		return -1
	return offset / 4

static func _apart(a: int, b: int, width: int) -> int:
	return absi(a / width - b / width) + absi(a % width - b % width)

static func _fault(result: Dictionary, kind: String, line: int, cell: int = -1) -> Dictionary:
	result.fault = kind
	result.line = line
	result.cell = cell
	return result

## The robot stands on the exit (if the room has one) and every goal word and register holds.
static func goal_met(room: Dictionary, result: Dictionary) -> bool:
	if not result.fault.is_empty():
		return false
	var tiles := ""
	for row in room.map:
		tiles += str(row)
	var base := int(room.base)
	if tiles.contains("E") and result.regs[10] != base + 4 * tiles.find("E"):
		return false
	var goal: Dictionary = room.goal
	for name in goal.get("registers", {}):
		if result.regs[Registers.number(str(name))] != int(goal.registers[name]) & MASK:
			return false
	for address in goal.get("memory", {}):
		if result.words[(str(address).hex_to_int() - base) / 4] != int(goal.memory[address]) & MASK:
			return false
	return true

## Mirrors grade_maze in server/puzzles.py for guest mode, where the game grades itself.
static func grade(room: Dictionary, response: Dictionary) -> bool:
	var program = response.get("program", [])
	if not (program is Array) or program.is_empty() or program.size() > int(room.max_moves) + 1:
		return false
	var allowed := room_lines(room)
	var labels := 0
	for line in program:
		if not (line is String) or not allowed.has(line):
			return false
		if line == "loop:":
			labels += 1
		elif labels == 0 and parse(line).op in BRANCHES:
			return false
	var count: int = program.size() - labels
	if labels > 1 or count < 1 or count > int(room.max_moves):
		return false
	return goal_met(room, run(room, program))
