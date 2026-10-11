extends "res://levels/level_3/tower_room.gd"
## A Recursion Elevator room: the player types values on the chain of calls of one run (each
## floor's arguments, the ra or s0 it saves, or what it returns), outermost floor first. Riding
## the elevator plays the run on the tower and checks every typed value; the ride is the attempt.
## Values can be typed in decimal or as 0x hex.

const CAPTIONS := {"ret": "returns", "ra": "saved ra", "s0": "saved s0"}

var truth: Array = []  # The calls of the room's function, outermost first.
var fields: Array = []  # One LineEdit per blank, in the payload's order.
var looks := {}

func _run_color() -> Color:
	return Style.CYAN

func _run_text() -> String:
	return "Ride the elevator ▶" if _can_run() else "Fill in every ? to ride"

func _last_step() -> Control:
	return _step(2, "Ride the elevator to check them")

func _build_controls() -> void:
	truth = CallMachine.chain(payload)
	for state in ["plain", "good", "bad"]:
		var look := StyleBoxFlat.new()
		look.bg_color = Color(0.06, 0.08, 0.12)
		look.set_corner_radius_all(6)
		look.set_border_width_all(2 if state != "plain" else 1)
		look.border_color = {"plain": Color(Style.GOLD, 0.6), "good": Style.GREEN, "bad": Style.RED}[state]
		look.set_content_margin_all(4)
		looks[state] = look
	side.add_child(_step(1, "Fill in every ? box", "one row per call, the first call on top · decimal or 0x hex"))
	var blank_at := {}
	for k in range(payload.blanks.size()):
		blank_at["%d:%s" % [int(payload.blanks[k][0]), str(payload.blanks[k][1])]] = k
	fields.resize(payload.blanks.size())
	var params: Array = payload.params
	for f in range(int(payload.floors)):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		side.add_child(row)
		row.add_child(_text(str(f + 1), 12, Color(Style.TEXT, 0.45), 26))
		row.add_child(_text(str(payload.function) + "(", 14, Style.GOLD.lightened(0.3)))
		for i in range(params.size()):
			row.add_child(_cell(f, str(params[i]), blank_at))
			if i < params.size() - 1:
				row.add_child(_text(",", 14, Style.TEXT))
		row.add_child(_text(")", 14, Style.GOLD.lightened(0.3)))
		for column in payload.columns:
			row.add_child(_text("  " + str(CAPTIONS.get(str(column), column)), 12, Color(Style.TEXT, 0.55)))
			row.add_child(_cell(f, str(column), blank_at))

func _text(text: String, font_size: int, color: Color, width: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", Style.MONO)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

## One value on a floor: a field to type in if it's a blank, otherwise the value itself.
func _cell(f: int, field: String, blank_at: Dictionary) -> Control:
	var key := "%d:%s" % [f, field]
	if not blank_at.has(key):
		# A return value the room doesn't ask for stays hidden: it could give away one it does.
		if field == "ret":
			return _text("…", 14, Color(Style.TEXT, 0.35))
		return _text(Assembly.word_text(int(truth[f].get(field, 0))), 14, Style.TEXT)
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(62, 30)
	edit.placeholder_text = "?"
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_override("font", Style.MONO)
	edit.add_theme_font_size_override("font_size", 14)
	edit.add_theme_stylebox_override("normal", looks.plain)
	edit.add_theme_stylebox_override("focus", looks.plain)
	edit.text_changed.connect(func(_text_now: String):
		_mark(edit, "plain")
		_sync())
	var index: int = blank_at[key]
	edit.text_submitted.connect(func(_text_now: String): _next_field(index))
	fields[index] = edit
	return edit

func _mark(edit: LineEdit, state: String) -> void:
	edit.add_theme_stylebox_override("normal", looks[state])
	edit.add_theme_stylebox_override("focus", looks[state])
	edit.add_theme_stylebox_override("read_only", looks[state])

func _next_field(index: int) -> void:
	for k in range(index + 1, fields.size()):
		if fields[k].text.strip_edges().is_empty():
			fields[k].grab_focus()
			return
	fields[index].release_focus()
	if _can_run():
		run_room()

## A typed value: decimal, or hex with 0x, either with a minus sign. null if it isn't one.
static func parse_value(text: String):
	var t := text.strip_edges().to_lower()
	var negative := t.begins_with("-")
	if negative:
		t = t.substr(1)
	var value: int
	if t.begins_with("0x") and t.length() > 2 and t.substr(2).is_valid_hex_number():
		value = t.substr(2).hex_to_int()
	elif t.is_valid_int():
		value = t.to_int()
	else:
		return null
	return -value if negative else value

func _can_run() -> bool:
	for edit in fields:
		if parse_value(edit.text) == null:
			return false
	return true

func answer() -> Dictionary:
	var values: Array = []
	for edit in fields:
		values.append(parse_value(edit.text))
	return {"values": values}

func miss_text() -> String:
	return "The elevator stopped short!" if headline.is_empty() else headline

func retry_tip() -> String:
	return "Fix the red values and ride again."

## Number keys pick a blank to type in.
func press(index: int) -> void:
	if not _busy() and index < fields.size():
		fields[index].grab_focus()

func _show_start() -> void:
	tower.idle = "Each call adds a floor here,\nand each return takes one away."
	listing.show_program(CallMachine.assemble(payload))
	_show_model({"memory": CallMachine.setup(payload, 0).memory, "labels": {}, "open": [], "sp": STACK_TOP,
		"heap": CallMachine.heap_line(payload, 0)})

func _sync_controls() -> void:
	for edit in fields:
		edit.editable = not _busy()

func _on_run() -> void:
	playing = true
	headline = ""
	for edit in fields:
		edit.release_focus()
		_mark(edit, "plain")
	_sync()
	var built := CallMachine.assemble(payload)
	var state := CallMachine.run(payload, built.lines, built.labels, 0)
	await _play(state, 0)
	if not is_instance_valid(tower):
		return
	var wrong := 0
	for k in range(fields.size()):
		var blank: Array = payload.blanks[k]
		var want := int(truth[int(blank[0])].get(str(blank[1]), -1))
		var good: bool = (int(parse_value(fields[k].text)) & CallMachine.MASK) == want
		_mark(fields[k], "good" if good else "bad")
		wrong += int(not good)
	if wrong:
		headline = "%d of %d answers were off!" % [wrong, fields.size()]
	else:
		tower.flash_message("EVERY FLOOR CHECKS OUT", Style.GREEN)
	playing = false
	locked = true
	_sync()
	attempt.emit()
