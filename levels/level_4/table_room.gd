extends RefCounted
## One Level 4 pipelining room, in the form of the lectures' practice questions: a circuit, a
## pipeline diagram to fill in, clocks to tune, a table with blanks, and questions, in any
## combination. The level's own rooms are all hands-on: a diagram the player places or stalls
## (it flags two rows in one stage, and after a run draws an arrow for each value a line read),
## and clocks tuned by racing a signal against them (every race is a try). Check plays the
## diagram and the races, says what went wrong first, then sends everything at once: a number
## for each row of the diagram, each clock's period, then any blanks. grade() mirrors
## grade_table in server/timing.py; the server has the final say.

signal attempt
signal learning_event(kind: String, detail: Dictionary)

const TimingVisuals := preload("res://levels/level_4/timing_visuals.gd")
const TimingGuide := preload("res://levels/level_4/timing_guide.gd")
const Style := preload("res://ui/style.gd")

var payload: Dictionary
var guide_title := "Circuit guide"  # What the guide button says for this room.
var hint := ""
var hint_used := false
var fails := 0
var locked := false
var disabled := false
var chart  # The pipeline diagram, if the room has one.
var circuit  # The circuit figure, if the room has one.
var tuners: Array = []  # The clocks to tune.
var slip := ""  # What the last check found wrong, for the strike message.
var blanks: Array = []  # Each blank after the diagram's: {"key", "edit" or "buttons", "value"}.
var missed := 0  # How many blanks the last check found wrong.
var check_button: Button
var clear_button: Button
var hint_button: Button
var hint_label: Label
var solved_label: Label  # The room's `solved_note`, in place of its facts once the gate opens.
var facts_label: Label

func _init(room: Dictionary, box: VBoxContainer, hint_text) -> void:
	payload = room
	guide_title = "Circuit guide" if room.has("circuit") and not room.has("chart") else "Pipeline guide"
	hint = "" if hint_text == null else str(hint_text)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 18)
	box.add_child(main)
	var figures := VBoxContainer.new()
	figures.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	figures.add_theme_constant_override("separation", 6)
	main.add_child(figures)
	if room.has("circuit"):
		circuit = TimingVisuals.CircuitView.new(room.circuit)
		circuit.size_flags_vertical = Control.SIZE_EXPAND_FILL
		figures.add_child(circuit)
	if room.has("chart"):
		chart = TimingVisuals.PipelineChart.new(room.chart)
		chart.changed.connect(_sync)
		figures.add_child(chart)
	hint_label = Style.hint_box(figures, false)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(548, 0)
	side.add_theme_constant_override("separation", 6)
	main.add_child(side)
	if room.has("facts"):
		var facts := _text("\n".join(PackedStringArray(room.facts)), 13, Color(Style.CYAN, 0.9))
		facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.add_child(facts)
		facts_label = facts
	if room.has("solved_note"):
		solved_label = Style.hint_box(side, false)
		solved_label.add_theme_color_override("font_color", Style.GREEN)
		solved_label.get_parent().get_theme_stylebox("panel").border_color = Color(Style.GREEN, 0.7)
	for clock in room.get("clocks", []):
		var tuner = TimingVisuals.ClockRace.new(clock)
		tuner.changed.connect(_sync)
		if clock.has("gold") and circuit != null:
			# The circuit shows the design this clock belongs to: with or without its pipeline registers.
			tuner.touched.connect(func():
				circuit.ghost = not clock.gold
				circuit.queue_redraw())
		tuners.append(tuner)
		side.add_child(tuner)
	if room.has("rows"):
		var table := GridContainer.new()
		table.columns = room.columns.size()
		table.add_theme_constant_override("h_separation", 14)
		table.add_theme_constant_override("v_separation", 4)
		side.add_child(table)
		for heading in room.columns:
			table.add_child(_text(str(heading), 12, Color(Style.TEXT, 0.55)))
		for row in room.rows:
			for cell in row:
				if cell is Dictionary:
					table.add_child(_blank(cell))
				else:
					var label := _text(str(cell), 13, Color(Style.TEXT, 0.92))
					label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					table.add_child(label)
	if room.has("asks"):
		var asks := GridContainer.new()
		asks.columns = 2
		asks.add_theme_constant_override("h_separation", 14)
		asks.add_theme_constant_override("v_separation", 4)
		side.add_child(asks)
		for ask in room.asks:
			var label := _text(str(ask.ask), 13, Color(Style.TEXT, 0.92))
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			asks.add_child(label)
			asks.add_child(_blank(ask))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	side.add_child(keys)
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
	clear_button = _tool("Clear", _clear)
	hint_button = _tool("Hint (−1★)", show_hint)
	keys.add_child(clear_button)
	keys.add_child(hint_button)
	_sync()

func answer() -> Dictionary:
	return {"cells": _cells()}

## What each part of this room is and does, for the level's guide (I).
func guide() -> Dictionary:
	return TimingGuide.for_room(payload)

func stars() -> int:
	return 3 - int(fails > 0) - int(hint_used)

func miss_text() -> String:
	if not slip.is_empty():
		return slip
	return "Not everything is right!" if missed == 0 else "%d thing%s wrong!" % [missed, " is" if missed == 1 else "s are"]

func retry_tip() -> String:
	return "Fix what's red and try again."

func set_disabled(value: bool) -> void:
	disabled = value
	_sync()

## Enter checks, once every blank is filled. Other keys belong to the blank being typed in.
func handle_key(key: int) -> bool:
	if key in [KEY_ENTER, KEY_KP_ENTER] and not _busy() and _complete():
		check()
		return true
	return false

# Number keys, Backspace, and R do nothing here: typing happens in the blanks.
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
	hint_label.get_parent().show()
	hint_button.modulate = Color.WHITE
	_sync()

## Hands the answers in. A room with a diagram first plays it, a cycle at a time.
func check() -> void:
	if _busy() or not _complete():
		return
	locked = true
	# What went wrong first, in words, for the strike message. The grader decides the strike.
	slip = "" if chart == null else chart.problem()
	_sync()
	if chart != null:
		var last: int = chart.length()
		var sweep: Tween = chart.create_tween()
		sweep.tween_method(func(cycle: float):
			chart.cursor = mini(int(cycle), last - 1)
			chart.queue_redraw(), 0.0, float(last), 0.07 * last)
		await sweep.finished
		if not is_instance_valid(chart):
			return
		chart.cursor = -1
		chart.revealed = true  # The run is over: its arrows show what each line read, and when.
		chart.queue_redraw()
	if not tuners.is_empty():
		# Race every clock's signal. Every race is a try: a clock that ticks too soon breaks the
		# circuit, and one with time to spare is a miss too, since it could tick faster.
		var race: Tween = tuners[0].create_tween()
		race.tween_method(func(part: float):
			for tuner in tuners:
				tuner.shown = part
				tuner.queue_redraw(), 0.0, 1.0, 1.3)
		await race.finished
		if not is_instance_valid(tuners[0]):
			return
		var broke: bool = tuners.any(func(tuner): return tuner.period() < tuner.trip())
		if broke:
			slip = "The clock ticked before the signal arrived!"
			Audio.play("overflow", -6.0)
		elif tuners.any(func(tuner): return tuner.period() > tuner.trip()):
			slip = "It works, but a clock could tick faster!"
	attempt.emit()

func solved() -> void:
	locked = true
	if chart != null:
		chart.won = true
		chart.wrong.clear()
		chart.queue_redraw()
		Style.burst(chart, chart.size / 2.0, [Style.GREEN, Style.GOLD, Style.CYAN], 30, 260.0)
	for blank in blanks:
		_mark(blank, Style.GREEN)
	for tuner in tuners:
		tuner.won = true
		tuner.queue_redraw()
	hint_label.get_parent().hide()
	if solved_label != null:
		# Something to learn now that the gate is open (gate 10: what the forwarding muxes did).
		solved_label.text = str(payload.solved_note)
		solved_label.get_parent().show()
		if facts_label != null:
			facts_label.hide()
	check_button.get_parent().hide()  # Nothing left to check: the room gives the space to the explanation.
	_sync()

## A strike: every wrong row of the diagram and every wrong blank turns red until it is changed.
func failed() -> void:
	fails += 1
	locked = false
	var keys := table_keys(payload)
	var cells := _cells()
	missed = 0
	for k in range(cells.size()):
		if tidy(cells[k]) == tidy(keys[k]):
			continue
		missed += 1
		# A clock shows its own verdict.
		if chart != null and k < chart.marks.size():
			chart.wrong[k] = true
		elif k >= cells.size() - blanks.size():
			_mark(blanks[k - (cells.size() - blanks.size())], Style.RED)
	if chart != null:
		chart.queue_redraw()
	_sync()
	if fails >= 2 and not hint_used and not hint.is_empty():
		hint_button.text = "Need a hint? (−1★)"
		hint_button.modulate = Style.GOLD

func reset() -> void:
	locked = false
	_sync()

func _busy() -> bool:
	return locked or disabled

func _cells() -> Array:
	var cells: Array = []
	if chart != null:
		for mark in chart.marks:
			cells.append(str(mark))
	for tuner in tuners:
		cells.append(str(tuner.period()))
	for blank in blanks:
		cells.append(_value(blank))
	return cells

func _value(blank: Dictionary) -> String:
	return str(blank.edit.text).strip_edges() if blank.has("edit") else str(blank.value)

func _complete() -> bool:
	if chart != null and not chart.complete():
		return false
	for blank in blanks:
		if _value(blank).is_empty():
			return false
	return true

func _started() -> bool:
	if chart != null and chart.marks.any(func(mark): return mark != (0 if chart.stalling else -1)):
		return true
	if tuners.any(func(tuner): return tuner.pick != tuner.options.size() - 1):
		return true
	return blanks.any(func(blank): return not _value(blank).is_empty())

func _clear() -> void:
	if _busy() or not _started():
		return
	Audio.play("undo")
	for blank in blanks:
		if blank.has("edit"):
			blank.edit.text = ""
		else:
			blank.value = ""
		_mark(blank, Color.TRANSPARENT)
	if chart != null:
		chart.clear()
	for tuner in tuners:
		tuner.reset()
	_sync()

func _sync() -> void:
	var off := _busy()
	if chart != null:
		chart.editable = not off
		chart.queue_redraw()
	for tuner in tuners:
		tuner.editable = not off
		tuner.queue_redraw()
	for blank in blanks:
		if blank.has("edit"):
			blank.edit.editable = not off
			if off:
				blank.edit.release_focus()
		else:
			for button in blank.buttons:
				button.disabled = off
				_paint_choice(button, button.text == blank.value, blank.get("mark", Color.TRANSPARENT))
	check_button.disabled = off or not _complete()
	var verb := "Race ▶" if not tuners.is_empty() and chart == null else "Run ▶" if chart != null else "Check ▶"
	check_button.text = verb if _complete() else "Place every row of the diagram" if chart != null and not chart.complete() \
		else "Fill in every blank"
	clear_button.disabled = off or not _started()
	hint_button.disabled = disabled or locked or hint_used or hint.is_empty()

## A blank's control: a box to type in, or a button for each of its choices.
func _blank(spec: Dictionary) -> Control:
	var blank := {"key": str(spec.blank), "value": ""}
	blanks.append(blank)
	if spec.has("choices"):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		blank.buttons = []
		for choice in spec.choices:
			var button := Button.new()
			button.text = str(choice)
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.custom_minimum_size = Vector2(40, 26)
			button.add_theme_font_override("font", Style.MONO)
			button.add_theme_font_size_override("font_size", 13)
			button.pressed.connect(_choose.bind(blank, str(choice)))
			blank.buttons.append(button)
			row.add_child(button)
		return row
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(92, 26)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.max_length = 16
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.placeholder_text = "?"
	edit.context_menu_enabled = false
	edit.add_theme_font_override("font", Style.MONO)
	edit.add_theme_font_size_override("font_size", 14)
	edit.text_changed.connect(func(_text):
		_mark(blank, Color.TRANSPARENT)
		_sync())
	edit.text_submitted.connect(func(_text): _next(blank))
	blank.edit = edit
	_mark(blank, Color.TRANSPARENT)
	return edit

## Enter in a blank moves to the next empty one, or checks when none is left.
func _next(from: Dictionary) -> void:
	var start := blanks.find(from)
	for k in range(1, blanks.size()):
		var blank: Dictionary = blanks[(start + k) % blanks.size()]
		if blank.has("edit") and _value(blank).is_empty():
			blank.edit.grab_focus()
			return
	check()

func _choose(blank: Dictionary, choice: String) -> void:
	if _busy():
		return
	Audio.play("press", -8.0, 0.1)
	blank.value = "" if blank.value == choice else choice
	_mark(blank, Color.TRANSPARENT)
	_sync()

## Outlines a blank: red when the last check found it wrong, green once the gate opens.
func _mark(blank: Dictionary, color: Color) -> void:
	blank.mark = color
	if not blank.has("edit"):
		for button in blank.buttons:
			_paint_choice(button, button.text == blank.value, color)
		return
	for look in ["normal", "focus", "read_only"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(Style.SOCKET, 0.9)
		style.border_color = color if color.a > 0 else Style.GOLD if look == "focus" else Style.DIM
		style.set_border_width_all(2 if color.a > 0 or look == "focus" else 1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		blank.edit.add_theme_stylebox_override(look, style)

func _paint_choice(button: Button, chosen: bool, mark: Color) -> void:
	var color: Color = (mark if mark.a > 0 else Style.GOLD) if chosen else Style.DIM
	for look in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(color, 0.28) if chosen else Color(Style.SOCKET, 0.9 if look != "hover" else 1.0)
		style.border_color = color if chosen or look != "hover" else Color(Style.GOLD, 0.7)
		style.set_border_width_all(2 if chosen else 1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		button.add_theme_stylebox_override(look, style)
	for look in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(look, Style.TEXT if chosen else Color(Style.TEXT, 0.7))

func _text(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _tool(text: String, action: Callable) -> Button:
	var tool := Button.new()
	tool.text = text
	tool.custom_minimum_size = Vector2(80, 40)
	tool.add_theme_font_size_override("font_size", 14)
	tool.focus_mode = Control.FOCUS_NONE
	tool.pressed.connect(action)
	return tool

## A table room's keys, in the order its blanks are answered. Mirrors table_keys in server/timing.py.
static func table_keys(room: Dictionary) -> Array:
	var keys: Array = []
	var diagram: Dictionary = room.get("chart", {})
	for mark in diagram.get("starts", diagram.get("stalls", [])):
		keys.append(str(int(mark)))
	for clock in room.get("clocks", []):
		var total := 0
		for part in clock.path:
			total += int(part[1])
		keys.append(str(total))
	for row in room.get("rows", []):
		for cell in row:
			if cell is Dictionary:
				keys.append(str(cell.blank))
	for ask in room.get("asks", []):
		keys.append(str(ask.blank))
	return keys

## What a cell says, however it was typed: no spaces or commas, a number without leading zeros or
## trailing decimal zeros, anything else in lower case. Mirrors tidy.
static func tidy(text: String) -> String:
	text = text.replace(" ", "").replace(",", "")
	if not text.is_empty() and text.replace("?", "").is_empty():
		return "??"
	var whole := text.get_slice(".", 0)
	var part := text.substr(whole.length() + 1)
	var dotted := text.contains(".")
	for letter in whole + part:
		if letter < "0" or letter > "9":
			return text.to_lower()
	if (whole + part).is_empty() or (dotted and part.is_empty()):
		return text.to_lower()
	part = part.rstrip("0")
	return str(int(whole)) + ("." + part if not part.is_empty() else "")

## A reference answer in words, for the level's Show answer.
static func answer_lines(room: Dictionary, response: Dictionary) -> Array:
	var lines: Array = []
	var cells: Array = response.get("cells", [])
	var at := 0
	var diagram: Dictionary = room.get("chart", {})
	if diagram.has("starts") or diagram.has("stalls"):
		var marks: Array = []
		for row in diagram.rows:
			marks.append(str(int(cells[at]) + (1 if diagram.has("starts") else 0)))
			at += 1
		lines.append(("Diagram: start the rows in cycles %s." if diagram.has("starts") else "Diagram: stalls for each line, top to bottom: %s.")
			% ", ".join(PackedStringArray(marks)))
	for clock in room.get("clocks", []):
		lines.append("%s: %s %s." % [clock.name, cells[at], clock.get("unit", "ps")])
		at += 1
	for row in room.get("rows", []):
		var filled: Array = []
		for k in range(row.size()):
			if row[k] is Dictionary:
				filled.append("%s %s" % [room.columns[k], cells[at]])
				at += 1
		if not filled.is_empty():
			lines.append("%s: %s." % [str(row[0]) if row[0] is String else "Row", ", ".join(PackedStringArray(filled))])
	for ask in room.get("asks", []):
		lines.append("%s: %s." % [str(ask.ask).trim_suffix("?"), cells[at]])
		at += 1
	return lines

## Mirrors grade_table in server/timing.py for guest mode, where the game grades itself.
static func grade(room: Dictionary, response: Dictionary) -> bool:
	var cells = response.get("cells")
	var keys := table_keys(room)
	if not (cells is Array) or cells.size() != keys.size():
		return false
	for k in range(keys.size()):
		if not (cells[k] is String) or tidy(cells[k]) != tidy(keys[k]):
			return false
	return true
