extends RefCounted
## One Level 2 code room: a short program with blank lines to fill. The player clicks a blank (or
## presses its number) to pick its line, then runs the program. The robot plays the PC: it walks
## the program by address, following branches and jumps, while the registers, the data, and the
## stack change beside it. Every test runs in turn, so the program has to work for each input, and
## a run that fails one is a strike. The interpreter mirrors run_code in
## server/puzzles.py; the server replays the program and has the final say.

signal attempt

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const MazeVisuals := preload("res://levels/level_2/maze_visuals.gd")
const CodeVisuals := preload("res://levels/level_2/code_visuals.gd")
const Assembly := preload("res://levels/level_2/assembly.gd")
const Registers := preload("res://ui/registers.gd")
const Style := preload("res://ui/style.gd")
const BRANCHES := Assembly.BRANCHES
const MASK := 0xFFFFFFFF
const CODE_BASE := Assembly.CODE_BASE
const EXIT := Assembly.EXIT
const STEP_LIMIT := 500  ## Instructions a run may take before it counts as never ending; matches server/puzzles.py.
## Why a run crashed, by fault: the message over the code, then the short form for a test's card.
const FAULTS := {
	"code": ["NO CODE: the PC jumped to %s, where there's no instruction.", "the PC jumped to %s"],
	"memory": ["NO MEMORY: there's no word at %s.", "no word at %s"],
	"aligned": ["MISALIGNED: words start every 4 bytes, so none starts at %s.", "%s isn't word-aligned"],
	"loop": ["ENDLESS LOOP: the program never ends.", "it never ends"],
}

var payload: Dictionary
var options: Array = []  # Each blank's lines, in program order.
var choices: Array = []  # The line picked for each blank; "" until one is.
var picked: Array = []  # Blanks in the order they were filled, for Undo.
var hint := ""
var hint_used := false
var fails := 0
var headline := ""  # Why the last run missed, for the strike message.
var locked := false
var playing := false
var disabled := false
var picking := -1  # The blank whose list is open.
var last_list := -1
var view
var chips
var cards
var bubble: Control
var run_button: Button
var clear_button: Button
var hint_button: Button
var hint_label: Label

func _init(room: Dictionary, box: VBoxContainer, hint_text) -> void:
	payload = room
	hint = "" if hint_text == null else str(hint_text)
	options = blanks(room)
	for k in range(options.size()):
		choices.append("")
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 14)
	box.add_child(main)
	view = CodeVisuals.CodeView.new(room)
	view.step = 1
	view.note = "Pick a line for each blank"
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.blank_clicked.connect(_on_blank_clicked)
	main.add_child(view)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(408, 0)
	side.add_theme_constant_override("separation", 8)
	main.add_child(side)
	chips = MazeVisuals.RegisterChips.new()
	_setup_chips()
	side.add_child(chips)
	side.add_child(Style.step(2, "Run the tests", "the program must pass every one"))
	cards = CodeVisuals.TestCards.new(_test_lines())
	cards.title = ""
	side.add_child(cards)
	# The hint sits over the bottom of the code, so showing it never moves the controls.
	hint_label = Style.hint_box(view)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	side.add_child(keys)
	run_button = Button.new()
	run_button.custom_minimum_size = Vector2(0, 44)
	run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_button.focus_mode = Control.FOCUS_NONE
	run_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	run_button.tooltip_text = "Enter"
	run_button.add_theme_font_size_override("font_size", 18)
	for look in ["normal", "hover", "pressed", "disabled"]:
		run_button.add_theme_stylebox_override(look, Style.key_style(Style.GREEN, look))
	run_button.pressed.connect(run_tests)
	keys.add_child(run_button)
	clear_button = _tool("Clear", restart, "R")
	hint_button = _tool("Hint", show_hint, "")
	for tool in [clear_button, hint_button]:
		keys.add_child(tool)
	_show_start(0, false)
	_sync()

func answer() -> Dictionary:
	return {"blanks": choices.duplicate()}

## The strike message's first words: which test failed, or that the program crashed.
func miss_text() -> String:
	return "A test failed!" if headline.is_empty() else headline

func retry_tip() -> String:
	return "Pick different lines and run it again."

## The program's lines, every blank's choices, and its labels, with the registers it shows (the pc
## among them), for the instruction guide.
func guide() -> Dictionary:
	var lines: Array = []
	for entry in payload.code:
		if entry.has("label"):
			lines.append(str(entry.label) + ":")
		else:
			lines.append_array(entry.get("blank", [entry.get("line", "")]))
	return {"lines": lines, "registers": chips.names}

func stars() -> int:
	return 3 - int(fails > 0) - int(hint_used)

func set_disabled(value: bool) -> void:
	disabled = value
	_close_list()
	_sync()

## Enter or Space runs the tests, Tab opens the next blank's list, and Escape closes it.
func handle_key(key: int) -> bool:
	if key == KEY_ESCAPE and bubble != null:
		_close_list()
		return true
	if _busy():
		return false
	if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and bubble == null and _filled():
		run_tests()
		return true
	if key == KEY_TAB and not options.is_empty():
		_open_list((last_list + 1) % options.size())
		return true
	return false

## Number keys pick a line from the open list, or open that blank's list.
func press(index: int) -> void:
	if _busy():
		return
	if bubble != null:
		if index < options[picking].size():
			_pick(picking, str(options[picking][index]))
	elif index < options.size():
		_open_list(index)

## Empties the blank filled last.
func undo() -> void:
	if _busy() or picked.is_empty():
		return
	Audio.play("undo")
	_set_choice(int(picked.pop_back()), "")

## Empties every blank.
func restart() -> void:
	if _busy() or picked.is_empty():
		return
	Audio.play("undo")
	for k in range(choices.size()):
		_set_choice(k, "")

func show_hint() -> void:
	if hint.is_empty() or hint_used:
		return
	hint_used = true
	Audio.play("hint", -4.0)
	hint_label.text = "Hint: " + hint
	hint_button.modulate = Color.WHITE
	_sync()

## The room is open: celebrate, and put the hint away to make room for the explanation.
func solved() -> void:
	locked = true
	view.celebrate()
	_sync()

## The server counted the run as a miss: the cards shake, and the lines stay for another try.
func failed() -> void:
	fails += 1
	cards.shake = 8.0
	locked = false
	_sync()
	if fails >= 2 and not hint_used and not hint.is_empty():
		hint_button.text = "Need a hint?"
		hint_button.modulate = Style.GOLD

## The attempt never reached the grader: back to how things were before the run.
func reset() -> void:
	locked = false
	playing = false
	cards.clear()
	_show_start(0)
	_sync()

## Runs every test in turn while the robot walks the program as the PC, then reports the attempt.
func run_tests() -> void:
	if _busy() or not _filled():
		return
	_close_list()
	playing = true
	headline = ""
	cards.clear()
	_sync()
	var tests: Array = payload.tests
	var passed := 0
	for k in range(tests.size()):
		var result := run(payload, choices, tests[k])
		_show_start(k)
		cards.running = k
		await view.get_tree().create_timer(0.35).timeout
		if not is_instance_valid(view):
			return
		await _play(result)
		if not is_instance_valid(view):
			return
		var ok := meets(tests[k], result)
		cards.running = -1
		cards.mark(k, ok, outcome(tests[k], result))
		if ok:
			passed += 1
			Audio.play("open", -12.0)
		else:
			if headline.is_empty():
				headline = "Test %d crashed!" % (k + 1) if not str(result.fault).is_empty() else "Test %d failed!" % (k + 1)
			if str(result.fault).is_empty():
				view.flash_message("TEST %d FAILED" % (k + 1), Style.RED)
		await view.get_tree().create_timer(0.7).timeout
		if not is_instance_valid(view):
			return
	if passed == tests.size():
		view.flash_message("ALL TESTS PASS", Style.GREEN)
	playing = false
	locked = true
	_sync()
	attempt.emit()

## Plays one test's run: the robot steps through the trace, and each instruction's result lands in
## a chip or a memory word. A long loop speeds up so a run takes a few seconds.
func _play(result: Dictionary) -> void:
	var steps: Array = result.trace
	if result.fault == "loop":
		steps = steps.slice(0, 40)  # Enough to see it spin.
	var duration := clampf(3.4 / maxf(steps.size(), 1.0), 0.12, 0.45)
	for step in steps:
		var pc := int(step.pc)
		view.running_row = view.row_of(pc)
		view.walk_to(pc, duration * 0.4)
		chips.set_value("pc", pc)
		await view.get_tree().create_timer(duration * 0.45).timeout
		if not is_instance_valid(view):
			return
		if step.get("crash", false):
			break
		if int(step.reg) > 0:
			chips.set_value(Registers.name(int(step.reg)), int(step.value))
			if int(step.reg) == 2:
				view.sp = int(step.value)
		if step.stored:
			view.set_word(int(step.address), int(step.value))
		elif int(step.address) >= 0:
			view.flash_word(int(step.address))
		if int(step.next) != pc + 4:
			view.jump(pc, int(step.next), Style.PURPLE if str(step.op) in BRANCHES else Style.CYAN)
		Audio.play("press", -16.0, 0.25)
		await view.get_tree().create_timer(duration * 0.55).timeout
		if not is_instance_valid(view):
			return
	view.running_row = -1
	if str(result.fault).is_empty():
		chips.set_value("pc", int(result.pc))
		view.walk_to(int(result.pc), 0.3)
		await view.get_tree().create_timer(0.35).timeout
		return
	if result.fault == "code":
		chips.set_value("pc", int(result.at))
	view.fault(fault_text(result))
	Audio.play("overflow", -4.0)
	await view.get_tree().create_timer(1.6).timeout

## Shows where test `k` starts: its registers, fresh memory, and the robot on the first instruction.
func _show_start(k: int, glide: bool = true) -> void:
	var start := begin(payload, payload.tests[k])
	chips.show_state({"regs": start.regs, "pc": CODE_BASE}, true)
	view.show_memory(start.memory, int(start.regs[2]))
	view.reset_run()
	view.walk_to(CODE_BASE, 0.25 if glide else 0.0)

## A click on a blank opens its list (or closes it, if it's open); a click anywhere else closes it.
func _on_blank_clicked(blank: int) -> void:
	if blank < 0 or blank == picking:
		_close_list()
	else:
		_open_list(blank)

## Opens a blank's list of lines beside the code, level with the blank.
func _open_list(blank: int) -> void:
	_close_list()
	if _busy():
		return
	picking = blank
	last_list = blank
	view.open_blank = blank
	bubble = PanelContainer.new()
	var look := Style.panel_style()
	look.set_content_margin_all(6)
	look.border_color = Style.GOLD
	bubble.add_theme_stylebox_override("panel", look)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	bubble.add_child(column)
	var heading := Label.new()
	heading.text = "The line at 0x%X:" % _blank_address(blank)
	heading.add_theme_font_override("font", Style.MONO)
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Style.GOLD)
	column.add_child(heading)
	for i in range(options[blank].size()):
		var line := str(options[blank][i])
		var color := Style.CYAN if line == choices[blank] else Style.GOLD
		var button := Button.new()
		button.custom_minimum_size = Vector2(250, 30)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for look_state in ["normal", "hover", "pressed", "disabled"]:
			var key_look := Style.key_style(color, look_state)
			key_look.set_content_margin_all(4)
			key_look.border_width_bottom = 2 if look_state == "pressed" else 3
			button.add_theme_stylebox_override(look_state, key_look)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.offset_right = -10
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for part in [[str(i + 1), 11, Color(Style.TEXT, 0.45)], [line, 14, Style.TEXT]]:
			var label := Label.new()
			label.text = part[0]
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.size_flags_vertical = Control.SIZE_FILL
			label.add_theme_font_override("font", Style.MONO)
			label.add_theme_font_size_override("font_size", part[1])
			label.add_theme_color_override("font_color", part[2])
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(label)
		button.add_child(row)
		button.pressed.connect(_pick.bind(blank, line))
		column.add_child(button)
	view.add_child(bubble)
	bubble.reset_size()
	var rect: Rect2 = view.blank_rect(blank)
	var place := Vector2(rect.end.x - 30, rect.position.y - 26)
	place.x = clampf(place.x, 0.0, maxf(view.size.x - bubble.size.x, 0.0))
	place.y = clampf(place.y, 0.0, maxf(view.size.y - bubble.size.y, 0.0))
	bubble.position = place
	Audio.play("press", -10.0)

func _close_list() -> void:
	if bubble != null and is_instance_valid(bubble):
		bubble.queue_free()
	bubble = null
	picking = -1
	view.open_blank = -1

func _pick(blank: int, line: String) -> void:
	_close_list()
	if _busy():
		return
	Audio.play("press", -4.0, 0.1)
	picked.erase(blank)
	picked.append(blank)
	_set_choice(blank, line)

## Fills (or empties) a blank. The program changed, so the last run's results no longer apply.
func _set_choice(blank: int, line: String) -> void:
	choices[blank] = line
	view.choices[blank] = line
	if line.is_empty():
		picked.erase(blank)
	cards.clear()
	_show_start(0)
	_sync()

func _blank_address(blank: int) -> int:
	var address := CODE_BASE
	var k := 0
	for entry in payload.code:
		if entry.has("blank"):
			if k == blank:
				return address
			k += 1
		if not entry.has("label"):
			address += 4
	return address

func _sync() -> void:
	var off := _busy()
	view.editable = not off
	run_button.disabled = off or not _filled()
	var count: int = payload.tests.size()
	run_button.text = "Running…" if playing else "Pick a line for every blank" if not _filled() \
		else "Run ▶" if count == 1 else "Run all %d tests ▶" % count
	clear_button.disabled = off or picked.is_empty()
	hint_button.disabled = disabled or locked or hint_used or hint.is_empty()
	# The hint steps aside while the robot walks the code, and once the gate opens.
	hint_label.get_parent().visible = hint_used and not playing and not locked

func _busy() -> bool:
	return locked or playing or disabled

func _filled() -> bool:
	return not choices.has("")

## The chips: the pc (the robot), then every register the program or its tests use, in register
## order, captioned with the C variable each one holds.
func _setup_chips() -> void:
	var used := {}
	for entry in payload.code:
		for line in entry.get("blank", [entry.get("line", "")]):
			if str(line).is_empty():
				continue
			var ins := Assembly.parse(str(line))
			for field in ["rd", "rs1", "rs2"]:
				if ins.has(field) and int(ins[field]) != 0:
					used[int(ins[field])] = true
	for name in payload.get("registers", {}):
		used[Registers.number(str(name))] = true
	for test in payload.tests:
		for name in test.get("registers", {}).keys() + test.expect.get("registers", {}).keys():
			used[Registers.number(str(name))] = true
	var numbers: Array = used.keys()
	numbers.sort()
	var names: Array = ["pc"]
	for number in numbers:
		names.append(Registers.name(int(number)))
	chips.names = names
	chips.per_row = 4
	chips.address_floor = CODE_BASE
	chips.pointers = ["pc", "ra", "sp"]
	var nicknames: Dictionary = payload.get("names", {})
	for name in names:
		chips.captions[name] = "robot" if name == "pc" else nicknames.get(name, {"ra": "return", "sp": "stack"}.get(name, ""))
	chips.fit()

## Each test as its card says it: the inputs it starts with, then what it expects.
func _test_lines() -> Array:
	var lines: Array = []
	for test in payload.tests:
		var given: Array = []
		var registers: Dictionary = test.get("registers", {})
		for name in registers:
			var value = registers[name]
			given.append("%s = %s" % [name, str(value) if value is String else Assembly.word_text(int(value))])
		var wants: Array = []
		for item in _checks(test.expect):
			wants.append(_say(item, item.want))
		if test.expect.get("returned", false):
			wants.append("returns")
		var expected := "expect " + ", ".join(PackedStringArray(wants))
		lines.append(expected if given.is_empty() else "given %s, %s" % [", ".join(PackedStringArray(given)), expected])
	return lines

func _tool(text: String, action: Callable, shortcut: String) -> Button:
	var tool := Button.new()
	tool.text = text
	tool.tooltip_text = shortcut
	tool.custom_minimum_size = Vector2(80, 44)
	tool.add_theme_font_size_override("font_size", 14)
	tool.focus_mode = Control.FOCUS_NONE
	tool.pressed.connect(action)
	return tool

## What a test checks, in its card's order: data words (an array's together), then registers.
static func _checks(expect: Dictionary) -> Array:
	var items: Array = []
	var groups := {}
	var memory: Dictionary = expect.get("memory", {})
	for where in memory:
		var label := str(where).get_slice("[", 0)
		if not groups.has(label):
			groups[label] = {"name": label, "words": [], "want": []}
			items.append(groups[label])
		groups[label].words.append(str(where))
		groups[label].want.append(int(memory[where]) & MASK)
	for item in items:
		if item.words.size() == 1:
			item.name = item.words[0]
	var registers: Dictionary = expect.get("registers", {})
	for name in registers:
		items.append({"name": str(name), "register": str(name), "want": [int(registers[name]) & MASK]})
	return items

static func _actual(item: Dictionary, result: Dictionary) -> Array:
	if item.has("register"):
		return [int(result.regs[Registers.number(item.register)])]
	var values: Array = []
	for where in item.words:
		values.append(int(result.memory.get(word_address(result.labels, where), 0)))
	return values

static func _say(item: Dictionary, values: Array) -> String:
	var shown: Array = []
	for value in values:
		shown.append(Assembly.word_text(int(value)))
	return "%s = %s" % [item.name, shown[0] if shown.size() == 1 else "{%s}" % ", ".join(PackedStringArray(shown))]

## A test card's second line after a run: what the checked values came out as (only the wrong ones
## when it failed), or why the program crashed.
static func outcome(test: Dictionary, result: Dictionary) -> String:
	if not str(result.fault).is_empty():
		return "crashed: " + fault_text(result, true)
	var passed := meets(test, result)
	var got: Array = []
	for item in _checks(test.expect):
		var values := _actual(item, result)
		if passed or values != item.want:
			got.append(_say(item, values))
	var text := "" if got.is_empty() else "got " + ", ".join(PackedStringArray(got))
	if test.expect.get("returned", false) and int(result.pc) != EXIT:
		text += ("; " if not text.is_empty() else "") + "never returned to the OS"
	return text

static func fault_text(result: Dictionary, short := false) -> String:
	var text: String = FAULTS[result.fault][int(short)]
	return text % ("0x%X" % int(result.at)) if text.contains("%s") else text

## Each blank's lines, in program order. Mirrors code_blanks in server/puzzles.py.
static func blanks(room: Dictionary) -> Array:
	var lists: Array = []
	for entry in room.code:
		if entry.has("blank"):
			lists.append(entry.blank)
	return lists

## The program with its blanks filled: its lines (from CODE_BASE, 4 bytes apart) and each label's
## address. Mirrors assemble.
static func assemble(room: Dictionary, chosen: Array) -> Dictionary:
	var lines: Array = []
	var labels := {}
	var pick := 0
	for entry in room.code:
		if entry.has("label"):
			labels[str(entry.label)] = CODE_BASE + 4 * lines.size()
		elif entry.has("line"):
			lines.append(str(entry.line))
		else:
			lines.append(str(chosen[pick]))
			pick += 1
	return {"lines": lines, "labels": labels}

## The room's memory: its data blocks laid out from data.base (each label marks its first word),
## plus the stack's words below stack.top, which hold junk until something is saved. Mirrors
## data_layout.
static func data_layout(room: Dictionary) -> Dictionary:
	var memory := {}
	var labels := {}
	if room.has("data"):
		var address := int(room.data.base)
		for block in room.data.blocks:
			labels[str(block.label)] = address
			for word in block.words:
				memory[address] = int(word) & MASK
				address += 4
	if room.has("stack"):
		for k in range(1, int(room.stack.words) + 1):
			memory[int(room.stack.top) - 4 * k] = Assembly.JUNK
	return {"memory": memory, "labels": labels}

## Where a test starts: ra at EXIT (main's caller), sp at the top of the stack, then the room's and
## the test's registers, where a label's name stands for its address.
static func begin(room: Dictionary, test: Dictionary) -> Dictionary:
	var layout := data_layout(room)
	var regs: Array = []
	regs.resize(32)
	regs.fill(0)
	regs[1] = EXIT
	if room.has("stack"):
		regs[2] = int(room.stack.top)
	var given: Dictionary = room.get("registers", {}).duplicate()
	given.merge(test.get("registers", {}), true)
	for name in given:
		var value = given[name]
		regs[Registers.number(str(name))] = (int(layout.labels[value]) if value is String else int(value)) & MASK
	return {"regs": regs, "memory": layout.memory, "labels": layout.labels}

## Runs the program on one test. Returns its registers, memory, data labels, and final PC, the trace
## of every instruction it ran (for the animation), and, if it crashed, why ("fault": a key of
## FAULTS) and the address it couldn't use ("at"). The program ends when it returns to EXIT or runs past its last line.
## Mirrors run_code.
static func run(room: Dictionary, chosen: Array, test: Dictionary) -> Dictionary:
	var built := assemble(room, chosen)
	var program: Array = []
	for line in built.lines:
		program.append(Assembly.parse(line))
	var code_labels: Dictionary = built.labels
	var start := begin(room, test)
	var regs: Array = start.regs
	var memory: Dictionary = start.memory
	var data_labels: Dictionary = start.labels
	var result := {"regs": regs, "memory": memory, "labels": data_labels, "pc": CODE_BASE, "trace": [], "fault": "",
		"at": 0}
	var last := CODE_BASE + 4 * program.size()
	var pc := CODE_BASE
	var steps := 0
	while pc != EXIT and pc != last:
		if pc % 4 != 0 or pc < CODE_BASE or pc >= last:
			result.fault = "code"
			result.at = pc
			break
		steps += 1
		if steps > STEP_LIMIT:
			result.fault = "loop"
			break
		var ins: Dictionary = program[(pc - CODE_BASE) / 4]
		var op := str(ins.op)
		var step := {"pc": pc, "op": op, "next": pc + 4, "reg": -1, "value": 0, "address": -1, "stored": false}
		if op in BRANCHES:
			if Assembly.branch_taken(op, regs[int(ins.rs1)], regs[int(ins.rs2)]):
				step.next = int(code_labels[ins.target])
		elif op == "jal":
			step.next = int(code_labels[ins.target])
			_write(regs, step, int(ins.rd), pc + 4)
		elif op == "jalr":
			step.next = (int(regs[int(ins.rs1)]) + int(ins.imm)) & MASK & ~1
			_write(regs, step, int(ins.rd), pc + 4)
		elif op == "la":
			_write(regs, step, int(ins.rd), int(data_labels[ins.target]))
		elif op == "lw" or op == "sw":
			var address: int = (int(regs[int(ins.rs1)]) + int(ins.imm)) & MASK
			step.address = address
			if not memory.has(address):
				step.crash = true
				result.trace.append(step)
				result.fault = "memory" if address % 4 == 0 else "aligned"
				result.at = address
				break
			if op == "sw":
				memory[address] = regs[int(ins.rs2)]
				step.stored = true
				step.value = memory[address]
			else:
				_write(regs, step, int(ins.rd), int(memory[address]))
		else:
			var second: int = regs[int(ins.rs2)] if ins.has("rs2") else int(ins.imm) & MASK
			_write(regs, step, int(ins.rd), PuzzleRoom.execute(op, regs[int(ins.rs1)], second, 32))
		result.trace.append(step)
		pc = int(step.next)
	result.pc = pc
	return result

## Writes a register the way the hardware does: writes to x0 vanish.
static func _write(regs: Array, step: Dictionary, rd: int, value: int) -> void:
	if rd != 0:
		regs[rd] = value & MASK
		step.reg = rd
		step.value = regs[rd]

## A data word named like arr[2] (or just result, for its first word). Mirrors word_address.
static func word_address(labels: Dictionary, where: String) -> int:
	var index := 0
	if where.ends_with("]"):
		index = int(where.get_slice("[", 1).trim_suffix("]"))
	return int(labels[where.get_slice("[", 0)]) + 4 * index

## Whether a run did what its test expects. Mirrors code_passes.
static func meets(test: Dictionary, result: Dictionary) -> bool:
	if not str(result.fault).is_empty():
		return false
	var expect: Dictionary = test.expect
	var registers: Dictionary = expect.get("registers", {})
	for name in registers:
		if int(result.regs[Registers.number(str(name))]) != int(registers[name]) & MASK:
			return false
	var memory: Dictionary = expect.get("memory", {})
	for where in memory:
		var address := word_address(result.labels, str(where))
		if not result.memory.has(address) or int(result.memory[address]) != int(memory[where]) & MASK:
			return false
	return not expect.get("returned", false) or int(result.pc) == EXIT

## Mirrors grade_code in server/puzzles.py for guest mode, where the game grades itself.
static func grade(room: Dictionary, response: Dictionary) -> bool:
	var chosen = response.get("blanks")
	var lists := blanks(room)
	if not (chosen is Array) or chosen.size() != lists.size():
		return false
	for k in range(lists.size()):
		if not (chosen[k] is String) or chosen[k] not in lists[k]:
			return false
	for test in room.tests:
		if not meets(test, run(room, chosen, test)):
			return false
	return true
