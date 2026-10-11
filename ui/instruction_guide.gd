extends Control
## The instruction guide: for each instruction on the current gate, what its abbreviation stands
## for (the letters it takes are lit up), how it's written, and what it does, then the registers the
## gate uses. The level runner opens it from its top bar or with the I key and fills it from the
## room on screen; a click outside the panel, Escape, or I closes it.

signal toggled(open: bool)

const Style := preload("res://ui/style.gd")
const Registers := preload("res://ui/registers.gd")
const WIDTH := 640.0
## Every instruction the game uses, in the order the guide lists them. "name" spells out the
## abbreviation with the letters it takes in {braces}; "form" is how it's written, "does" what it
## does (M[a] is the word of memory at address a), and "more" says the rest. j and la are
## pseudo-instructions: the assembler turns them into real ones.
const INSTRUCTIONS := {
	"add": {"name": "{add}", "form": "add rd, rs1, rs2", "does": "rd = rs1 + rs2",
		"more": "Adds two registers. Past 32 bits the sum wraps around."},
	"sub": {"name": "{sub}tract", "form": "sub rd, rs1, rs2", "does": "rd = rs1 - rs2",
		"more": "Subtracts rs2 from rs1."},
	"mul": {"name": "{mul}tiply", "form": "mul rd, rs1, rs2", "does": "rd = rs1 * rs2",
		"more": "Multiplies two registers and keeps the low 32 bits of the product."},
	"div": {"name": "{div}ide", "form": "div rd, rs1, rs2", "does": "rd = rs1 / rs2",
		"more": "Divides as signed numbers, rounding toward zero. Dividing by 0 gives -1 (all ones)."},
	"rem": {"name": "{rem}ainder", "form": "rem rd, rs1, rs2", "does": "rd = rs1 % rs2",
		"more": "The remainder of the signed division; it has the dividend's sign. By 0 it gives rs1 back."},
	"and": {"name": "bitwise {and}", "form": "and rd, rs1, rs2", "does": "rd = rs1 & rs2",
		"more": "A bit is 1 only where both registers have a 1."},
	"or": {"name": "bitwise {or}", "form": "or rd, rs1, rs2", "does": "rd = rs1 | rs2",
		"more": "A bit is 1 where either register has a 1."},
	"xor": {"name": "bitwise e{x}clusive {or}", "form": "xor rd, rs1, rs2", "does": "rd = rs1 ^ rs2",
		"more": "A bit is 1 where the two registers differ."},
	"sll": {"name": "{s}hift {l}eft {l}ogical", "form": "sll rd, rs1, rs2", "does": "rd = rs1 << rs2",
		"more": "Moves the bits left by the amount in rs2, filling in 0s."},
	"srl": {"name": "{s}hift {r}ight {l}ogical", "form": "srl rd, rs1, rs2", "does": "rd = rs1 >> rs2",
		"more": "Moves the bits right by the amount in rs2, filling in 0s."},
	"sra": {"name": "{s}hift {r}ight {a}rithmetic", "form": "sra rd, rs1, rs2", "does": "rd = rs1 >> rs2",
		"more": "Moves the bits right by the amount in rs2, copying the sign bit, so a negative number stays negative."},
	"slt": {"name": "{s}et if {l}ess {t}han", "form": "slt rd, rs1, rs2", "does": "rd = (rs1 < rs2) ? 1 : 0",
		"more": "Compares the two registers as signed numbers."},
	"sltu": {"name": "{s}et if {l}ess {t}han, {u}nsigned", "form": "sltu rd, rs1, rs2", "does": "rd = (rs1 < rs2) ? 1 : 0",
		"more": "Compares the two registers as unsigned numbers."},
	"addi": {"name": "{add} {i}mmediate", "form": "addi rd, rs1, imm", "does": "rd = rs1 + imm",
		"more": "Adds a constant from -2048 to 2047; a negative one subtracts. addi x0, x0, 0 does nothing at all (a no-op)."},
	"andi": {"name": "{and} {i}mmediate", "form": "andi rd, rs1, imm", "does": "rd = rs1 & imm",
		"more": "Keeps only the bits that are 1 in the constant, like a mask."},
	"ori": {"name": "{or} {i}mmediate", "form": "ori rd, rs1, imm", "does": "rd = rs1 | imm",
		"more": "Turns on the bits that are 1 in the constant."},
	"xori": {"name": "{xor} {i}mmediate", "form": "xori rd, rs1, imm", "does": "rd = rs1 ^ imm",
		"more": "Flips the bits that are 1 in the constant."},
	"slli": {"name": "{s}hift {l}eft {l}ogical {i}mmediate", "form": "slli rd, rs1, imm", "does": "rd = rs1 << imm",
		"more": "Moves the bits left by imm places, filling in 0s. Each place doubles the value."},
	"srli": {"name": "{s}hift {r}ight {l}ogical {i}mmediate", "form": "srli rd, rs1, imm", "does": "rd = rs1 >> imm",
		"more": "Moves the bits right by imm places, filling in 0s. Each place halves an unsigned value."},
	"srai": {"name": "{s}hift {r}ight {a}rithmetic {i}mmediate", "form": "srai rd, rs1, imm", "does": "rd = rs1 >> imm",
		"more": "Moves the bits right by imm places, copying the sign bit. Each place halves a signed value, rounding down."},
	"slti": {"name": "{s}et if {l}ess {t}han {i}mmediate", "form": "slti rd, rs1, imm", "does": "rd = (rs1 < imm) ? 1 : 0",
		"more": "Compares a register with a constant, as signed numbers."},
	"sltiu": {"name": "{s}et if {l}ess {t}han {i}mmediate, {u}nsigned", "form": "sltiu rd, rs1, imm",
		"does": "rd = (rs1 < imm) ? 1 : 0", "more": "Compares a register with a constant, as unsigned numbers."},
	"lw": {"name": "{l}oad {w}ord", "form": "lw rd, offset(rs1)", "does": "rd = M[rs1 + offset]",
		"more": "Copies the 4-byte word at address rs1 + offset into rd. Words sit at addresses that are multiples of 4."},
	"sw": {"name": "{s}tore {w}ord", "form": "sw rs2, offset(rs1)", "does": "M[rs1 + offset] = rs2",
		"more": "Copies rs2 into the word at address rs1 + offset. No register changes."},
	"beq": {"name": "{b}ranch if {eq}ual", "form": "beq rs1, rs2, label", "does": "if (rs1 == rs2) PC = label",
		"more": "Jumps to the label when the registers are equal; otherwise the next instruction runs."},
	"bne": {"name": "{b}ranch if {n}ot {e}qual", "form": "bne rs1, rs2, label", "does": "if (rs1 != rs2) PC = label",
		"more": "Jumps to the label when the registers differ; otherwise the next instruction runs."},
	"blt": {"name": "{b}ranch if {l}ess {t}han", "form": "blt rs1, rs2, label", "does": "if (rs1 < rs2) PC = label",
		"more": "Compares as signed numbers. Otherwise the next instruction runs."},
	"bge": {"name": "{b}ranch if {g}reater than or {e}qual", "form": "bge rs1, rs2, label",
		"does": "if (rs1 >= rs2) PC = label", "more": "Compares as signed numbers. Otherwise the next instruction runs."},
	"bltu": {"name": "{b}ranch if {l}ess {t}han, {u}nsigned", "form": "bltu rs1, rs2, label",
		"does": "if (rs1 < rs2) PC = label", "more": "Compares as unsigned numbers. Otherwise the next instruction runs."},
	"bgeu": {"name": "{b}ranch if {g}reater than or {e}qual, {u}nsigned", "form": "bgeu rs1, rs2, label",
		"does": "if (rs1 >= rs2) PC = label", "more": "Compares as unsigned numbers. Otherwise the next instruction runs."},
	"jal": {"name": "{j}ump {a}nd {l}ink", "form": "jal rd, label", "does": "rd = PC + 4; PC = label",
		"more": "Calls a function: it saves the address of the next instruction (the return address) in rd, usually ra, then jumps."},
	"jalr": {"name": "{j}ump {a}nd {l}ink {r}egister", "form": "jalr rd, offset(rs1)", "does": "rd = PC + 4; PC = rs1 + offset",
		"more": "Jumps to an address held in a register, plus the offset. Functions return this way, to the address in ra."},
	"jr": {"name": "{j}ump {r}egister", "pseudo": true, "form": "jr rs1", "does": "PC = rs1",
		"more": "Short for jalr x0, 0(rs1). jr ra returns from a function."},
	"ret": {"name": "{ret}urn", "pseudo": true, "form": "ret", "does": "PC = ra",
		"more": "Short for jalr x0, 0(ra): it jumps back to the address in ra."},
	"j": {"name": "{j}ump", "pseudo": true, "form": "j label", "does": "PC = label",
		"more": "Short for jal x0, label: it jumps without saving a return address."},
	"la": {"name": "{l}oad {a}ddress", "pseudo": true, "form": "la rd, label", "does": "rd = address of label",
		"more": "Puts the address of a label, like an array's first word, in rd."},
	"label": {"name": "label", "form": "name:", "does": "names an address",
		"more": "Marks the address of the next instruction so branches and jumps can go there. A label isn't an instruction and takes no space."},
}
## The registers by role, in the order the guide lists them.
const REGISTER_GROUPS := [
	{"short": "pc", "members": ["pc"], "role": "program counter",
		"more": "The address of the instruction running now. It moves 4 bytes on after each instruction, unless a branch or jump sets it."},
	{"short": "x0", "members": ["x0"], "role": "the zero register",
		"more": "Always holds 0; writing to it does nothing."},
	{"short": "ra", "members": ["ra"], "role": "return address",
		"more": "Where a function returns to. jal saves it."},
	{"short": "sp", "members": ["sp"], "role": "stack pointer",
		"more": "The address of the top of the stack. The stack grows down, toward lower addresses."},
	{"short": "a0–a7", "members": ["a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"], "role": "arguments",
		"more": "Values passed into a function; a0 also carries the value it returns. In the maze, a0 holds the robot's address."},
	{"short": "t0–t6", "members": ["t0", "t1", "t2", "t3", "t4", "t5", "t6"], "role": "temporaries",
		"more": "Scratch registers. A function call may change them."},
	{"short": "s0–s11", "members": ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11"],
		"role": "saved registers", "more": "A function that changes them must put them back before it returns."},
]

var panel: PanelContainer
var scroll: ScrollContainer
var entries: VBoxContainer

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # A click outside the panel lands here and closes it.
	visible = false
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	var look := Style.panel_style()
	look.bg_color = Color(Style.BG, 0.98)
	look.border_color = Color(Style.CYAN, 0.55)
	look.shadow_color = Color(0, 0, 0, 0.5)
	look.shadow_size = 14
	look.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", look)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var heading := Label.new()
	heading.text = "Instruction guide"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size", 22)
	top.add_child(heading)
	var keys := Label.new()
	keys.text = "I or Esc closes it"
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", Color(Style.TEXT, 0.45))
	top.add_child(keys)
	var close_button := Button.new()
	close_button.text = "Close ×"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	top.add_child(close_button)
	var legend := Label.new()
	legend.text = "rd is the register an instruction writes; rs1 and rs2 are registers it reads. imm and offset are " \
		+ "numbers in the instruction, and M[a] is the word of memory at address a."
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.add_theme_font_size_override("font_size", 13)
	legend.add_theme_color_override("font_color", Color(Style.TEXT, 0.6))
	column.add_child(legend)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	entries = VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries.add_theme_constant_override("separation", 12)
	scroll.add_child(entries)

## Opens the guide for a room, its panel hanging below `anchor` with its right edge there. `room`
## holds "lines", the assembly the room shows or lets the player write, and optionally "registers"
## it shows besides those (like pc).
func open(room: Dictionary, anchor: Vector2) -> void:
	_fill(room.get("lines", []), room.get("registers", []))
	show()
	panel.modulate.a = 0.0
	scroll.custom_minimum_size.y = 0.0
	# Wrapped text measures itself once laid out, so the panel is sized a couple of frames later.
	await get_tree().process_frame
	await get_tree().process_frame
	if not visible:
		return
	var room_left := size.y - anchor.y - 16.0
	var chrome := panel.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = clampf(entries.get_combined_minimum_size().y, 60.0, maxf(room_left - chrome, 60.0))
	panel.reset_size()
	panel.position = Vector2(clampf(anchor.x - panel.size.x, 16.0, maxf(size.x - panel.size.x - 16.0, 16.0)), anchor.y)
	var tween := create_tween().set_parallel()
	tween.tween_property(panel, "modulate:a", 1.0, 0.12)
	tween.tween_property(panel, "position:y", anchor.y, 0.12).from(anchor.y - 8.0)
	scroll.scroll_vertical = 0
	toggled.emit(true)

func close() -> void:
	if visible:
		hide()
		toggled.emit(false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		close()
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))

func _fill(lines: Array, extra_registers: Array) -> void:
	for child in entries.get_children():
		entries.remove_child(child)
		child.queue_free()
	var found := instructions_in(lines)
	if not found.is_empty():
		entries.add_child(_heading("Instructions on this gate"))
		for op in found:
			entries.add_child(_instruction(op, _first_label(lines)))
	var used := registers_in(lines, extra_registers)
	if not used.is_empty():
		entries.add_child(_heading("Registers on this gate"))
		for group in REGISTER_GROUPS:
			var present: Array = group.members.filter(func(name): return name in used)
			if not present.is_empty():
				entries.add_child(_register(group, present))

## The instructions in `lines`, in the guide's order (a line ending in ":" is a label).
static func instructions_in(lines: Array) -> Array:
	var seen := {}
	for line in lines:
		var text := str(line).strip_edges()
		if not text.is_empty():
			seen["label" if text.ends_with(":") else text.get_slice(" ", 0)] = true
	return INSTRUCTIONS.keys().filter(func(op): return seen.has(op))

## The registers named in `lines`, plus `extra`, by ABI name.
static func registers_in(lines: Array, extra: Array = []) -> Array:
	var used := {}
	for name in extra:
		used[str(name)] = true
	for line in lines:
		var text := str(line)
		if text.ends_with(":"):
			continue
		var tokens := text.replace(",", " ").replace("(", " ").replace(")", " ").split(" ", false)
		for k in range(1, tokens.size()):
			var token := tokens[k]
			if token in Registers.NAMES or token in ["zero", "fp"] or token.begins_with("x") and token.substr(1).is_valid_int():
				used[Registers.abi(token)] = true
	return used.keys()

static func color_of(op: String) -> Color:
	if op in ["lw", "la"]:
		return Style.CYAN
	if op == "sw":
		return Style.ORANGE
	if op == "label":
		return Style.GREEN
	if op.begins_with("b") or op.begins_with("j"):
		return Style.PURPLE
	return Style.GOLD

## A name with its {lettered} parts lit in `color`, as BBCode.
static func spelled(name: String, color: Color) -> String:
	return name.replace("{", "[color=#%s]" % color.to_html(false)).replace("}", "[/color]")

static func _first_label(lines: Array) -> String:
	for line in lines:
		if str(line).ends_with(":"):
			return str(line)
	return "name:"

func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(Style.TEXT, 0.5))
	return label

func _instruction(op: String, label_example: String) -> Control:
	var info: Dictionary = INSTRUCTIONS[op]
	var color := color_of(op)
	var name := spelled(str(info.name), color)
	if info.get("pseudo", false):
		name += "   [font_size=12][color=#%s]pseudo-instruction[/color][/font_size]" % Color(Style.TEXT, 0.5).to_html()
	return _entry(label_example if op == "label" else op, color, name, [str(info.form), str(info.does)], str(info.more))

## A group of registers, titled with the x-name of each one on the gate (t0 = x5).
func _register(group: Dictionary, present: Array) -> Control:
	var names: Array = []
	for name in present:
		if name not in ["pc", "x0"]:
			names.append("%s = x%d" % [name, Registers.number(name)])
	var title := str(group.role)
	if not names.is_empty():
		title += "   [font_size=13][color=#%s]%s[/color][/font_size]" % [Color(Style.TEXT, 0.55).to_html(),
			", ".join(PackedStringArray(names))]
	return _entry(str(group.short), Style.CYAN.lightened(0.3), title, [], str(group.more))

## One entry: a short code on the left; a title, an optional line of code, and a sentence beside it.
func _entry(code: String, color: Color, title: String, forms: Array, more: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var short := Label.new()
	short.text = code
	short.custom_minimum_size = Vector2(76, 0)
	short.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # Level with the entry's title.
	short.add_theme_font_override("font", Style.MONO)
	short.add_theme_font_size_override("font_size", 19)
	short.add_theme_color_override("font_color", color)
	row.add_child(short)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var heading := RichTextLabel.new()
	heading.bbcode_enabled = true
	heading.fit_content = true
	heading.scroll_active = false
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_font_size_override("normal_font_size", 17)
	heading.add_theme_color_override("default_color", Style.TEXT)
	heading.text = title
	text.add_child(heading)
	if not forms.is_empty():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 18)
		for part in [[forms[0], Color(Style.TEXT, 0.6)], [forms[1], Style.CYAN]]:
			var label := Label.new()
			label.text = part[0]
			label.add_theme_font_override("font", Style.MONO)
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_color", part[1])
			line.add_child(label)
		text.add_child(line)
	var detail := Label.new()
	detail.text = more
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", Color(Style.TEXT, 0.82))
	text.add_child(detail)
	return row
