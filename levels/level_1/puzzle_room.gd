extends RefCounted
## One Level 1 gate: press instruction keys until register x5 matches the target pattern.
## The gate reports an attempt by itself when the bulbs match or the moves run out. The
## interpreter mirrors server/puzzles.py; the server replays the presses and has the final say.

signal attempt

const Visuals := preload("res://levels/level_1/visuals.gd")
const Style := preload("res://ui/style.gd")
const R_TYPE := ["add", "sub", "and", "or", "xor", "sll", "srl", "sra", "slt", "sltu"]
const STRIKES := 3  ## Failed tries before the Chip Chomper drags the robot back; matches server/gameplay.py.

var payload: Dictionary
var width := 32
var mask := 0
var main := "x5"
var buttons: Array = []
var moves: Array = []
var hint := ""
var hint_used := false
var fails := 0
var locked := false
var disabled := false
var strip
var tray
var keys: Array = []
var undo_button: Button
var restart_button: Button
var hint_button: Button
var hint_label: Label

func _init(room: Dictionary, box: VBoxContainer, hint_text) -> void:
	payload = room
	width = int(payload.get("width", 32))
	mask = (1 << width) - 1
	main = str(payload.goal.keys()[0])
	buttons = payload.buttons
	hint = "" if hint_text == null else str(hint_text)
	var display := str(payload.get("display", "unsigned"))
	strip = Visuals.RegisterStrip.new(width, display == "signed", display == "hex", main)
	strip.target = int(payload.goal[main]) & mask
	for reg in payload.get("initial", {}):
		if reg != main:
			strip.extras[reg] = int(payload.initial[reg]) & mask
	strip.show_value(_value())
	box.add_child(strip)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	for i in range(buttons.size()):
		keys.append(_make_key(i))
		row.add_child(keys[i])
	box.add_child(row)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tray = Visuals.MoveTray.new()
	tools.add_child(tray)
	undo_button = _tool("Undo", undo, "Backspace")
	restart_button = _tool("Restart", restart, "R")
	hint_button = _tool("Hint", show_hint, "")
	for tool in [undo_button, restart_button, hint_button]:
		tools.add_child(tool)
	box.add_child(tools)
	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_color", Visuals.GOLD)
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.hide()
	box.add_child(hint_label)
	_sync()

func answer() -> Dictionary:
	return {"moves": moves.duplicate()}

func stars() -> int:
	return 3 - int(moves.size() > int(payload.par)) - int(hint_used)

func set_disabled(value: bool) -> void:
	disabled = value
	_sync()

func press(index: int) -> void:
	if locked or disabled or index < 0 or index >= buttons.size() or moves.size() >= int(payload.max_moves):
		return
	var before := _regs()
	moves.append(index)
	var ins: Dictionary = buttons[index]
	var op := str(ins.op)
	var shift := int(ins.get("imm", 0)) * (1 if op in ["slli", "sll"] else -1)
	var how := "slide" if op in ["slli", "srli", "srai", "sll", "srl", "sra"] else "ripple" if op in ["add", "addi", "sub"] else "sweep"
	strip.animate_to(_value(), how, shift)
	_warn_overflow(ins, before)
	Audio.play("press", -2.0, 0.08)
	if _solved() or moves.size() >= int(payload.max_moves):
		# Let the bulbs settle before the gate reacts.
		locked = true
		_sync()
		await strip.get_tree().create_timer(0.4).timeout
		if is_instance_valid(strip):
			attempt.emit()
		return
	_sync()

func undo() -> void:
	if locked or disabled or moves.is_empty():
		return
	moves.pop_back()
	Audio.play("undo")
	strip.animate_to(_value(), "sweep")
	_sync()

func restart() -> void:
	if locked or disabled or moves.is_empty():
		return
	moves.clear()
	Audio.play("undo")
	strip.animate_to(_value(), "sweep")
	_sync()

func show_hint() -> void:
	if hint.is_empty() or hint_used:
		return
	hint_used = true
	Audio.play("hint", -4.0)
	hint_label.text = "Hint: " + hint
	hint_label.show()
	hint_button.modulate = Color.WHITE
	_sync()

func solved() -> void:
	locked = true
	strip.celebrate()
	_sync()

## The server did not accept these moves: shake, then put the register back to its start.
func failed() -> void:
	fails += 1
	tray.shake = 8.0
	strip.flash_message("OUT OF MOVES", Visuals.RED)
	await strip.get_tree().create_timer(0.9).timeout
	if not is_instance_valid(strip):
		return
	reset()
	if fails >= 2 and not hint_used and not hint.is_empty():
		hint_button.text = "Need a hint?"
		hint_button.modulate = Visuals.GOLD

func reset() -> void:
	moves.clear()
	locked = false
	strip.animate_to(_value(), "sweep")
	_sync()

func _sync() -> void:
	var off := disabled or locked
	for key in keys:
		key.disabled = off or moves.size() >= int(payload.max_moves)
		key.modulate.a = 0.45 if key.disabled else 1.0
	undo_button.disabled = off or moves.is_empty()
	restart_button.disabled = off or moves.is_empty()
	hint_button.disabled = off or hint_used or hint.is_empty()
	var lines: Array = []
	for move in moves:
		lines.append(asm(buttons[move]))
	tray.set_moves(lines, int(payload.max_moves))

func _regs() -> Array:
	var program: Array = []
	for move in moves:
		program.append(buttons[move])
	return run_program(program, payload.get("initial", {}), width)

func _value() -> int:
	return _regs()[int(main.substr(1))]

func _solved() -> bool:
	var regs := _regs()
	for reg in payload.goal:
		if regs[int(str(reg).substr(1))] != int(payload.goal[reg]) & mask:
			return false
	return true

## Adds and subtracts that leave the register's range flash a warning, since that is the lesson.
func _warn_overflow(ins: Dictionary, before: Array) -> void:
	var op := str(ins.op)
	if op not in ["add", "addi", "sub"]:
		return
	var signed_view: bool = strip.signed_view
	var a: int = before[int(ins.rs1)]
	var b: int = before[int(ins.rs2)] if ins.has("rs2") else int(ins.imm)
	if signed_view:
		a = _signed(a, width)
		if ins.has("rs2"):
			b = _signed(b, width)
	var exact := a - b if op == "sub" else a + b
	var low := -(1 << (width - 1)) if signed_view else 0
	var high := (1 << (width - 1)) - 1 if signed_view else mask
	if exact < low or exact > high:
		strip.flash_message("OVERFLOW!" if signed_view else "WRAPPED AROUND!", Visuals.RED if signed_view else Visuals.ORANGE)
		Audio.play("overflow", -4.0)

func _make_key(i: int) -> Button:
	var ins: Dictionary = buttons[i]
	var face := face_for(ins, mask)
	var color: Color = {"math": Visuals.GOLD, "shift": Visuals.CYAN}.get(face[2], Visuals.PURPLE)
	var key := Button.new()
	key.custom_minimum_size = Vector2(210, 98)
	key.focus_mode = Control.FOCUS_NONE
	key.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		key.add_theme_stylebox_override(state, Style.key_style(color, state))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in [[face[0], 28, Visuals.TEXT], [face[1], 13, color], [asm(ins), 12, Color(Visuals.TEXT, 0.55)]]:
		var label := Label.new()
		label.text = part[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", part[1])
		label.add_theme_color_override("font_color", part[2])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(label)
	column.get_child(2).add_theme_font_override("font", Style.MONO)
	key.add_child(column)
	var hotkey := Label.new()
	hotkey.text = str(i + 1)
	hotkey.position = Vector2(12, 6)
	hotkey.add_theme_font_size_override("font_size", 12)
	hotkey.add_theme_color_override("font_color", Color(Visuals.TEXT, 0.4))
	hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_child(hotkey)
	key.pressed.connect(press.bind(i))
	return key

func _tool(text: String, action: Callable, shortcut: String) -> Button:
	var tool := Button.new()
	tool.text = text
	tool.tooltip_text = shortcut
	tool.custom_minimum_size = Vector2(104, 40)
	tool.focus_mode = Control.FOCUS_NONE
	tool.pressed.connect(action)
	return tool

## What an instruction key shows: a short symbol, a plain-words caption, and a colour group.
static func face_for(ins: Dictionary, value_mask: int) -> Array:
	var imm := int(ins.get("imm", 0))
	match str(ins.op):
		"addi":
			return ["+%d" % imm if imm >= 0 else "-%d" % -imm, "add %d" % imm if imm >= 0 else "subtract %d" % -imm, "math"]
		"add":
			return ["+ x%d" % int(ins.rs2), "add register x%d" % int(ins.rs2), "math"]
		"sub":
			return ["- x%d" % int(ins.rs2), "subtract register x%d" % int(ins.rs2), "math"]
		"slli":
			return ["<< %d" % imm, "shift left", "shift"]
		"srli":
			return [">> %d" % imm, "shift right, fill with 0", "shift"]
		"srai":
			return [">> %d" % imm, "shift right, keep the sign", "shift"]
		"andi":
			return ["and 0x%02X" % imm, "keep bulbs where mask is 1", "logic"]
		"ori":
			return ["or 0x%02X" % imm, "turn bulbs on", "logic"]
		"xori":
			var all_bits := imm & value_mask == value_mask
			return ["flip all" if all_bits else "xor 0x%02X" % imm, "xor 0x%02X" % imm if all_bits else "flip some bulbs", "logic"]
	return [str(ins.op), "", "math"]

static func asm(ins: Dictionary) -> String:
	var op := str(ins.op)
	var last := "x%d" % int(ins.rs2) if ins.has("rs2") else "0x%02X" % int(ins.imm) if op in ["andi", "ori", "xori"] else str(int(ins.imm))
	return "%s x%d, x%d, %s" % [op, int(ins.rd), int(ins.rs1), last]

static func _signed(value: int, bits: int = 32) -> int:
	value &= (1 << bits) - 1
	return value - (1 << bits) if value >> (bits - 1) != 0 else value

static func _execute(op: String, a: int, b: int, bits: int) -> int:
	if op == "sltiu":
		op = "sltu"
	elif op not in R_TYPE:
		op = op.trim_suffix("i")
	var shift := b & 31
	var value_mask := (1 << bits) - 1
	match op:
		"add": return (a + b) & value_mask
		"sub": return (a - b) & value_mask
		"and": return a & b
		"or": return a | b
		"xor": return a ^ b
		"sll": return (a << shift) & value_mask
		"srl": return a >> shift
		"sra": return (_signed(a, bits) >> shift) & value_mask
		"slt": return int(_signed(a, bits) < _signed(b, bits))
		"sltu": return int(a < b)
	return 0

static func run_program(program: Array, initial: Dictionary, bits: int = 32) -> Array:
	var value_mask := (1 << bits) - 1
	var regs: Array = []
	regs.resize(32)
	regs.fill(0)
	for reg in initial:
		regs[int(str(reg).substr(1))] = int(initial[reg]) & value_mask
	for ins in program:
		var second: int = regs[int(ins.rs2)] if ins.has("rs2") else int(ins.imm) & value_mask
		if int(ins.rd) != 0:
			regs[int(ins.rd)] = _execute(str(ins.op), regs[int(ins.rs1)], second, bits)
	return regs

## Mirrors grade_puzzle in server/puzzles.py for guest mode, where the game grades itself.
static func grade(room: Dictionary, response: Dictionary) -> bool:
	var pressed: Array = response.get("moves", [])
	if pressed.is_empty() or pressed.size() > int(room.max_moves):
		return false
	var program: Array = []
	for move in pressed:
		program.append(room.buttons[int(move)])
	var bits := int(room.get("width", 32))
	var regs := run_program(program, room.get("initial", {}), bits)
	for reg in room.goal:
		if regs[int(str(reg).substr(1))] != int(room.goal[reg]) & ((1 << bits) - 1):
			return false
	return true
