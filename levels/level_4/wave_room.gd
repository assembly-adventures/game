extends RefCounted
## One Level 4 waveform room: a small circuit beside a timing grid. The inputs (and the clock, if
## there is one) are drawn already, and each signal to draw starts as a flat line at its first
## level. The player clicks a row wherever the signal changes, which puts an edge there. Moving
## over the grid shows that moment on the circuit: a wire is bright while it carries 1. Check plays
## time across the grid until the drawing first differs from what the circuit does. simulate() mirrors
## server/timing.py; the server runs its own and has the final say.

signal attempt
signal learning_event(kind: String, detail: Dictionary)

const TimingVisuals := preload("res://levels/level_4/timing_visuals.gd")
const TimingGuide := preload("res://levels/level_4/timing_guide.gd")
const Style := preload("res://ui/style.gd")
const GATE_NAMES := {"not": "NOT", "and": "AND", "or": "OR", "xor": "XOR", "nand": "NAND", "nor": "NOR"}

var payload: Dictionary
var guide_title := "Circuit guide"  # What the guide button says for this room.
var hint := ""
var hint_used := false
var fails := 0
var locked := false
var disabled := false
var checking := false  # A check is playing time across the grid.
var slip := Vector2i(-1, -1)  # (tick, row) where the last check first found the drawing wrong.
var missed: Array = []  # The signals the last check found wrong.
var history: Array = []  # The drawn rows before each stroke, for Undo.
var circuit
var grid
var check_button: Button
var undo_button: Button
var clear_button: Button
var hint_button: Button
var hint_label: Label

func _init(room: Dictionary, box: VBoxContainer, hint_text) -> void:
	payload = room
	hint = "" if hint_text == null else str(hint_text)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 14)
	box.add_child(main)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(340, 0)
	side.add_theme_constant_override("separation", 6)
	main.add_child(side)
	circuit = TimingVisuals.CircuitView.new(room.circuit, _notes(room))
	circuit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(circuit)
	hint_label = Style.hint_box(side, false)
	var work := VBoxContainer.new()
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work.add_theme_constant_override("separation", 6)
	main.add_child(work)
	grid = TimingVisuals.WaveGrid.new()
	grid.ticks = int(room.ticks)
	grid.tick_time = float(room.tick)
	grid.unit = str(room.unit)
	var given := simulate(room)
	var clock_name := str(room.clock.name) if room.has("clock") else ""
	var names: Array = [clock_name] if not clock_name.is_empty() else []
	for input in room.circuit.inputs:
		if str(input.name) != clock_name:
			names.append(str(input.name))
	for gate in room.circuit.gates:
		names.append(str(gate.out))
	for name in names:
		var draws: bool = name in room.draw
		var wave: Array = given[name]
		if draws:
			wave = []
			wave.resize(grid.ticks)
			wave.fill(int(given[name][0]))  # The circuit starts settled, so the first level is given.
		grid.rows.append({"name": name, "wave": wave, "draw": draws, "clock": name == clock_name})
	if not clock_name.is_empty():
		for edge in edges(given[clock_name]):
			if edge[1] == 1:
				grid.rises.append(edge[0])
	grid.setup()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.stroke.connect(func(): history.append(_drawn()))
	grid.changed.connect(func(_name):
		grid.cursor = -1.0
		_sync())
	grid.hovered.connect(circuit.highlight)
	grid.pointed.connect(func(tick):
		if not checking:
			_show_moment(tick))
	work.add_child(grid)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	work.add_child(keys)
	check_button = Button.new()
	check_button.custom_minimum_size = Vector2(0, 40)
	check_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_button.focus_mode = Control.FOCUS_NONE
	check_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	check_button.tooltip_text = "Enter"
	check_button.add_theme_font_size_override("font_size", 17)
	for look in ["normal", "hover", "pressed", "disabled"]:
		check_button.add_theme_stylebox_override(look, Style.key_style(Style.GREEN, look))
	check_button.pressed.connect(check)
	keys.add_child(check_button)
	undo_button = _tool("Undo", undo, "Backspace")
	clear_button = _tool("Clear", restart, "R")
	hint_button = _tool("Hint", show_hint, "")
	for tool in [undo_button, clear_button, hint_button]:
		keys.add_child(tool)
	_sync()

func answer() -> Dictionary:
	return {"waves": _drawn()}

## What each part of this room is and does, for the level's guide (I).
func guide() -> Dictionary:
	return TimingGuide.for_room(payload)

func stars() -> int:
	return 3 - int(fails > 0) - int(hint_used)

func miss_text() -> String:
	if missed.is_empty():
		return "That's not what the circuit does!"
	return "%s goes wrong at %s %s!" % [grid.rows[slip.y].name, TimingVisuals.WaveGrid.time_text(slip.x * float(payload.tick)), payload.unit]

func retry_tip() -> String:
	return "Fix the red row%s and check again." % ("" if missed.size() == 1 else "s")

func set_disabled(value: bool) -> void:
	disabled = value
	_sync()

func handle_key(key: int) -> bool:
	if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and not _busy() and _complete():
		check()
		return true
	return false

func press(_index: int) -> void:
	pass

## Takes back the last stroke.
func undo() -> void:
	if _busy() or history.is_empty():
		return
	Audio.play("undo")
	_restore(history.pop_back())

## Erases everything drawn.
func restart() -> void:
	if _busy() or not _started():
		return
	Audio.play("undo")
	history.append(_drawn())
	for row in grid.rows:
		if row.draw:
			row.wave.fill(int(row.wave[0]))
	grid.wrong.clear()
	grid.flag = Vector2i(-1, -1)
	grid.queue_redraw()
	_sync()

func show_hint() -> void:
	if hint.is_empty() or hint_used:
		return
	hint_used = true
	learning_event.emit("hint", {})
	Audio.play("hint", -4.0)
	hint_label.text = "Hint: " + hint
	hint_label.get_parent().show()
	hint_button.modulate = Color.WHITE
	_sync()

## Plays time across the grid, the circuit's wires following along, up to the first moment the
## drawing differs from what the circuit does (or to the end), then hands the drawing in. Where it
## stops is only for show: the grader decides the strike.
func check() -> void:
	if _busy() or not _complete():
		return
	var right := simulate(payload)
	missed.clear()
	slip = Vector2i(-1, -1)
	for r in range(grid.rows.size()):
		var row: Dictionary = grid.rows[r]
		if not row.draw or row.wave == right[row.name]:
			continue
		missed.append(str(row.name))
		for tick in range(grid.ticks):
			if int(row.wave[tick]) != int(right[row.name][tick]):
				if slip.x < 0 or tick < slip.x:
					slip = Vector2i(tick, r)
				break
	locked = true
	checking = true
	_sync()
	var stop := float(slip.x) if slip.x >= 0 else float(grid.ticks)
	var sweep: Tween = grid.create_tween()
	sweep.tween_method(func(at: float):
		grid.cursor = at
		grid.queue_redraw()
		_show_moment(mini(int(at), grid.ticks - 1)), 0.0, stop, clampf(stop / grid.ticks, 0.25, 1.0) * 1.1)
	await sweep.finished
	if not is_instance_valid(grid):
		return
	checking = false
	grid.flag = slip
	if slip.x < 0:
		grid.cursor = -1.0
		_show_moment(-1)
	grid.queue_redraw()
	attempt.emit()

## Lights the circuit's wires as the grid has them at one tick; -1 shows plain wires again.
func _show_moment(tick: int) -> void:
	var now := {}
	if tick >= 0:
		for row in grid.rows:
			now[row.name] = int(row.wave[tick])
	circuit.show_levels(now)

func solved() -> void:
	locked = true
	grid.won = true
	grid.cursor = -1.0
	grid.flag = Vector2i(-1, -1)
	grid.wrong.clear()
	Style.burst(grid, grid.size / 2.0, [Style.GREEN, Style.GOLD, Style.CYAN], 30, 260.0)
	grid.queue_redraw()
	hint_label.get_parent().hide()
	_sync()

func failed() -> void:
	fails += 1
	locked = false
	if slip.x >= 0:
		Style.burst(grid, Vector2(grid.LABEL + slip.x * grid._tick_width(), grid.AXIS + (slip.y + 0.5) * grid._row_height()),
			[Style.RED, Style.ORANGE], 14, 150.0)
	for name in missed:
		grid.wrong[name] = true
	grid.queue_redraw()
	_sync()
	if fails >= 2 and not hint_used and not hint.is_empty():
		hint_button.text = "Need a hint?"
		hint_button.modulate = Style.GOLD

func reset() -> void:
	locked = false
	grid.cursor = -1.0
	grid.flag = Vector2i(-1, -1)
	grid.queue_redraw()
	_sync()

func _busy() -> bool:
	return locked or disabled

func _drawn() -> Dictionary:
	var waves := {}
	for row in grid.rows:
		if row.draw:
			waves[row.name] = row.wave.duplicate()
	return waves

func _restore(waves: Dictionary) -> void:
	for row in grid.rows:
		if row.draw:
			row.wave = waves[row.name].duplicate()
	grid.wrong.clear()
	grid.flag = Vector2i(-1, -1)
	grid.queue_redraw()
	_sync()

## Whether any row has an edge yet.
func _started() -> bool:
	for row in grid.rows:
		if row.draw and not edges(row.wave).is_empty():
			return true
	return false

func _complete() -> bool:
	return _started()

func _sync() -> void:
	var off := _busy()
	grid.editable = not off
	check_button.disabled = off or not _complete()
	check_button.text = "Checking…" if checking else "Check ▶" if _complete() else "Click where %s changes" % _list(payload.draw, "or")
	if not off and grid.cursor >= 0.0 and grid.flag.x < 0:
		grid.cursor = -1.0
	undo_button.disabled = off or history.is_empty()
	clear_button.disabled = off or not _started()
	hint_button.disabled = disabled or locked or hint_used or hint.is_empty()

func _tool(text: String, action: Callable, shortcut: String) -> Button:
	var tool := Button.new()
	tool.text = text
	tool.tooltip_text = shortcut
	tool.custom_minimum_size = Vector2(80, 40)
	tool.add_theme_font_size_override("font_size", 14)
	tool.focus_mode = Control.FOCUS_NONE
	tool.pressed.connect(action)
	return tool

static func _list(names: Array, joiner := "and") -> String:
	var words := PackedStringArray(names)
	if words.size() <= 2:
		return (" %s " % joiner).join(words)
	return ", ".join(words.slice(0, words.size() - 1)) + ", %s " % joiner + words[words.size() - 1]

## Each gate's delay, to print under it.
static func _notes(room: Dictionary) -> Dictionary:
	var notes := {}
	var delays: Dictionary = room.get("delays", {})
	for gate in room.circuit.gates:
		var delay := int(delays.get(gate.op, 0))
		if delay > 0:
			var time := "%s %s" % [TimingVisuals.WaveGrid.time_text(delay * float(room.tick)), room.unit]
			notes[str(gate.out)] = "clk-to-q " + time if gate.op == "dff" else time
	return notes

## A waveform given as [[tick, value], ...] as one level per tick. Mirrors level in server/timing.py.
static func level(transitions: Array, ticks: int) -> Array:
	var changes := {}
	for change in transitions:
		changes[int(change[0])] = int(change[1])
	var wave: Array = []
	var value := 0
	for t in range(ticks):
		value = changes.get(t, value)
		wave.append(value)
	return wave

## Every signal of the room, one level per tick. Mirrors simulate.
static func simulate(room: Dictionary) -> Dictionary:
	var ticks := int(room.ticks)
	var waves := {}
	for name in room.signals:
		waves[str(name)] = level(room.signals[name], ticks)
	if room.has("clock"):
		var period := int(room.clock.period)
		var wave: Array = []
		for t in range(ticks):
			wave.append(int(posmod(t - int(room.clock.rise), period) < period / 2))
		waves[str(room.clock.name)] = wave
	var delays: Dictionary = room.get("delays", {})
	for gate in room.circuit.gates:
		var op := str(gate.op)
		var delay := int(delays.get(op, 0))
		var wave: Array = []
		if op == "dff":
			var data: Array = waves[str(gate.in[0])]
			var clk: Array = waves[str(gate.clk)]
			var value := int(room.get("start", {}).get(gate.out, 0))
			for t in range(ticks):
				var edge := t - delay
				if edge >= 1 and clk[edge] == 1 and clk[edge - 1] == 0:
					value = data[edge - 1]
				wave.append(value)
		else:
			for t in range(ticks):
				var ones := 0
				for name in gate.in:
					ones += int(waves[str(name)][maxi(t - delay, 0)])
				wave.append(_gate(op, ones, gate.in.size()))
		waves[str(gate.out)] = wave
	return waves

## A gate's output, given how many of its inputs are 1.
static func _gate(op: String, ones: int, count: int) -> int:
	match op:
		"not":
			return 1 - ones
		"and":
			return int(ones == count)
		"or":
			return int(ones > 0)
		"xor":
			return ones % 2
		"nand":
			return int(ones != count)
	return int(ones == 0)  # nor

## Where a waveform changes: [tick, new value] for each edge. Mirrors edges.
static func edges(wave: Array) -> Array:
	var found: Array = []
	for t in range(1, wave.size()):
		if int(wave[t]) != int(wave[t - 1]):
			found.append([t, int(wave[t])])
	return found

## A reference answer in words, for the level's Show answer: where each signal starts and every
## edge after that.
static func answer_lines(room: Dictionary, response: Dictionary) -> Array:
	var lines: Array = []
	var waves: Dictionary = response.get("waves", {})
	for name in room.draw:
		var wave: Array = waves.get(name, [])
		if wave.is_empty():
			continue
		var parts: Array = ["starts at %d" % int(wave[0])]
		for edge in edges(wave):
			parts.append("%s at %s %s" % ["rises" if edge[1] == 1 else "falls",
				TimingVisuals.WaveGrid.time_text(edge[0] * float(room.tick)), room.unit])
		lines.append("%s: %s" % [name, ", ".join(PackedStringArray(parts))])
	return lines

## Mirrors grade_wave in server/timing.py for guest mode, where the game grades itself.
static func grade(room: Dictionary, response: Dictionary) -> bool:
	var drawn = response.get("waves")
	if not (drawn is Dictionary) or drawn.size() != room.draw.size():
		return false
	var right := simulate(room)
	for name in room.draw:
		var wave = drawn.get(name)
		if not (wave is Array) or wave.size() != right[name].size():
			return false
		for t in range(wave.size()):
			if int(wave[t]) != int(right[name][t]):
				return false
	return true
