extends RefCounted
## What every Level 3 room shares: the program listing on the left, the stack drawn as the Call
## Stack Tower in the middle, and a side panel with the room's controls as numbered steps, the
## Chomper's audit, and the hint. A run plays on the tower: each call lowers a floor (the stack
## grows down), the robot rides sp like an elevator, stores fill their words, and returns pull
## floors back up. walk_room.gd extends this with the walkthrough's controls and answer;
## call_machine.gd runs the code.

signal attempt
signal learning_event(kind: String, detail: Dictionary)

const CallMachine := preload("res://levels/level_3/call_machine.gd")
const TowerVisuals := preload("res://levels/level_3/tower_visuals.gd")
const CodeVisuals := preload("res://levels/level_2/code_visuals.gd")
const Assembly := preload("res://levels/level_2/assembly.gd")
const Registers := preload("res://ui/registers.gd")
const Style := preload("res://ui/style.gd")
const STACK_TOP := CallMachine.STACK_TOP
const JUNK := CallMachine.JUNK
## Why a call crashed, over the tower and (shorter) on its audit card.
const FAULTS := {
	"code": ["NO CODE: the PC jumped to %s, where there's no instruction.", "jumped to %s"],
	"memory": ["OFF THE STACK: there's no stack word at %s.", "no stack word at %s"],
	"aligned": ["MISALIGNED: no word starts at %s.", "%s isn't a word"],
	"overflow": ["STACK OVERFLOW: the heap already ate the word at %s.", "ran into the heap at %s"],
	"loop": ["NEVER RETURNED: the code kept running and never got back to the Chomper.", "never returned"],
}

var payload: Dictionary
var hint := ""
var hint_used := false
var fails := 0
var headline := ""
var locked := false
var playing := false
var disabled := false
var listing
var tower
var side: VBoxContainer
var cards
var tools: HBoxContainer
var run_button: Button
var hint_button: Button
var hint_box: PanelContainer
var hint_label: Label
var won := false

func _init(room: Dictionary, box: VBoxContainer, hint_text) -> void:
	payload = room
	hint = "" if hint_text == null else str(hint_text)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	box.add_child(main)
	listing = TowerVisuals.ListingView.new()
	listing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listing.size_flags_stretch_ratio = 1.2
	main.add_child(listing)
	tower = TowerVisuals.TowerView.new()
	tower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if room.has("chomper"):
		tower.bottom = STACK_TOP - 4 * CallMachine.stack_words(room)
	main.add_child(tower)
	side = VBoxContainer.new()
	side.custom_minimum_size = Vector2(372, 0)
	side.add_theme_constant_override("separation", 8)
	main.add_child(side)
	_build_controls()
	# The hint, once asked for, sits in a box over the bottom of the tower, so showing it never moves
	# the controls. It steps aside while a call plays.
	hint_label = Style.hint_box(tower)
	hint_box = hint_label.get_parent() as PanelContainer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var last := _last_step()
	if last != null:
		side.add_child(last)
	tools = HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	side.add_child(tools)
	run_button = Button.new()
	run_button.custom_minimum_size = Vector2(0, 44)
	run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_button.focus_mode = Control.FOCUS_NONE
	run_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	run_button.tooltip_text = "Enter"
	run_button.add_theme_font_size_override("font_size", 17)
	for look in ["normal", "hover", "pressed", "disabled"]:
		run_button.add_theme_stylebox_override(look, Style.key_style(_run_color(), look))
	run_button.pressed.connect(run_room)
	tools.add_child(run_button)
	_add_tools()
	hint_button = _tool("Hint", show_hint, "")
	tools.add_child(hint_button)
	_show_start()
	_sync()

# ---- What each kind of room fills in -------------------------------------------------------

## The room's steps and controls in the side panel (a room with an audit adds it with _add_audit).
func _build_controls() -> void:
	pass

## A step shown just above the run button, or null.
func _last_step() -> Control:
	return null

func _add_tools() -> void:
	pass

func _run_color() -> Color:
	return Style.GREEN

func _run_text() -> String:
	return "Run ▶"

func _can_run() -> bool:
	return true

func _show_start() -> void:
	pass

func _on_run() -> void:
	pass

func _sync_controls() -> void:
	pass

func _star_penalty() -> int:
	return 0

func answer() -> Dictionary:
	return {}

func miss_text() -> String:
	return "Not yet!" if headline.is_empty() else headline

func retry_tip() -> String:
	return "Change something and try again."

# ---- What the runner calls ------------------------------------------------------------------

func stars() -> int:
	return maxi(1, 3 - int(fails > 0) - int(hint_used) - _star_penalty())

func set_disabled(value: bool) -> void:
	disabled = value
	_sync()

## Enter or Space runs the room when it's ready.
func handle_key(key: int) -> bool:
	if _busy():
		return false
	if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _can_run():
		run_room()
		return true
	return false

func press(_index: int) -> void:
	pass

func undo() -> void:
	pass

func restart() -> void:
	pass

func show_hint() -> void:
	if hint.is_empty() or hint_used:
		return
	hint_used = true
	learning_event.emit("hint", {})
	Audio.play("hint", -4.0)
	hint_label.text = "Hint: " + hint
	hint_button.modulate = Color.WHITE
	_sync()

func solved() -> void:
	locked = true
	won = true
	tower.celebrate()
	listing.win = 0.6
	_sync()

## The server counted the answer as a miss: the room opens again for another try.
func failed() -> void:
	fails += 1
	if cards != null:
		cards.shake = 8.0
	locked = false
	_sync()
	if fails >= 2 and not hint_used and not hint.is_empty():
		hint_button.text = "Need a hint?"
		hint_button.modulate = Style.GOLD

## The attempt never reached the grader: back to how things were before it.
func reset() -> void:
	locked = false
	playing = false
	_show_start()
	_sync()

## The program's lines and labels, and the registers in them, for the instruction guide.
func guide() -> Dictionary:
	var lines: Array = []
	for row in listing.rows:
		if row.kind != "slot":
			lines.append(str(row.text))
	return {"lines": lines}

func run_room() -> void:
	if _busy() or not _can_run():
		return
	_on_run()

# ---- Shared helpers -------------------------------------------------------------------------

func _busy() -> bool:
	return locked or playing or disabled

func _sync() -> void:
	run_button.disabled = _busy() or not _can_run()
	run_button.text = "Running…" if playing else _run_text()
	hint_button.disabled = disabled or locked or hint_used or hint.is_empty()
	hint_box.visible = hint_used and not playing and not won
	_sync_controls()

## A call as the tower and the audit say it: the function and its arguments.
func _call_title(function: String, record: Dictionary) -> String:
	var params: Array = payload.get("params", [])
	if params.is_empty():
		params = _argument_names()
	var values: Array = []
	for name in params:
		values.append(_number(int(record.get(str(name), 0))))
	return "%s(%s)" % [function, ", ".join(PackedStringArray(values))]

func _argument_names() -> Array:
	var names: Array = payload.calls[0].get("args", {}).keys()
	names.sort_custom(func(a, b): return Registers.number(str(a)) < Registers.number(str(b)))
	return names

func _audit_lines() -> Array:
	var lines: Array = []
	for call in payload.calls:
		var title := _call_title(str(payload.entry), call.get("args", {}))
		lines.append("the Chomper calls %s%s" % [title, " · wants %s" % _number(int(call.expect))
			if call.has("expect") else ""])
	return lines

## A card's second line after a run: what the call returned and kept, or what went wrong.
func _detail(row: Dictionary) -> String:
	var state: Dictionary = row.state
	if not state.fault.is_empty():
		return "crashed: " + _fault_text(state.fault, 1)
	var regs: Array = state.regs
	if row.passed:
		return "returned %s · s0–s11 and sp kept" % _number(int(regs[10]))
	var parts: Array = []
	for problem in row.problems:
		match str(problem):
			"value":
				parts.append("returned %s" % _number(int(regs[10])))
			"sp":
				parts.append("sp is 0x%X, not 0x%X" % [int(regs[2]), STACK_TOP])
			_:
				var n := Registers.number(str(problem))
				parts.append("%s changed: %s → %s" % [problem, Assembly.word_text(int(row.before[n])),
					Assembly.word_text(int(regs[n]))])
	return "; ".join(PackedStringArray(parts))

## An argument or return value as C prints it (in decimal, even when it's 256 or more).
func _number(value: int) -> String:
	return "junk" if value == JUNK else Style.word_text(value)

func _fault_text(fault: Dictionary, form: int) -> String:
	var text: String = FAULTS[str(fault.kind)][form]
	return text % ("0x%X" % int(fault.at)) if text.contains("%s") else text

## Plays one call on the tower: floors appear as calls are made and leave as they return, each
## store fills its word, and the listing follows the PC. A long run (an endless loop) plays its
## first steps, then jumps to where it ended.
func _play(state: Dictionary, index: int = 0) -> void:
	var trace: Array = state.trace
	var shown: Array = trace.slice(0, 150)
	var duration := clampf(5.5 / maxf(shown.size(), 1.0), 0.03, 0.3)
	var model := {"memory": CallMachine.setup(payload, index).memory, "labels": {}, "open": [state.calls[0]],
		"sp": STACK_TOP, "heap": CallMachine.heap_line(payload, 0)}
	tower.idle = ""
	_show_model(model)
	for step in shown:
		if not is_instance_valid(tower):
			return
		listing.running = int(step.pc)
		listing.queue_redraw()
		_apply(model, step)
		_show_model(model)
		if not str(step.stored).is_empty():
			tower.flash(int(step.address))
		if not step.call.is_empty():
			Audio.play("press", -10.0, 0.15)
		elif step.returned:
			Audio.play("press", -12.0, 0.3)
		await tower.get_tree().create_timer(duration, false).timeout
	if not is_instance_valid(tower):
		return
	for step in trace.slice(shown.size()):
		_apply(model, step)
	listing.running = -1
	listing.queue_redraw()
	_show_model(model)
	if not state.fault.is_empty():
		tower.fault(_fault_text(state.fault, 0))
		Audio.play("overflow", -4.0)
		await tower.get_tree().create_timer(1.4, false).timeout

func _apply(model: Dictionary, step: Dictionary) -> void:
	if not step.call.is_empty():
		model.open.append(step.call)
	elif step.returned and not model.open.is_empty():
		model.open.pop_back()
	var name := str(step.stored)
	if not name.is_empty():
		model.memory[int(step.address)] = int(step.value)
		model.labels[int(step.address)] = "saved " + name if CallMachine.restored(name) else name
	model.sp = int(step.get("sp", model.sp))
	model.heap = int(step.get("heap", model.heap))

## The open calls as floors: each holds the words from where sp was when it was called down to
## where the next call began (or to sp, for the deepest).
func _show_model(model: Dictionary) -> void:
	var floors: Array = []
	var open: Array = model.open
	for i in range(open.size()):
		var record: Dictionary = open[i]
		var top := int(record.sp)
		var below := int(open[i + 1].sp) if i + 1 < open.size() else int(model.sp)
		var words: Array = []
		var address := top - 4
		while address >= below and words.size() < 40:
			words.append({"address": address, "label": model.labels.get(address, ""), "value": model.memory.get(address, JUNK)})
			address -= 4
		floors.append({"title": _call_title(str(record.function), record), "words": words, "current": i == open.size() - 1})
	tower.show_live(floors, int(model.sp), int(model.heap) if payload.has("chomper") else -1)

func _tool(text: String, action: Callable, shortcut: String) -> Button:
	var tool := Button.new()
	tool.text = text
	tool.tooltip_text = shortcut
	tool.custom_minimum_size = Vector2(76, 44)
	tool.add_theme_font_size_override("font_size", 14)
	tool.focus_mode = Control.FOCUS_NONE
	tool.pressed.connect(action)
	return tool

## A numbered step in the side panel (the shared look every level's steps use).
func _step(number: int, text: String, note: String = "") -> HBoxContainer:
	return Style.step(number, text, note)

## Tighter padding than the theme gives buttons, for a column of choices in the side panel.
func _compact(button: Button) -> void:
	var theme := ThemeDB.get_project_theme()
	for look in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		if theme == null or not theme.has_stylebox(look, "Button"):
			continue
		var box: StyleBox = theme.get_stylebox(look, "Button").duplicate()
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		button.add_theme_stylebox_override(look, box)

## The Chomper's audit under the step that explains it: one card per call, filled in by a run.
func _add_audit(step: Control) -> void:
	side.add_child(step)
	cards = CodeVisuals.TestCards.new(_audit_lines())
	cards.title = ""
	side.add_child(cards)
