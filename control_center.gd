extends Control
## The Control Center: a top-down motherboard where each level is a chip. Chips glow once a
## level is open and turn green when its badge is earned. The robot waits beside the next chip
## to play, and the Chip Chomper prowls the bus along the bottom of the board.

const CircuitBackdrop := preload("res://ui/circuit_backdrop.gd")
const Characters := preload("res://ui/characters.gd")
const Style := preload("res://ui/style.gd")
const GRAYSCALE := preload("res://badge_grayscale.gdshader")

## Each level's place on the board (as fractions of the board), badge, and scene. The robot
## travels them in this order: along the top row, down, and back along the bottom row. A level
## without a scene stays locked even if the server marks it active.
const LEVELS := [
	{"id": 1, "name": "Basic RISC-V Commands", "at": Vector2(0.2, 0.22), "badge": "badge_1", "icon": "res://images/1.svg",
		"scene": "res://levels/level_1/risc_v_level.tscn"},
	{"id": 2, "name": "Opcode", "at": Vector2(0.5, 0.22), "badge": "badge_2", "icon": "res://images/2.svg"},
	{"id": 3, "name": "Pipelining", "at": Vector2(0.8, 0.22), "badge": "badge_3", "icon": "res://images/3.svg"},
	{"id": 4, "name": "The Stack", "at": Vector2(0.8, 0.74), "badge": "badge_4", "icon": "res://images/4.svg"},
	{"id": 5, "name": "Code Tracing", "at": Vector2(0.5, 0.74), "badge": "badge_5", "icon": "res://images/5.svg"},
	{"id": 6, "name": "Code Writing", "at": Vector2(0.2, 0.74), "badge": "badge_6", "icon": "res://images/6.svg"},
	{"id": 7, "name": "Challenge", "at": Vector2(0.5, 0.48), "badge": "challenge_badge", "icon": "res://images/7.svg",
		"core": true},
]

var board
var chips := {}
var status_label: Label
var retry_button: Button
var guest_button: Button
var sound_button: Button
var progress_bar: ProgressBar
var badge_count: Label

func _ready() -> void:
	get_tree().paused = false
	add_child(CircuitBackdrop.new())
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 20)
	add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margins.add_child(layout)
	layout.add_child(_header())
	board = Board.new()
	for level in LEVELS:
		var chip := Chip.new(level)
		chip.pressed.connect(func(): get_tree().change_scene_to_file(level.scene))
		board.add_chip(chip)
		chips[level.id] = chip
	layout.add_child(board)
	layout.add_child(_footer())
	PlayerData.profile_changed.connect(_update_progress)
	_load_profile()

func _header() -> Control:
	var header := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Control Center"
	titles.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "The Chip Chomper corrupted the processor. Fix it one chip at a time."
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(Style.TEXT, 0.6))
	titles.add_child(subtitle)
	var progress := VBoxContainer.new()
	progress.custom_minimum_size = Vector2(260, 0)
	progress.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(progress)
	badge_count = Label.new()
	badge_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress.add_child(badge_count)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 16)
	progress_bar.show_percentage = false
	progress.add_child(progress_bar)
	return header

func _footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wrapping keeps a long error message from pushing the buttons (and the board) off screen.
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(220, 0)
	status_label.add_theme_color_override("font_color", Color(Style.TEXT, 0.75))
	footer.add_child(status_label)
	retry_button = Button.new()
	retry_button.text = "Retry loading saved progress"
	retry_button.pressed.connect(_load_profile)
	footer.add_child(retry_button)
	guest_button = Button.new()
	guest_button.text = "Play as guest (progress is not saved)"
	guest_button.pressed.connect(func():
		PlayerData.start_guest()
		_load_profile())
	footer.add_child(guest_button)
	var fullscreen_button := Button.new()
	fullscreen_button.text = "Full screen (F11)"
	fullscreen_button.pressed.connect(PlayerData.toggle_fullscreen)
	footer.add_child(fullscreen_button)
	sound_button = Button.new()
	sound_button.pressed.connect(func():
		Audio.set_enabled(not Audio.enabled)
		_update_sound_label())
	footer.add_child(sound_button)
	_update_sound_label()
	return footer

func _update_sound_label() -> void:
	sound_button.text = "Sound: on" if Audio.enabled else "Sound: off"

func _load_profile() -> void:
	retry_button.hide()
	guest_button.hide()
	status_label.text = "Loading saved progress…"
	if not await PlayerData.refresh_profile():
		status_label.text = PlayerData.last_error
		retry_button.show()
		guest_button.show()
		return
	var active := {}
	var completed := {}
	for level in PlayerData.levels:
		active[int(level.id)] = bool(level.is_active)
		completed[int(level.id)] = bool(level.get("completed", false))
	for level in LEVELS:
		var done: bool = completed.get(level.id, false) or level.badge in PlayerData.earned_badges
		chips[level.id].set_state(active.get(level.id, false) and level.has("scene"), done)
	board.place_characters()
	if PlayerData.guest:
		status_label.text = "Guest mode: Level 1 only. Progress resets when you reload."
	else:
		status_label.text = "Progress is saved to your UNC account."
	_update_progress()

func _update_progress() -> void:
	progress_bar.value = PlayerData.get_progress_ratio() * 100.0
	var earned := PlayerData.earned_badges.size()
	badge_count.text = "%d badge%s earned" % [earned, "" if earned == 1 else "s"]


## The circuit board itself: traces between the chips, the bus the Chomper patrols, and the
## two characters. Chips are child buttons positioned by fraction of the board.
class Board extends Control:
	const PATH := [1, 2, 3, 4, 5, 6]
	var chips: Array = []
	var robot
	var chomper
	var patrol := 0.0
	var heading := 1.0
	var t := 0.0

	func _init() -> void:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(_layout)

	func _ready() -> void:
		chomper = Characters.Chomper.new()
		add_child(chomper)
		robot = Characters.Robot.new()
		add_child(robot)
		_layout()

	func add_chip(chip) -> void:
		chips.append(chip)
		add_child(chip)

	func _chip(id: int):
		for chip in chips:
			if chip.level.id == id:
				return chip
		return null

	func _layout() -> void:
		for chip in chips:
			chip.size = chip.custom_minimum_size
			chip.position = (size * chip.level.at - chip.size / 2).round()
		place_characters()

	## The robot stands on the trace just before the next chip to play (or beside the last one
	## finished, cheering, once nothing new is open).
	func place_characters() -> void:
		if robot == null:
			return
		var target = null
		var last_done = null
		for id in PATH:
			var chip = _chip(id)
			if chip.complete:
				last_done = chip
			elif chip.unlocked and target == null:
				target = chip
		var chip = target if target != null else last_done if last_done != null else _chip(PATH[0])
		var bottom_row: bool = chip.level.at.y > 0.5
		var side: float = chip.position.x + chip.size.x + 36 if bottom_row else chip.position.x - 36
		robot.position = Vector2(side, chip.position.y + chip.size.y / 2 + 32)
		robot.cheer = 1000.0 if target == null and last_done != null else 0.0

	func _process(delta: float) -> void:
		t += delta
		# The Chomper paces the bus under the bottom row, turning round at each end.
		var left := 70.0
		var right := size.x - 70.0
		patrol += heading * delta * 70.0
		if patrol > right - left or patrol < 0.0:
			heading = -heading
			patrol = clampf(patrol, 0.0, right - left)
		if chomper:
			# Drawn a little smaller here so it clears the bottom row of chips. It leans into its
			# turns rather than flipping, since flipping would mirror the text on the window.
			chomper.position = Vector2(left + patrol, size.y - 30)
			chomper.scale = Vector2(0.8, 0.8)
			chomper.rotation = lerpf(chomper.rotation, 0.06 * heading, minf(1.0, delta * 3.0))
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var rect := Rect2(Vector2.ZERO, size)
		Style.rounded(self, rect, Color(0.05, 0.1, 0.13, 0.94), 18, Color(Style.CYAN, 0.3), 2)
		for x in range(20, int(size.x), 24):
			draw_line(Vector2(x, 6), Vector2(x, size.y - 6), Color(Style.CYAN, 0.025))
		for corner in [Vector2(18, 18), Vector2(size.x - 18, 18), Vector2(18, size.y - 18), Vector2(size.x - 18, size.y - 18)]:
			draw_circle(corner, 7, Color(0, 0, 0, 0.5))
			draw_arc(corner, 7, 0, TAU, 16, Color(Style.GOLD, 0.5), 2, true)
		var core = _chip(7)
		# Thin traces from every chip to the CPU core, then the main bus in play order.
		for id in PATH:
			var chip = _chip(id)
			_trace(_center(chip), _center(core), Color(Style.CYAN, 0.12), 2.0)
		for i in range(PATH.size() - 1):
			var from = _chip(PATH[i])
			var lit: bool = from.complete
			_trace(_center(from), _center(_chip(PATH[i + 1])), Color(Style.GREEN, 0.75) if lit else Color(Style.CYAN, 0.22),
				6.0, lit)
		var bus := size.y - 34
		draw_line(Vector2(40, bus), Vector2(size.x - 40, bus), Color(Style.PURPLE, 0.25), 4)
		for k in range(8):
			var x := fmod(t * 60.0 + k * size.x / 8.0, size.x - 80) + 40
			draw_circle(Vector2(x, bus), 2.5, Color(Style.PURPLE, 0.6))
		draw_string(Style.MONO, Vector2(size.x - 250, size.y - 10), "AA-311 MAINBOARD  REV 1.0", HORIZONTAL_ALIGNMENT_LEFT,
			-1, 11, Color(Style.TEXT, 0.25))
		for chip in chips:
			draw_string(Style.MONO, chip.position + Vector2(0, -12), "U%d" % chip.level.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(Style.TEXT, 0.3))

	func _center(chip) -> Vector2:
		return chip.position + chip.size / 2

	## Board traces run in right angles: across first, then up or down.
	func _trace(from: Vector2, to: Vector2, color: Color, width: float, pulse: bool = false) -> void:
		var bend := Vector2(to.x, from.y)
		if pulse:
			draw_polyline(PackedVector2Array([from, bend, to]), Color(color, 0.18), width * 2.5, true)
		draw_polyline(PackedVector2Array([from, bend, to]), color, width, true)
		if pulse:
			var length := from.distance_to(bend) + bend.distance_to(to)
			var along := fmod(t * 120.0, maxf(length, 1.0))
			var dot := from.move_toward(bend, along) if along < from.distance_to(bend) \
				else bend.move_toward(to, along - from.distance_to(bend))
			draw_circle(dot, 4, Color.WHITE)


## One level as a chip on the board: pins along the top and bottom, the badge (greyed out until
## earned), and the level's name and status. It is a real button, so it takes focus and clicks.
class Chip extends Button:
	var level: Dictionary
	var unlocked := false
	var complete := false
	var badge: TextureRect
	var t := 0.0

	func _init(entry: Dictionary) -> void:
		level = entry
		custom_minimum_size = Vector2(250, 104)
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		badge = TextureRect.new()
		badge.texture = load(entry.icon)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size = Vector2(64, 64)
		badge.position = Vector2(16, 20)
		var gray := ShaderMaterial.new()
		gray.shader = GRAYSCALE
		badge.material = gray
		add_child(badge)
		set_state(false, false)

	func set_state(open: bool, done: bool) -> void:
		unlocked = open
		complete = done
		disabled = not open
		badge.material.set_shader_parameter("gray_amount", 0.0 if done else 1.0)
		badge.modulate.a = 1.0 if open or done else 0.4
		tooltip_text = "Replay this level" if done and open else "Start or resume this level" if open else "Coming soon"

	func _process(delta: float) -> void:
		t += delta
		badge.position.y = 20.0 + _lift()
		queue_redraw()

	func _lift() -> float:
		return -3.0 if is_hovered() and not disabled else 0.0

	func _draw() -> void:
		var font := get_theme_default_font()
		var core: bool = level.get("core", false)
		var lift := _lift()
		var body := Rect2(Vector2(0, lift), size)
		var accent := Style.GREEN if complete else Style.CYAN if unlocked else Style.DIM
		Style.rounded(self, Rect2(Vector2(4, 7), size), Color(0, 0, 0, 0.35), 10)
		var pins := 7
		for k in range(pins):
			var x := 22.0 + k * (size.x - 44.0) / (pins - 1)
			var pin := Color(Style.GOLD, 0.8) if complete else Color("7d8494")
			draw_rect(Rect2(x - 4, lift - 6, 8, 7), pin)
			draw_rect(Rect2(x - 4, size.y + lift - 1, 8, 7), pin)
		if unlocked and not complete:
			Style.rounded(self, body.grow(5), Color(accent, 0.08 + 0.08 * sin(t * 3.0)), 15)
		Style.rounded(self, body, Color("121924"), 10, Color(accent, 0.9 if unlocked or complete else 0.35), 2)
		draw_circle(Vector2(0, size.y / 2 + lift), 8, Color("0b1018"))
		var tag := "CPU CORE" if core else "LEVEL %d" % level.id
		var status := "✓ Complete" if complete else "▶ Play" if unlocked else "Locked"
		var status_color := Style.GREEN if complete else Style.GOLD if unlocked else Color(Style.TEXT, 0.4)
		draw_string(Style.MONO, Vector2(94, 28 + lift), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(accent, 0.9))
		draw_multiline_string(font, Vector2(94, 50 + lift), level.name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 104, 17, 2,
			Style.TEXT)
		draw_string(font, Vector2(94, size.y - 13 + lift), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_color)
		if not unlocked and not complete:
			var lock := Vector2(size.x - 22, 22 + lift)
			draw_arc(lock + Vector2(0, -3), 5, PI, TAU, 10, Color(Style.TEXT, 0.4), 2, true)
			draw_rect(Rect2(lock + Vector2(-7, -3), Vector2(14, 11)), Color(Style.TEXT, 0.4))
		if has_focus():
			Style.rounded(self, body.grow(4), Color(0, 0, 0, 0), 13, Style.GOLD, 2)
