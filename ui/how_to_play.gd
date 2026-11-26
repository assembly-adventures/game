extends Control
## "How this level works": a card over the level with what the player does, the controls, and how
## stars and strikes work. It opens by itself the first time a player opens each level on this
## device, and again from the ? button in the top bar or the H key; Escape, H, or Got it closes it.
## The rooms' prompts can then stay about the question itself instead of repeating the controls.

signal toggled(open: bool)

const Style := preload("res://ui/style.gd")
const SEEN := "user://help.cfg"  # Which levels' cards this device has already shown.

## Each level's card: what the player does, and the controls, as short lines.
const LEVELS := {
	1: {"do": "Turn the register into the target value with the instruction keys. The gate opens by itself as soon as they match.",
		"controls": ["Press an instruction key, or its number (1–9), to run it on the register.",
			"Backspace undoes a move; R starts the gate over. Both are free."],
		"scoring": "Use as few moves as you can: more than the fewest possible costs a star. Running out of moves is a strike."},
	2: {"do": "Two kinds of rooms. In a maze room, walk the robot through memory to the exit; every step, load, and store writes one RISC-V line. In a code room, fill the blank lines so the program passes its tests.",
		"controls": ["Maze rooms: arrow keys or WASD step the robot, or click the next cell. Click a word to load it or store into it.",
			"Code rooms: click a blank (or press its number) and pick its line, then Run the tests.",
			"Backspace undoes; R clears."],
		"scoring": "In a maze room, more instructions than the fewest possible cost a star. A code room's run that fails a test is a strike, and costs a star."},
	3: {"do": "Follow a short program line by line as it calls functions, and make the one move the walk stops for.",
		"controls": ["Play runs the program; Step runs one line and Back goes back one.",
			"When the walk stops at your move, drag a code block into the gold slot (or press its number).",
			"A wrong block plays out, shows what broke, and rewinds. It costs a star, never a strike."],
		"scoring": "Get every move right with no hint for 3 stars."},
	4: {"do": "Waveform gates: draw the signals the circuit makes. Pipelining gates: place instructions on the diagram, add stalls, and tune clocks.",
		"controls": ["Waveforms: click a gold row at the moment its signal changes; click an edge again to take it away. Point at the grid to light up the circuit's wires at that moment.",
			"Pipeline diagrams: click the cycle a row starts in, or press + and − to hold a line in decode. Use as few stalls as you can.",
			"Clocks: set each one with − and +, then press Race."],
		"scoring": "Every Check, Run, and Race is a try: a wrong one is a strike, and the gate loses a star."},
}

var panel: PanelContainer
var body: VBoxContainer
var level := 1

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # A click outside the card closes it.
	visible = false
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(880, 0)
	var look := Style.panel_style()
	look.bg_color = Color(Style.BG, 0.98)
	look.border_color = Color(Style.CYAN, 0.6)
	look.shadow_color = Color(0, 0, 0, 0.5)
	look.shadow_size = 16
	look.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", look)
	add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)

## Whether this device has shown a level's card yet.
static func seen(level_id: int) -> bool:
	var marks := ConfigFile.new()
	return marks.load(SEEN) == OK and bool(marks.get_value("seen", "level_%d" % level_id, false))

static func mark_seen(level_id: int) -> void:
	var marks := ConfigFile.new()
	marks.load(SEEN)
	marks.set_value("seen", "level_%d" % level_id, true)
	marks.save(SEEN)

func open(level_id: int) -> void:
	level = level_id
	_fill()
	show()
	mark_seen(level_id)
	await get_tree().process_frame
	panel.reset_size()
	panel.position = ((size - panel.size) / 2.0).floor()
	toggled.emit(true)

func close() -> void:
	if visible:
		hide()
		toggled.emit(false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))

func _fill() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var card: Dictionary = LEVELS.get(level, LEVELS[1])
	var top := HBoxContainer.new()
	body.add_child(top)
	var heading := _text("How Level %d works" % level, 24, Style.TEXT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var keys := _text("H or Esc closes it", 12, Color(Style.TEXT, 0.45), false)
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(keys)
	_section("WHAT YOU DO")
	body.add_child(_text(str(card.do), 15, Color(Style.TEXT, 0.9)))
	_section("CONTROLS")
	for line in card.controls:
		body.add_child(_text("•  " + str(line), 14, Color(Style.TEXT, 0.85)))
	_section("STARS AND STRIKES")
	for line in [str(card.scoring),
			"A hint costs a star. Show answer shows one way to open the gate, which then earns at most 1 star.",
			"Three strikes on a gate and the Chip Chomper drags you back to the gate before it.",
			"Click an open gate in the corridor to go back and try it again."]:
		body.add_child(_text("•  " + line, 14, Color(Style.TEXT, 0.85)))
	_section("KEYS")
	body.add_child(_text("H  this card   ·   I  the guide   ·   Enter  continue   ·   F10  settings", 14, Style.CYAN))
	var done := Button.new()
	done.text = "Got it"
	done.custom_minimum_size = Vector2(160, 40)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled"]:
		done.add_theme_stylebox_override(state, Style.key_style(Style.GREEN, state))
	done.pressed.connect(close)
	body.add_child(done)

func _section(text: String) -> void:
	var label := _text(text, 12, Color(Style.CYAN, 0.8), false)
	label.add_theme_font_override("font", Style.MONO)
	label.custom_minimum_size.y = 22  # A little room above each section.
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	body.add_child(label)

func _text(text: String, size: int, color: Color, wrap := true) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
