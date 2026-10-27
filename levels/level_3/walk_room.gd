extends "res://levels/level_3/tower_room.gd"
## A walkthrough: a short program the student follows line by line. The listing lights the line
## that just ran, the tower shows the stack (a floor per call, the robot riding sp), the chips
## above the code show the registers the room watches, and the side panel says what the line did,
## with its values. Play runs it by itself, leaving each line up long enough to read its caption;
## Step and Back move a line at a time.
##
## At each of its moments the walk stops for the student's move (a call, a stack frame, where to
## keep a value, a base case): the side panel shows a bank of code blocks, one per option, and the
## student drags one into the gold slot in the listing. A good move is written into the program and
## the walk goes on. A wrong one plays out on the tower, shows what broke and why, and rewinds: it
## costs a star, never a strike. When the program gets back to the Chomper with the contract kept,
## the moves made are the attempt.

const MazeVisuals := preload("res://levels/level_2/maze_visuals.gd")
## How long Play leaves a line up: a base, plus time for every character of its caption and note,
## within a floor and a cap. A line already read on a floor above stays up for about half as long.
const READ_BASE := 1.2
const READ_PER_CHARACTER := 0.04
const READ_LEAST := 2.2
const READ_MOST := 7.0
const READ_AGAIN := 0.5
const QUICK := 0.2  ## The same, while a wrong move plays out.
const SHOWN := 45  ## Lines of a wrong move played out before it jumps to how it ended.
const CAPTIONS := {"a0": "arg", "ra": "way back", "sp": "stack", "s0": "kept", "s1": "kept", "t0": "temp"}

var choices: Array = []  # The option picked at each moment; -1 until the move is made.
var order: Array = []  # Each moment's options in the order its bank shows them, shuffled once per room.
var walk := {}  # The program with the moves made so far, run until the next move or the end, and
                # how many of its lines ("at") have run on screen.
var trying := {}  # A wrong move playing out: its moment, option, program, run, "at", and "done".
var view := {}  # What's on screen: the walk, or a wrong move playing out.
var auto := false
var generation := 0  # Bumped to stop a play loop that's waiting on its timer.
var finished := false
var revealed := false  # Past the walk's last line to its move or the Chomper's check. Until then that
                       # line's caption stays up (and a walk whose first move comes before any line
                       # shows its intro).
var cheer := ""  # What a good move did, shown with the next line.
var chips
var story: PanelContainer
var header: Label
var line_label: Label
var body: Label
var note_label: Label
var bank: HFlowContainer  # The move's blocks, waiting to be dragged into the slot.
var rewind_button: Button
var read_bar: ProgressBar  # While Play runs: fills over the time the line stays up.
var read_tween: Tween
var progress: Label
var back_button: Button
var step_button: Button
var restart_button: Button

func _build_controls() -> void:
	for entry in CallMachine.moments(payload):
		choices.append(-1)
		var shown: Array = range(entry.options.size())
		shown.shuffle()  # Otherwise the good block would usually come first, as it's written first.
		order.append(shown)
	listing.move_dropped.connect(_on_drop)
	listing.drag_ended.connect(_on_drag_ended)
	# The registers the room watches sit above the code.
	var main: Node = listing.get_parent()
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.2
	column.add_theme_constant_override("separation", 6)
	main.add_child(column)
	main.move_child(column, 0)
	chips = MazeVisuals.RegisterChips.new()
	chips.names = payload.watch
	chips.pointers = ["ra", "sp"]
	chips.address_floor = 0x5A00  # The Chomper's junk reads as hex; the room's numbers stay decimal.
	for name in payload.watch:
		chips.captions[name] = CAPTIONS.get(str(name), "")
	column.add_child(chips)
	main.remove_child(listing)
	listing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(listing)
	side.add_child(_step(1, "Press Play, or Step one line at a time"))
	story = PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0, 0, 0, 0.28)
	look.border_color = Color(Style.CYAN, 0.35)
	look.set_border_width_all(1)
	look.set_corner_radius_all(10)
	look.set_content_margin_all(10)
	story.add_theme_stylebox_override("panel", look)
	story.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(story)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 4)
	story.add_child(words)
	header = _label(11, Color(Style.TEXT, 0.5))
	line_label = _label(14, Style.GOLD)
	line_label.add_theme_font_override("font", Style.MONO)
	body = _label(14, Style.TEXT)
	note_label = _label(13, Style.CYAN.lightened(0.3))
	bank = HFlowContainer.new()  # Three blocks fit a row, which keeps the controls under it on screen.
	bank.add_theme_constant_override("h_separation", 4)
	bank.add_theme_constant_override("v_separation", 4)
	rewind_button = Button.new()
	rewind_button.text = "Rewind and try again"
	rewind_button.focus_mode = Control.FOCUS_NONE
	rewind_button.add_theme_font_size_override("font_size", 14)
	_compact(rewind_button)
	rewind_button.pressed.connect(_rewind)
	for part in [header, line_label, body, note_label, bank, rewind_button]:
		words.add_child(part)
	# Along the box's bottom, the bar that fills until Play moves to the next line.
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	words.add_child(push)
	read_bar = ProgressBar.new()
	read_bar.show_percentage = false
	read_bar.max_value = 1.0
	read_bar.step = 0.0
	read_bar.custom_minimum_size = Vector2(0, 6)
	read_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in [["background", Color(Style.TEXT, 0.1)], ["fill", Style.CYAN]]:
		var bar_look := StyleBoxFlat.new()
		bar_look.bg_color = part[1]
		bar_look.set_corner_radius_all(3)
		read_bar.add_theme_stylebox_override(part[0], bar_look)
	read_bar.hide()
	words.add_child(read_bar)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _last_step() -> Control:
	progress = _label(12, Color(Style.TEXT, 0.55))
	return progress

func _add_tools() -> void:
	back_button = _tool("◀ Back", back, "Left arrow")
	step_button = _tool("Step ▶", step_forward, "Right arrow")
	restart_button = _tool("Restart", restart, "R")
	for tool in [back_button, step_button, restart_button]:
		tools.add_child(tool)
	run_button.tooltip_text = "Space"

# ---- The walk ---------------------------------------------------------------------------------

func _show_start() -> void:
	finished = false
	revealed = false
	trying = {}
	_rebuild()
	walk.at = 0
	view = walk
	listing.show_program(walk.built)
	_show()

## Assembles the program with the moves made so far and runs it until the next move or the end.
func _rebuild() -> void:
	var built := CallMachine.assemble(payload, [], choices)
	walk = {"built": built, "state": CallMachine.run(payload, built.lines, built.labels, 0, built.stops),
		"at": int(walk.get("at", 0))}

## The tower, stack, and registers after the first `count` lines of a run.
func _model_at(state: Dictionary, count: int) -> Dictionary:
	var start := CallMachine.setup(payload, 0)
	var model := {"memory": start.memory, "labels": {}, "open": [state.calls[0]], "sp": STACK_TOP,
		"heap": CallMachine.heap_line(payload, 0), "regs": start.regs}
	for k in range(count):
		var step: Dictionary = state.trace[k]
		_apply(model, step)
		if int(step.reg) >= 0:
			model.regs[int(step.reg)] = int(step.value)
	return model

func _waiting() -> bool:
	return revealed and trying.is_empty() and int(walk.at) == walk.state.trace.size() and int(walk.state.paused) >= 0

## Past the last line of a walk that's done: the Chomper checks it.
func _ending() -> bool:
	return revealed and trying.is_empty() and int(walk.at) == walk.state.trace.size() and int(walk.state.paused) < 0

## Whether Step (or Play) has anything left to show: a line, or the move or check after the last one.
func _more() -> bool:
	return trying.is_empty() and (int(walk.at) < walk.state.trace.size() or not revealed)

func _broke() -> bool:
	return not trying.is_empty() and trying.done

## Moves on a line. Past the last one, it shows the move (or the Chomper's check) and returns false.
func _advance() -> bool:
	if int(view.at) >= view.state.trace.size():
		if trying.is_empty() and not revealed:
			revealed = true
			_show()
		return false
	view.at = int(view.at) + 1
	var step: Dictionary = view.state.trace[int(view.at) - 1]
	if not step.call.is_empty():
		Audio.play("press", -10.0, 0.15)
	elif step.returned:
		Audio.play("press", -12.0, 0.3)
	_show()
	return true

func run_room() -> void:
	if auto:
		_pause()
	else:
		_play_walk()

func _play_walk() -> void:
	if disabled or locked or not _more():
		return
	auto = true
	generation += 1
	var mine := generation
	_sync()
	while auto and mine == generation:
		if not _advance():
			break
		var seconds := _reading_time()
		_run_bar(seconds)
		await tower.get_tree().create_timer(seconds).timeout
		if not is_instance_valid(tower):
			return
	if mine == generation:
		auto = false
		_stop_bar()
		_show()

func _pause() -> void:
	auto = false
	generation += 1
	_stop_bar()
	_sync()

## Fills the bar over the `seconds` before Play moves on.
func _run_bar(seconds: float) -> void:
	if read_tween:
		read_tween.kill()
	read_bar.value = 0.0
	read_bar.show()
	read_tween = read_bar.create_tween()
	read_tween.tween_property(read_bar, "value", 1.0, seconds)

func _stop_bar() -> void:
	if read_tween:
		read_tween.kill()
	read_bar.value = 0.0
	read_bar.hide()

## Seconds to leave what's on screen up while playing: enough to read it.
func _reading_time() -> float:
	var characters := body.text.length()
	if line_label.visible:
		characters += line_label.text.length()
	if note_label.visible:
		characters += note_label.text.length()
	var seconds := clampf(READ_BASE + READ_PER_CHARACTER * characters, READ_LEAST, READ_MOST)
	var at := int(view.at)
	if at > 0 and not note_label.visible and not _first_run(view.state.trace, at - 1):
		seconds = maxf(READ_LEAST * 0.8, seconds * READ_AGAIN)
	return seconds

func step_forward() -> void:
	if disabled or locked or not trying.is_empty():
		return
	_pause()
	_advance()

## Backspace and the Left arrow step back a line (from a move, back to the line before it).
func back() -> void:
	if disabled or locked or not trying.is_empty() or (int(walk.at) == 0 and not revealed):
		return
	_pause()
	if revealed and int(walk.at) == walk.state.trace.size():
		revealed = false
	else:
		walk.at = int(walk.at) - 1
		revealed = false
	_show()

func undo() -> void:
	back()

func restart() -> void:
	if disabled or locked or not trying.is_empty() or (int(walk.at) == 0 and not revealed):
		return
	_pause()
	walk.at = 0
	revealed = false
	_show()

## Number keys make the move on the bank's block of that number (the keyboard's way to drag it in);
## when a wrong move has played out, any of them rewinds.
func press(index: int) -> void:
	if disabled or locked:
		return
	if _waiting():
		var shown: Array = order[int(walk.state.paused)]
		if index < shown.size():
			_choose(int(shown[index]))
	elif _broke():
		_rewind()
	elif int(walk.at) >= walk.state.trace.size() and _more():
		_advance()

## Space plays or pauses (or rewinds after a wrong move), and the arrows step.
func handle_key(key: int) -> bool:
	if disabled or locked:
		return false
	match key:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if _broke():
				_rewind()
			else:
				run_room()
			return true
		KEY_RIGHT:
			step_forward()
			return true
		KEY_LEFT:
			back()
			return true
	return false

func _choose(k: int) -> void:
	var m := int(walk.state.paused)
	var entry: Dictionary = CallMachine.moments(payload)[m]
	if k < 0 or k >= entry.options.size():
		return
	var option: Dictionary = entry.options[k]
	if bool(option.good):
		Audio.play("press", -4.0, 0.1)
		choices[m] = k
		cheer = str(option.why)
		revealed = false
		var at := int(walk.at)
		_rebuild()
		walk.at = at
		view = walk
		listing.show_program(walk.built)
		_show()
		return
	# A wrong move: the other moves not made yet go the good way, so what breaks is this move's doing.
	fails += 1
	var picks := choices.duplicate()
	picks[m] = k
	for j in range(picks.size()):
		if int(picks[j]) < 0:
			picks[j] = _good_option(j)
	var built := CallMachine.assemble(payload, [], picks)
	trying = {"moment": m, "option": option, "picks": picks, "built": built, "at": int(walk.at), "done": false,
		"state": CallMachine.run(payload, built.lines, built.labels, 0)}
	view = trying
	listing.show_program(built)
	# The wrong move's own lines glow red where they went in.
	var stop: int = walk.state.trace.size()
	var address: int = int(walk.state.trace[stop - 1].next) if stop > 0 else int(built.labels[str(payload.entry)])
	for i in range(built.lines.size()):
		if str(built.parts[i]) != "body" and CallMachine.CODE_BASE + 4 * i >= address:
			listing.marks[CallMachine.CODE_BASE + 4 * i] = Style.RED
	Audio.play("undo", -6.0)
	_play_out()

func _good_option(m: int) -> int:
	var options: Array = CallMachine.moments(payload)[m].options
	for k in range(options.size()):
		if bool(options[k].good):
			return k
	return 0

## The wrong move runs at a quicker pace (a long one jumps to how it ended), then says what broke.
func _play_out() -> void:
	_pause()
	var mine := generation
	var trace: Array = trying.state.trace
	var limit := mini(trace.size(), int(trying.at) + SHOWN)
	_show()
	while not trying.is_empty() and int(trying.at) < limit and mine == generation:
		await tower.get_tree().create_timer(QUICK).timeout
		if not is_instance_valid(tower) or trying.is_empty() or mine != generation:
			return
		trying.at = int(trying.at) + 1
		_show()
	if trying.is_empty() or mine != generation:
		return
	trying.at = trace.size()
	trying.done = true
	_show()
	if not trying.state.fault.is_empty():
		tower.fault(_fault_text(trying.state.fault, 0))
	else:
		tower.flash_message("THE CONTRACT BROKE", Style.RED)  # The side panel says how.
	Audio.play("overflow", -4.0)

func _rewind() -> void:
	if trying.is_empty():
		return
	trying = {}
	view = walk
	listing.marks.clear()
	listing.show_program(walk.built)
	tower.message_alpha = 0.0
	Audio.play("undo")
	_show()

## The program got back to the Chomper: it checks the contract, and the moves made are the attempt.
func _finish() -> void:
	if finished:
		return
	finished = true
	auto = false
	_stop_bar()
	var row: Dictionary = CallMachine.audit(payload, [], choices)[0]
	if row.passed:
		locked = true
		_sync()
		attempt.emit()

func answer() -> Dictionary:
	return {"choices": choices.duplicate()}

## A good move that's bigger than it needs to be (the finale's roomy frame) costs a star.
func _star_penalty() -> int:
	var entries := CallMachine.moments(payload)
	for m in range(entries.size()):
		if int(choices[m]) >= 0 and bool(entries[m].options[int(choices[m])].get("loose", false)):
			return 1
	return 0

func failed() -> void:
	super.failed()
	finished = false

## Every line the walk can run, its moves included, for the instruction guide.
func guide() -> Dictionary:
	var lines: Array = []
	for entry in payload.code:
		if entry.has("label"):
			lines.append(str(entry.label) + ":")
		elif entry.has("line"):
			lines.append(str(entry.line))
		elif entry.has("moment"):
			for option in entry.options:
				if option.has("lines"):
					lines.append_array(option.lines)
				else:
					var written := CallMachine.frame_lines(option.frame)
					lines.append_array(written[0] + written[1])
	return {"lines": lines}

# ---- What's on screen -------------------------------------------------------------------------

func _show() -> void:
	var built: Dictionary = view.built
	var state: Dictionary = view.state
	var at := int(view.at)
	var trace: Array = state.trace
	var model := _model_at(state, at)
	_show_model(model)
	chips.show_state(model, at > 0)
	listing.running = int(trace[at - 1].pc) if at > 0 else -1
	listing.waiting = int(state.paused) if _waiting() else -1
	listing.queue_redraw()
	header.add_theme_color_override("font_color", Color(Style.TEXT, 0.5))
	for block in bank.get_children():
		bank.remove_child(block)
		block.queue_free()
	line_label.hide()
	note_label.hide()
	rewind_button.hide()
	if _broke():
		header.text = "THAT MOVE BROKE IT"
		header.add_theme_color_override("font_color", Style.RED)
		line_label.text = _fault_text(state.fault, 0) if not state.fault.is_empty() \
			else _detail(CallMachine.audit(payload, [], trying.picks)[0])
		line_label.show()
		body.text = str(trying.option.why)
		rewind_button.show()
	elif _waiting():
		var m := int(state.paused)
		var entry: Dictionary = CallMachine.moments(payload)[m]
		header.text = "YOUR MOVE  ·  DRAG A BLOCK INTO THE GOLD SLOT"
		header.add_theme_color_override("font_color", Style.GOLD)
		body.text = str(entry.ask)
		listing.drop_note = "the matching epilogue goes in before the return" if str(entry.moment) == "frame" else ""
		for place in range(order[m].size()):
			bank.add_child(_block(m, int(order[m][place]), place))
	elif _ending():
		header.text = "THE CHOMPER CHECKS"
		header.add_theme_color_override("font_color", Style.GREEN)
		var row: Dictionary = CallMachine.audit(payload, [], choices)[0]
		body.text = _verdict(row)
		_finish.call_deferred()
	elif at == 0:
		header.text = "WHAT'S HAPPENING"
		body.text = str(payload.intro)
	else:
		var step: Dictionary = trace[at - 1]
		var index := (int(step.pc) - CallMachine.CODE_BASE) / 4
		var text: String = built.lines[index]
		header.text = "WHAT'S HAPPENING" if trying.is_empty() else "PLAYING OUT YOUR MOVE"
		if not trying.is_empty():
			header.add_theme_color_override("font_color", Style.RED.lightened(0.2))
		line_label.text = text
		line_label.show()
		body.text = _caption(text, step, _model_at(state, at - 1).regs, built.labels)
		var note := ""
		if not cheer.is_empty() and trying.is_empty():
			note = cheer
			cheer = ""
		elif built.notes.has(index) and _first_run(trace, at - 1):
			note = str(built.notes[index])
		note_label.text = note
		note_label.visible = not note.is_empty()
	if _waiting():
		progress.text = "your move" if at == 0 else "line %d of %d  ·  your move" % [at, trace.size()]
	else:
		progress.text = "line %d of %d%s" % [at, trace.size(),
			"  ·  your move next" if trying.is_empty() and state.paused >= 0 else ""]
	_sync()

## Option k's block in moment m's bank, numbered by its place there (its key). It's dragged into the
## slot; a click that doesn't drag it only flashes the slot.
func _block(m: int, k: int, place: int) -> PanelContainer:
	var block := _block_face(CallMachine.moments(payload)[m].options[k], place)
	block.mouse_filter = Control.MOUSE_FILTER_STOP
	block.tooltip_text = "Drag into the gold slot (key %d)" % (place + 1)
	block.set_drag_forwarding(_drag_block.bind(m, k, place, block), Callable(), Callable())
	block.gui_input.connect(_on_block_input)
	return block

## How a block looks, in the bank and in the hand: its number, then the code the option writes in
## the blue the listing writes moves in (a frame's is its prologue), or "(add nothing)" in a dashed
## outline like an empty slot.
func _block_face(option: Dictionary, place: int) -> PanelContainer:
	var written: Array = option.lines if option.has("lines") else CallMachine.frame_lines(option.frame)[0]
	var block := PanelContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var look := StyleBoxFlat.new()
	look.bg_color = Color(0, 0, 0, 0.18) if written.is_empty() else Color("161d2a")
	look.border_color = Color(Style.CYAN, 0.55)
	look.set_border_width_all(0 if written.is_empty() else 1)
	look.set_corner_radius_all(6)
	look.set_content_margin_all(6)
	look.content_margin_top = 2
	block.add_theme_stylebox_override("panel", look)
	if written.is_empty():
		block.draw.connect(func(): Style.dashed_box(block, Rect2(Vector2.ONE, block.size - Vector2(2, 2)),
			Color(Style.TEXT, 0.4), 1.5, 5.0))
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_constant_override("separation", 0)
	block.add_child(words)
	var key := Label.new()
	key.text = str(place + 1)
	key.add_theme_font_size_override("font_size", 10)
	key.add_theme_color_override("font_color", Color(Style.TEXT, 0.45))
	words.add_child(key)
	var code := Label.new()
	code.text = "(add nothing)" if written.is_empty() \
		else "\n".join(PackedStringArray(written.map(func(line): return str(line))))
	code.add_theme_font_override("font", Style.MONO)
	code.add_theme_font_size_override("font_size", 12)
	code.add_theme_constant_override("line_spacing", 0)
	code.add_theme_color_override("font_color", Color(Style.TEXT, 0.55) if written.is_empty() else Style.CYAN.lightened(0.35))
	words.add_child(code)
	return block

## Picks a block up: the drag carries its move, a copy follows the mouse, and the block left in the
## bank fades until the drag ends.
func _drag_block(at_position: Vector2, m: int, k: int, place: int, block: Control) -> Variant:
	if disabled or locked or not _waiting():
		return null
	var copy := _block_face(CallMachine.moments(payload)[m].options[k], place)
	copy.custom_minimum_size = block.size
	copy.position = -at_position
	var hand := Control.new()
	hand.add_child(copy)
	block.set_drag_preview(hand)
	block.modulate.a = 0.3
	Audio.play("press", -12.0, 0.2)
	return {"move": k, "moment": m}

func _on_block_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_nudge()

## A block landed in the slot: that's the move.
func _on_drop(k: int) -> void:
	if not disabled and not locked and _waiting():
		_choose(k)

## A block let go anywhere else goes back to the bank, and the slot flashes to show where it belongs.
func _on_drag_ended(dropped: bool) -> void:
	_sync()
	if not dropped and _waiting():
		_nudge()

func _nudge() -> void:
	listing.create_tween().tween_property(listing, "nudge", 0.0, 0.9).from(1.0)

## Whether the step at `k` is the first time its line runs (a line's note shows only then).
func _first_run(trace: Array, k: int) -> bool:
	for j in range(k):
		if int(trace[j].pc) == int(trace[k].pc):
			return false
	return true

func _verdict(row: Dictionary) -> String:
	var call: Dictionary = payload.calls[0]
	var regs: Array = row.state.regs
	var kept: bool = not row.problems.any(func(problem): return str(problem) != "value" and str(problem) != "sp")
	return "%s returned %s %s   ·   s0–s11 kept %s   ·   sp back at 0x%X %s" % [
		_call_title(str(payload.entry), call.get("args", {})), _number(int(regs[10])),
		"✓" if not "value" in row.problems else "✗ (wanted %s)" % _number(int(call.expect)),
		"✓" if kept else "✗", STACK_TOP, "✓" if not "sp" in row.problems else "✗"]

func _sync() -> void:
	if view.is_empty():
		return
	var stuck := disabled or locked or not trying.is_empty()
	var more := _more()
	var home: bool = int(view.at) == 0 and not revealed
	run_button.text = "Pause" if auto else "▶ Play"
	run_button.disabled = stuck or (not more and not auto)
	step_button.disabled = stuck or not more
	back_button.disabled = stuck or home
	restart_button.disabled = stuck or home
	hint_button.disabled = disabled or locked or hint_used or hint.is_empty()
	hint_box.visible = hint_used and not auto and trying.is_empty() and not won
	rewind_button.disabled = disabled or locked
	for block in bank.get_children():
		block.modulate.a = 0.45 if disabled or locked else 1.0
		block.mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled or locked else Control.CURSOR_DRAG

# ---- Captions ---------------------------------------------------------------------------------

func _name(n: int) -> String:
	return Registers.name(n)

## A register's value as the caption says it: addresses (ra, sp, the Chomper's junk) in hex,
## a never-saved stack word as junk, and numbers as C prints them.
func _value(n: int, value: int) -> String:
	if value == JUNK:
		return "junk"
	if n == 1 or n == 2 or (value >= 0x5A00 and value < 0x6000):
		return "0x%X" % value
	return Style.word_text(value)

## The function a code address belongs to: the nearest function label at or before it.
func _function_at(address: int, labels: Dictionary) -> String:
	var functions := [str(payload.entry)]
	for line in walk.built.lines:
		var ins := Assembly.parse(str(line))
		if str(ins.op) == "jal" and int(ins.rd) == 1:
			functions.append(str(ins.target))
	var best := ""
	var best_at := -1
	for name in functions:
		var at := int(labels.get(name, -1))
		if at <= address and at > best_at:
			best = name
			best_at = at
	return best

## What a line just did, in plain words, with the values it used. `regs` are the registers just
## before it ran.
func _caption(text: String, step: Dictionary, regs: Array, labels: Dictionary) -> String:
	var ins := Assembly.parse(text)
	var op := str(ins.op)
	var rd := int(ins.get("rd", 0))
	var rs1 := int(ins.get("rs1", 0))
	var rs2 := int(ins.get("rs2", 0))
	var imm := int(ins.get("imm", 0))
	var value := int(step.value)
	if step.get("crash", false):
		return "This line reaches for the word at 0x%X, which isn't on the stack it can use." % int(step.address)
	match op:
		"addi":
			if rd == 2 and rs1 == 2:
				if imm < 0:
					return "Make room on the stack: sp moves down %d bytes (%d word%s), to 0x%X." % [-imm, -imm / 4,
						"" if imm == -4 else "s", int(step.sp)]
				return "Give the room back: sp moves up %d bytes, to 0x%X." % [imm, int(step.sp)]
			if rs1 == 0:
				return "%s = %s." % [_name(rd), _value(rd, value)]
			return "%s = %s %s %d = %s." % [_name(rd), _name(rs1), "-" if imm < 0 else "+", absi(imm), _value(rd, value)]
		"add", "sub", "mul":
			if op == "add" and rs2 == 0:
				return "Copy %s into %s: %s." % [_name(rs1), _name(rd), _value(rd, value)]
			if op == "add" and rs1 == 0:
				return "Copy %s into %s: %s." % [_name(rs2), _name(rd), _value(rd, value)]
			var symbol: String = {"add": "+", "sub": "-", "mul": "×"}[op]
			return "%s = %s %s %s = %s %s %s = %s." % [_name(rd), _name(rs1), symbol, _name(rs2), _value(rs1, regs[rs1]),
				symbol, _value(rs2, regs[rs2]), _value(rd, value)]
		"slli":
			return "%s = %s << %d: %s, %d times bigger." % [_name(rd), _name(rs1), imm, _value(rd, value), 1 << imm]
		"slti":
			return "%s = 1 if %s (%s) is less than %d, else 0. So %s = %d." % [_name(rd), _name(rs1),
				_value(rs1, regs[rs1]), imm, _name(rd), value]
		"sw":
			return "Save %s on the stack: %s goes in the word at sp+%d (0x%X)." % [_name(rs2), _value(rs2, regs[rs2]), imm,
				int(step.address)]
		"lw":
			if rd == 1 or CallMachine.restored(_name(rd)):
				return "Restore %s from the stack (sp+%d): %s = %s again." % [_name(rd), imm, _name(rd), _value(rd, value)]
			return "Load the word at sp+%d into %s: %s." % [imm, _name(rd), _value(rd, value)]
		"jal":
			if rd == 1:
				return "Call %s: ra = 0x%X, the address of the next line, then jump. A new floor opens on the tower." \
					% [str(ins.target), value]
			return "Jump to %s. j leaves ra alone: it still holds %s." % [str(ins.target), _value(1, regs[1])]
		"jalr":
			var target := int(step.next)
			if target == CallMachine.CHOMPER:
				return "Return to the Chomper: jump to ra (0x400). This call is over."
			return "Return: jump to ra (0x%X), back in %s. This floor closes." % [target, _function_at(target, labels)]
	if op in Assembly.BRANCHES:
		var taken := int(step.next) != int(step.pc) + 4
		var symbol: String = {"beq": "=", "bne": "≠", "blt": "<", "bge": "≥", "bltu": "<", "bgeu": "≥"}[op]
		return "Is %s (%s) %s %s (%s)? %s." % [_name(rs1), _value(rs1, regs[rs1]), symbol, _name(rs2),
			_value(rs2, regs[rs2]), ("Yes, so jump to %s" % str(ins.target)) if taken else "No, so carry on"]
	return "%s = %s." % [_name(rd), _value(rd, value)]
