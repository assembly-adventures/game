extends Control
## One best completed run per player, level, and Eastern-time week. All ranking happens on the server.

const Style := preload("res://ui/style.gd")
const CircuitBackdrop := preload("res://ui/circuit_backdrop.gd")
const LEVEL_NAMES := ["1 · Registers", "2 · Memory Maze", "3 · Call Stack Tower"]

var level_id := 1
var week_offset := 0
var revision := 0
var week_label: Label
var status_label: Label
var personal: Label
var rows: VBoxContainer
var tabs: Array[Button] = []
var previous_button: Button
var next_button: Button
var current_button: Button
var retry_button: Button
var refresh_button: Button
var timer: Timer
var displayed_week_end := ""

func _ready() -> void:
	_build()
	Settings.changed.connect(_load_board)
	timer = Timer.new()
	timer.wait_time = 60.0
	timer.timeout.connect(_load_board)
	add_child(timer)
	timer.start()
	_load_board()

func _build() -> void:
	add_child(CircuitBackdrop.new())
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 24)
	add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margins.add_child(layout)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 12)
	layout.add_child(navigation)
	var back := Button.new()
	back.text = "◀ Control Center"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://control_center.tscn"))
	navigation.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)
	navigation.add_child(Settings.make_button())
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	layout.add_child(heading)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 4)
	heading.add_child(titles)
	var title := _label("Weekly leaderboard", 30, Style.TEXT)
	title.theme_type_variation = &"TitleLabel"
	titles.add_child(title)
	titles.add_child(_label("A fresh week. Another chance to improve your best.", 16, Color(Style.TEXT, 0.65)))
	refresh_button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	refresh_button.pressed.connect(_load_board)
	heading.add_child(refresh_button)
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 10)
	layout.add_child(levels)
	var group := ButtonGroup.new()
	for i in range(LEVEL_NAMES.size()):
		var tab := Button.new()
		tab.text = LEVEL_NAMES[i]
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.set_pressed_no_signal(i == 0)
		tab.pressed.connect(_choose_level.bind(i + 1))
		levels.add_child(tab)
		tabs.append(tab)
	var period := HBoxContainer.new()
	period.add_theme_constant_override("separation", 12)
	layout.add_child(period)
	previous_button = Button.new()
	previous_button.text = "◀ Previous week"
	previous_button.pressed.connect(_change_week.bind(-1))
	period.add_child(previous_button)
	week_label = _label("This week", 17, Style.CYAN)
	week_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	week_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	period.add_child(week_label)
	next_button = Button.new()
	next_button.text = "Next week ▶"
	next_button.pressed.connect(_change_week.bind(1))
	period.add_child(next_button)
	current_button = Button.new()
	current_button.text = "This week"
	current_button.pressed.connect(func():
		week_offset = 0
		_load_board())
	period.add_child(current_button)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", Style.panel_style())
	layout.add_child(panel)
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 10)
	panel.add_child(board)
	board.add_child(_row("RANK", "UNC ONYEN", "STARS", "MISTAKES", false, true))
	board.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	status_label = _label("Loading standings…", 18, Color(Style.TEXT, 0.7))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board.add_child(status_label)
	retry_button = Button.new()
	retry_button.text = "Try again"
	retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry_button.pressed.connect(_load_board)
	retry_button.hide()
	board.add_child(retry_button)
	personal = _label("", 17, Style.GOLD)
	layout.add_child(personal)
	layout.add_child(_label("Highest stars, then fewest mistakes. Equal results share a rank. Each entry is one completed run.", 14, Color(Style.TEXT, 0.7)))
	layout.add_child(_label("New week: Monday, 12:00 AM Eastern. Random rooms keep each run different. Badges and progress never reset.", 13, Color(Style.TEXT, 0.5)))
	back.grab_focus()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _row(rank: String, onyen: String, stars: String, mistakes: String, mine: bool = false, heading: bool = false) -> Control:
	var box := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Color(Style.CYAN, 0.09) if mine else Color(0.04, 0.075, 0.11, 0.5)
	look.set_corner_radius_all(8)
	look.set_content_margin_all(12)
	if mine:
		look.set_border_width_all(1)
		look.border_color = Color(Style.CYAN, 0.45)
	if heading:
		look.bg_color = Color.TRANSPARENT
	box.add_theme_stylebox_override("panel", look)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var values := [rank, onyen, stars, mistakes]
	for i in range(values.size()):
		var color := Color(Style.TEXT, 0.5) if heading else Style.CYAN if mine else Style.TEXT
		if i == 2 and not heading:
			color = Style.GOLD
		var label := _label(str(values[i]), 12 if heading else 18, color)
		label.add_theme_font_override("font", Style.MONO)
		label.custom_minimum_size.x = [72, 0, 120, 110][i]
		if i == 1:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i > 1:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
	return box

func _choose_level(id: int) -> void:
	level_id = id
	_load_board()

func _change_week(direction: int) -> void:
	week_offset = clampi(week_offset + direction, -52, 0)
	_load_board()

func _load_board() -> void:
	revision += 1
	var requested_revision := revision
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	status_label.show()
	status_label.text = "Loading standings…"
	personal.text = ""
	retry_button.hide()
	next_button.disabled = week_offset == 0
	previous_button.disabled = week_offset == -52
	current_button.disabled = week_offset == 0
	week_label.text = "This week" if week_offset == 0 else "%d week%s ago" % [-week_offset, "" if week_offset == -1 else "s"]
	if Settings.hide_leaderboard:
		status_label.text = "The leaderboard is hidden on this device. You can show it again in Settings."
		refresh_button.disabled = true
		return
	if PlayerData.guest or PlayerData.api_base.is_empty():
		status_label.text = "Sign in with UNC on the hosted game to see the weekly leaderboard.\nGuest play does not appear in the standings."
		refresh_button.disabled = true
		return
	refresh_button.disabled = true
	var result := await PlayerData.api_request("/leaderboard?level_id=%d&week_offset=%d" % [level_id, week_offset])
	if not is_inside_tree() or requested_revision != revision:
		return
	refresh_button.disabled = false
	if not result.ok:
		status_label.text = result.error
		retry_button.show()
		return
	var data: Dictionary = result.data
	week_label.text = str(data.get("week_label", "This week")) + " · Eastern"
	var entries: Array = data.get("entries", [])
	for entry in entries:
		var mine := bool(entry.get("is_me", str(entry.onyen) == PlayerData.onyen))
		rows.add_child(_row(str(int(entry.rank)), str(entry.onyen) + ("  (you)" if mine else ""),
			"%d / %d" % [int(entry.stars), int(entry.get("max_stars", 30))], str(int(entry.mistakes)), mine))
	status_label.visible = entries.is_empty()
	status_label.text = "No visible results for this level this week." if week_offset == 0 \
		else "No visible results for this level in this week."
	var mine = data.get("my_entry")
	if mine is Dictionary:
		var rank_text := "Hidden from classmates" if mine.get("rank") == null else "Your rank: #%d" % int(mine.rank)
		personal.text = "%s  ·  %d stars  ·  %d mistake%s" % [rank_text, int(mine.stars), int(mine.mistakes),
			"" if int(mine.mistakes) == 1 else "s"]
	elif not bool(data.get("leaderboard_visible", PlayerData.leaderboard_visible)):
		personal.text = "Your entry is hidden. Change your visibility anytime in Settings."
	else:
		personal.text = "Finish a new run of this level to join this week's standings." if week_offset == 0 \
			else "You have no completed run recorded for this level in this week."
