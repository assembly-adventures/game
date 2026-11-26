extends Control
## Runs one level of puzzle gates: loads or resumes the run, shows each unsolved gate, submits
## attempts, plays the Chip Chomper's strikes and setbacks, and awards the badge. Each level's
## scene sets which level it is; the gate's payload kind picks the puzzle that plays inside it.
## Two things work the same on every gate: Show answer (top bar) fetches the gate's reference
## answer, which caps the gate at one star, and a click on an open gate in the corridor goes back
## to it, closing it until it is opened again.

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const ROOMS := {"moves": PuzzleRoom, "maze": preload("res://levels/level_2/maze_room.gd"),
	"code": preload("res://levels/level_2/code_room.gd"), "walk": preload("res://levels/level_3/walk_room.gd"),
	"wave": preload("res://levels/level_4/wave_room.gd"), "table": preload("res://levels/level_4/table_room.gd")}
const Corridor := preload("res://ui/corridor.gd")
const CircuitBackdrop := preload("res://ui/circuit_backdrop.gd")
const InstructionGuide := preload("res://ui/instruction_guide.gd")
const HowToPlay := preload("res://ui/how_to_play.gd")
const Style := preload("res://ui/style.gd")

@export var level_id := 1
@export_file("*.svg") var badge_icon := "res://images/1.svg"
@export_multiline var finish_line := "The robot reached the CPU and the Chip Chomper ran off. Basic Instructions Master!"

var run: Dictionary = {}
var question: Dictionary = {}
var question_index: int = 0
var solved: Array = []
var strikes: Dictionary = {}
var choices: Array = []
var tiles: Array = []
var selectors: Array = []
var puzzle = null  # The current gate's room, chosen by its payload kind (see ROOMS).
var request_id: String = ""
var pending_answer: Dictionary = {}
var busy: bool = false
var ready_for_next: bool = false
var started_at: int = 0
var title: Label
var prompt_label: Label
var detail_label: Label
var code_box: PanelContainer
var code_label: Label
var options_box: VBoxContainer
var feedback: Label
var feedback_box: PanelContainer  # The bar the message sits in; shown only when there is one.
var feedback_tone := "info"  # What the next message is: "bad" (a strike or an error), "good" (an open gate), or "info".
var shown_feedback := ""
var submit: Button
var retry: Button
var corridor
var menu_button: Button
var learning_failed := false
var guide_button: Button
var guide  # The instruction guide, drawn over everything when open.
var help  # The level's how-to-play card, drawn over everything when open.
var help_button: Button
var status_line: RichTextLabel  # Under the title: the stars the gate can still earn, and its strikes.
var shown_status := ""
var feedback_icon: Label
var layout_root: MarginContainer
var answer_button: Button
var answer_box: PanelContainer
var answer_label: Label
var answers: Dictionary = {}  # Gate ID: its reference answer's lines, once the player has asked for them.
var answer_asked := false  # Show answer was pressed once; the next press shows it.
var back_asked := -1  # The open gate a click asked to go back to; a second click on it goes.
var finished := false

func _ready() -> void:
	_build_ui()
	LearningLog.saved.connect(_learning_saved)
	_load_run()

## Under the title: the stars this gate can still earn (dimmed where one is lost) and its strikes.
func _update_status() -> void:
	var text := ""
	if puzzle != null and not finished and not question.is_empty():
		var id := str(question.id)
		var can := clampi(int(puzzle.stars()), 1, 3)
		if answers.has(id) or bool(run.get("question_stats", {}).get(id, {}).get("answer_shown", false)):
			can = 1
		var lit := "[color=#%s]%s[/color][color=#%s]%s[/color]" % [Style.GOLD.to_html(false), "★".repeat(can),
			Color(Style.TEXT, 0.25).to_html(), "★".repeat(3 - can)]
		var count := int(strikes.get(id, 0))
		var strike_color := Style.RED if count > 0 else Color(Style.TEXT, 0.6)
		text = "[center][color=#%s]%s[/color] %s   [color=#%s]·   Strikes %d of %d[/color][/center]" % [
			Color(Style.TEXT, 0.6).to_html(), "Earned" if ready_for_next else "Can still earn", lit,
			strike_color.to_html(), count, PuzzleRoom.STRIKES]
	if text != shown_status:
		shown_status = text
		status_line.text = text
		status_line.visible = not text.is_empty()

## The message bar follows its text: hidden when there is nothing to say, and tinted by the kind
## of news, red for a strike or an error, green for an open gate, cyan for anything else.
func _process(_delta: float) -> void:
	_update_status()
	if feedback == null or feedback.text == shown_feedback:
		return
	shown_feedback = feedback.text
	feedback_box.visible = not shown_feedback.is_empty()
	var tint: Color = {"bad": Style.RED, "good": Style.GREEN}.get(feedback_tone, Style.CYAN)
	feedback_icon.text = {"bad": "✗", "good": "✓"}.get(feedback_tone, "›")
	feedback_icon.add_theme_color_override("font_color", tint)
	feedback_tone = "info"
	var look := StyleBoxFlat.new()
	look.bg_color = Color(tint, 0.1)
	look.border_color = Color(tint, 0.75)
	look.border_width_left = 4
	look.set_corner_radius_all(8)
	look.content_margin_left = 14
	look.content_margin_right = 14
	look.content_margin_top = 8
	look.content_margin_bottom = 8
	feedback_box.add_theme_stylebox_override("panel", look)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := CircuitBackdrop.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margins := MarginContainer.new()
	layout_root = margins
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 20)
	add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margins.add_child(layout)
	# Top bar: back to the Control Center, the gate count, the instruction guide, and whether progress
	# is kept.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	layout.add_child(bar)
	menu_button = Button.new()
	menu_button.text = "◀ Control Center"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.pressed.connect(_return_to_center)
	bar.add_child(menu_button)
	var heading_box := VBoxContainer.new()
	heading_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_box.alignment = BoxContainer.ALIGNMENT_CENTER
	heading_box.add_theme_constant_override("separation", 0)
	bar.add_child(heading_box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	heading_box.add_child(title)
	status_line = RichTextLabel.new()
	status_line.bbcode_enabled = true
	status_line.fit_content = true
	status_line.scroll_active = false
	status_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_line.add_theme_font_size_override("normal_font_size", 14)
	heading_box.add_child(status_line)
	guide_button = Button.new()
	guide_button.text = "Instruction guide ▼"
	guide_button.tooltip_text = "What each instruction on this gate means (I)"
	guide_button.focus_mode = Control.FOCUS_NONE
	guide_button.pressed.connect(_toggle_guide)
	guide_button.hide()
	bar.add_child(guide_button)
	answer_button = Button.new()
	answer_button.tooltip_text = "See one way to open this gate. A gate opened after seeing its answer earns 1 star."
	answer_button.focus_mode = Control.FOCUS_NONE
	answer_button.pressed.connect(_toggle_answer)
	answer_button.hide()
	bar.add_child(answer_button)
	# Whether progress is kept, as a small pill: gold for a guest, whose progress resets on reload.
	var saving := Label.new()
	var tint := Style.GOLD if PlayerData.guest else Style.GREEN
	saving.text = "GUEST · NOT SAVED" if PlayerData.guest else "✓ SAVED"
	saving.tooltip_text = "Guest progress resets when you reload the page." if PlayerData.guest \
		else "Progress saves to your UNC account automatically."
	saving.mouse_filter = Control.MOUSE_FILTER_PASS
	saving.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	saving.add_theme_font_override("font", Style.MONO)
	saving.add_theme_font_size_override("font_size", 11)
	saving.add_theme_color_override("font_color", tint)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(tint, 0.1)
	pill.border_color = Color(tint, 0.6)
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(12)
	pill.content_margin_left = 10
	pill.content_margin_right = 10
	pill.content_margin_top = 4
	pill.content_margin_bottom = 4
	saving.add_theme_stylebox_override("normal", pill)
	bar.add_child(saving)
	help_button = Button.new()
	help_button.text = "?"
	help_button.tooltip_text = "How this level works (H)"
	help_button.custom_minimum_size = Vector2(48, 48)
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.add_theme_font_size_override("font_size", 20)
	help_button.pressed.connect(_toggle_help)
	bar.add_child(help_button)
	var settings_button := Settings.make_button()
	settings_button.focus_mode = Control.FOCUS_NONE
	bar.add_child(settings_button)
	corridor = Corridor.new()
	corridor.bitten.connect(func():
		Audio.play("chomp")
		_shake(12.0))
	corridor.gate_clicked.connect(_go_back)
	layout.add_child(corridor)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Style.panel_style())
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(frame)
	var scroll := ScrollContainer.new()
	frame.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Lets a room's puzzle grow into spare height.
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	# The prompt (its goal, and any detail under it), with any code it refers to in a monospace box
	# beside it.
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	content.add_child(heading)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 2)
	heading.add_child(words)
	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.add_theme_font_size_override("font_size", 20)
	words.add_child(prompt_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 15)
	detail_label.add_theme_color_override("font_color", Color(Style.TEXT, 0.7))
	detail_label.hide()
	words.add_child(detail_label)
	code_box = PanelContainer.new()
	var code_style := Style.panel_style()
	code_style.bg_color = Color(0, 0, 0, 0.35)
	code_style.border_color = Color(Style.GREEN, 0.45)
	code_style.set_corner_radius_all(10)
	code_style.set_content_margin_all(10)
	code_style.content_margin_left = 14
	code_style.content_margin_right = 14
	code_box.add_theme_stylebox_override("panel", code_style)
	code_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(code_box)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	code_box.add_child(code_row)
	var language := Label.new()
	language.text = "C"
	language.add_theme_font_size_override("font_size", 13)
	language.add_theme_color_override("font_color", Color(Style.GREEN, 0.8))
	code_row.add_child(language)
	code_label = Label.new()
	code_label.add_theme_font_override("font", Style.MONO)
	code_label.add_theme_font_size_override("font_size", 16)
	code_row.add_child(code_label)
	options_box = VBoxContainer.new()
	options_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_box.add_theme_constant_override("separation", 14)
	content.add_child(options_box)
	# The gate's answer, once asked for: under the room, so it can be read while playing.
	answer_box = PanelContainer.new()
	var answer_style := Style.panel_style()
	answer_style.bg_color = Color(Style.BG, 0.94)
	answer_style.border_color = Color(Style.GOLD, 0.7)
	answer_style.set_corner_radius_all(8)
	answer_style.set_content_margin_all(8)
	answer_box.add_theme_stylebox_override("panel", answer_style)
	answer_box.hide()
	answer_box.custom_minimum_size = Vector2(600, 0)
	answer_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(answer_box)  # Over the screen, under its button: opening it never squeezes the room.
	answer_label = Label.new()
	answer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answer_label.add_theme_font_override("font", Style.MONO)
	answer_label.add_theme_font_size_override("font_size", 14)
	answer_label.add_theme_color_override("font_color", Style.GOLD)
	answer_label.custom_minimum_size = Vector2(576, 0)  # A wrapping label needs a width to wrap at.
	answer_box.add_child(answer_label)
	# The message under the room (strikes, open gates, and anything else to say) sits in a tinted
	# bar that only shows when there is something in it; see _process.
	feedback_box = PanelContainer.new()
	feedback_box.hide()
	layout.add_child(feedback_box)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 17)
	var message_row := HBoxContainer.new()
	message_row.add_theme_constant_override("separation", 10)
	feedback_box.add_child(message_row)
	feedback_icon = Label.new()  # ✗, ✓, or ›: the kind of news, for anyone who can't tell red from green.
	feedback_icon.add_theme_font_size_override("font_size", 18)
	feedback_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	message_row.add_child(feedback_icon)
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_row.add_child(feedback)
	submit = Button.new()
	submit.text = "Check answer"
	submit.custom_minimum_size = Vector2(0, 44)
	submit.focus_mode = Control.FOCUS_NONE
	submit.pressed.connect(_submit)
	layout.add_child(submit)
	retry = Button.new()
	retry.text = "Retry connection"
	retry.pressed.connect(_retry)
	layout.add_child(retry)
	guide = InstructionGuide.new()
	guide.toggled.connect(func(open: bool): guide_button.text = _guide_title() + (" ▲" if open else " ▼"))
	add_child(guide)
	help = HowToPlay.new()
	help.toggled.connect(func(open: bool): help_button.text = "×" if open else "?")
	add_child(help)

## Number keys press instruction keys; Backspace undoes, R restarts, Enter continues, and I opens
## the instruction guide. A room can claim other keys first (Level 2 steps the robot with the arrow
## keys). While the guide is open the gate waits, and Escape or I closes it.
func _unhandled_input(event: InputEvent) -> void:
	if Settings.is_open or busy or learning_failed:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	if help.visible:
		if key in [KEY_ESCAPE, KEY_H, KEY_ENTER, KEY_KP_ENTER]:
			help.close()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_H:
		_toggle_help()
		get_viewport().set_input_as_handled()
		return
	if guide.visible:
		if key in [KEY_ESCAPE, KEY_I]:
			guide.close()
		get_viewport().set_input_as_handled()
		return
	if puzzle != null and puzzle.has_method("handle_key") and puzzle.handle_key(key):
		pass
	elif key == KEY_I and guide_button.visible:
		_toggle_guide()
	elif key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and submit.visible and not submit.disabled:
		_submit()
	elif puzzle != null and key >= KEY_1 and key <= KEY_9:
		puzzle.press(key - KEY_1)
	elif puzzle != null and key in [KEY_BACKSPACE, KEY_Z]:
		puzzle.undo()
	elif puzzle != null and key == KEY_R:
		puzzle.restart()
	else:
		return
	get_viewport().set_input_as_handled()

## Opens or closes the level's how-to-play card.
func _toggle_help() -> void:
	if help.visible:
		help.close()
	else:
		guide.close()
		help.open(level_id)

## What the gate's guide is called: the instruction guide, unless the room names its own.
func _guide_title() -> String:
	return str(puzzle.guide_title) if puzzle != null and "guide_title" in puzzle else InstructionGuide.TITLE

## Opens the guide for the gate on screen, hanging under its button, or closes it.
func _toggle_guide() -> void:
	if guide.visible:
		guide.close()
	elif puzzle != null and puzzle.has_method("guide"):
		var corner := guide_button.get_global_rect()
		guide.open(puzzle.guide(), Vector2(corner.end.x, corner.end.y + 8))

func _load_run() -> void:
	_set_busy(true)
	retry.hide()
	title.text = "Loading level %d…" % level_id
	var result := await PlayerData.api_request("/runs", HTTPClient.METHOD_POST, {"level_id": level_id, "telemetry_version": 1})
	_set_busy(false)
	if not result.ok:
		feedback_tone = "bad"
		feedback.text = result.error
		submit.disabled = true
		retry.show()
		return
	run = result.data
	_set_busy(true)
	if not await _flush_learning():
		_set_busy(false)
		return
	_set_busy(false)
	solved = run.solved_question_ids
	strikes = run.get("strikes", {}).duplicate()
	question_index = 0
	var flags: Array = []
	for item in run.questions:
		flags.append(item.id in solved)
	corridor.setup(run.questions.size(), flags)
	for i in range(run.questions.size()):
		var item: Dictionary = run.questions[i]
		if item.id in solved:
			corridor.open_gate(i, int(run.get("question_stats", {}).get(str(item.id), {}).get("stars", 3)))
	corridor.max_strikes = PuzzleRoom.STRIKES
	_show_next_unsolved()
	# The first time this device opens the level, the card explains how it is played.
	if not HowToPlay.seen(level_id) and not finished:
		help.open(level_id)

func _show_next_unsolved() -> void:
	while question_index < run.questions.size() and run.questions[question_index].id in solved:
		question_index += 1
	if question_index >= run.questions.size():
		_finish()
		return
	question = run.questions[question_index]
	var is_puzzle: bool = question.type == "puzzle"
	ready_for_next = false
	pending_answer = {}
	request_id = ""
	feedback.text = ""
	submit.text = "Check answer"
	submit.disabled = false
	# Gates open by themselves, so the button only appears once there is somewhere to go.
	submit.visible = not is_puzzle
	retry.hide()
	title.text = "Level %d · %s %d of %d" % [level_id, "Gate" if is_puzzle else "Question", question_index + 1,
		run.questions.size()]
	_show_prompt(str(question.prompt))
	corridor.walk_to(question_index)
	corridor.set_strikes(int(strikes.get(str(question.id), 0)))
	code_box.visible = question.get("code_snippet") != null
	code_label.text = "" if question.get("code_snippet") == null else str(question.code_snippet)
	choices.clear()
	selectors.clear()
	puzzle = null
	tiles = question.payload.get("tiles", []).duplicate(true)
	guide.close()
	_render_options()
	guide_button.visible = puzzle != null and puzzle.has_method("guide")
	guide_button.text = _guide_title() + " ▼"
	guide_button.tooltip_text = "What each %s on this gate means (I)" % ("part" if puzzle != null and "guide_title" in puzzle else "instruction")
	back_asked = -1
	answer_asked = false
	answer_box.hide()
	_sync_answer_button()
	_sync_corridor()
	started_at = Time.get_ticks_msec()

## Show answer is offered on a puzzle gate until it opens. Its label says what the next press does.
func _sync_answer_button() -> void:
	answer_button.visible = puzzle != null and not ready_for_next and not finished
	answer_button.text = "Hide answer ▲" if answer_box.visible else "Answer ▼" if answers.has(str(question.get("id", ""))) \
		else "Show it (1 star)" if answer_asked else "Show answer (max 1★)"

## The first press asks, since seeing the answer costs stars; the second fetches it. The server
## records that it was shown (an "answer" learning event) and scores the gate at one star. After
## that the button only opens and closes the answer, which stays under the room while it is played.
func _toggle_answer() -> void:
	if busy or learning_failed or puzzle == null or ready_for_next:
		return
	var id := str(question.id)
	if answer_box.visible:
		answer_box.hide()
	elif answers.has(id):
		_show_answer_box()
	elif not answer_asked and not bool(run.get("question_stats", {}).get(id, {}).get("answer_shown", false)):
		answer_asked = true
		feedback.text = "Show this gate's answer? Opening the gate after seeing it earns 1 star. Press the button again to see it."
	else:
		_set_busy(true)
		var saved_ok := await _flush_learning()
		var result := {"ok": false, "error": feedback.text}
		if saved_ok:
			result = await PlayerData.api_request("/runs/%s/events" % run.id, HTTPClient.METHOD_POST,
				{"question_id": question.id, "request_id": PlayerData.new_request_id(), "kind": "answer"})
		_set_busy(false)
		if not result.ok:
			feedback_tone = "bad"
			feedback.text = str(result.error)
			return
		_learning_saved(str(run.id), id, result.data.get("question_stats", {}))
		var lines: Array = ROOMS[str(question.payload.kind)].answer_lines(question.payload, result.data.answer)
		answers[id] = lines
		answer_label.text = "ONE WAY TO OPEN THIS GATE  ·  it now earns at most 1 star\n" + "\n".join(PackedStringArray(lines))
		_show_answer_box()
		feedback.text = "Here is one way to open this gate. Follow it, and work out why it works."
		Audio.play("hint", -4.0)
	_sync_answer_button()

## Shows the answer in a panel hanging under its button, over the corridor.
func _show_answer_box() -> void:
	answer_box.show()
	answer_box.reset_size()
	var corner := answer_button.get_global_rect()
	var right := corner.end.x - global_position.x
	answer_box.position = Vector2(clampf(right - answer_box.size.x, 16.0, maxf(size.x - answer_box.size.x - 16.0, 16.0)),
		corner.end.y - global_position.y + 8.0)

## Open gates in the corridor can be clicked to go back to them, except while the run is busy.
func _sync_corridor() -> void:
	corridor.clickable = not finished and not run.is_empty()

## A click on an open gate in the corridor goes back to it. The first click asks, since the gate
## closes again until it is reopened; the second click on the same gate goes. The server records
## it like a setback (without a strike) and keeps the gate's best stars.
func _go_back(index: int) -> void:
	if busy or learning_failed or finished or run.is_empty() or not pending_answer.is_empty():
		return
	if index >= run.questions.size() or run.questions[index].id not in solved:
		return
	if back_asked != index:
		back_asked = index
		feedback.text = "Go back to gate %d? It closes until you open it again, and it keeps its best stars. Click it again to go back." % (index + 1)
		return
	back_asked = -1
	_set_busy(true)
	var result := {"ok": false, "error": feedback.text}
	if await _flush_learning():
		result = await PlayerData.api_request("/runs/%s/reopen" % run.id, HTTPClient.METHOD_POST,
			{"question_id": run.questions[index].id})
	_set_busy(false)
	if not result.ok:
		feedback_tone = "bad"
		feedback.text = str(result.error)
		return
	run = result.data
	solved = run.solved_question_ids
	strikes = run.get("strikes", {}).duplicate()
	corridor.close_gate(index)
	Audio.play("undo")
	question_index = index
	_show_next_unsolved()
	feedback.text = "Back at gate %d. Open it again to move on." % (index + 1)

## A prompt's first line is the gate's goal; any lines after it are detail, shown smaller beneath.
func _show_prompt(text: String) -> void:
	var goal := text.get_slice("\n", 0)
	prompt_label.text = goal
	detail_label.text = text.substr(goal.length()).strip_edges()
	detail_label.visible = not detail_label.text.is_empty()

func _clear_options() -> void:
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()

func _render_options() -> void:
	_clear_options()
	match question.type:
		"puzzle":
			puzzle = ROOMS[str(question.payload.kind)].new(question.payload, options_box, question.get("hint"))
			var stats: Dictionary = run.get("question_stats", {}).get(str(question.id), {})
			puzzle.fails = int(stats.get("mistakes", 0))
			if bool(stats.get("hint_used", false)):
				puzzle.show_hint()
			puzzle.attempt.connect(_submit)
			puzzle.learning_event.connect(_record_learning)
		"multiple_choice":
			var group := ButtonGroup.new()
			for option in question.payload.options:
				var button := CheckBox.new()
				button.text = option.text
				button.set_meta("answer_id", option.id)
				if not question.payload.multi_select:
					button.button_group = group
				options_box.add_child(button)
				choices.append(button)
			if question.payload.multi_select:
				feedback.text = "Select all answers that apply."
		"drag_and_drop":
			feedback.text = "Arrange all tiles in order using the up and down buttons."
			for i in range(tiles.size()):
				var row := HBoxContainer.new()
				var label := Label.new()
				label.text = "%d. %s" % [i + 1, tiles[i].text]
				label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(label)
				for direction in [-1, 1]:
					var button := Button.new()
					button.text = "Up" if direction == -1 else "Down"
					button.custom_minimum_size = Vector2(80, 36)
					button.disabled = i + direction < 0 or i + direction >= tiles.size()
					button.pressed.connect(_move_tile.bind(i, direction))
					row.add_child(button)
				options_box.add_child(row)
		"matching":
			feedback.text = "Match each row to a different answer."
			for pair in question.payload.rows:
				var row := VBoxContainer.new()
				var label := Label.new()
				label.text = pair.text
				row.add_child(label)
				var selector := OptionButton.new()
				selector.add_item("Choose an answer…")
				for option in question.payload.choices:
					selector.add_item(option.text)
				selector.set_meta("pair_id", pair.id)
				row.add_child(selector)
				selectors.append(selector)
				options_box.add_child(row)

func _move_tile(index: int, direction: int) -> void:
	if busy or ready_for_next or not pending_answer.is_empty():
		return
	var value = tiles[index]
	tiles[index] = tiles[index + direction]
	tiles[index + direction] = value
	_render_options()

func _answer() -> Dictionary:
	match question.type:
		"puzzle":
			return puzzle.answer()
		"multiple_choice":
			var selected: Array = []
			for button in choices:
				if button.button_pressed:
					selected.append(button.get_meta("answer_id"))
			return {"selected_option_ids": selected}
		"drag_and_drop":
			var order: Array = []
			for tile in tiles:
				order.append(tile.id)
			return {"order": order}
		"matching":
			var pairs := {}
			for selector in selectors:
				if selector.selected > 0:
					pairs[selector.get_meta("pair_id")] = question.payload.choices[selector.selected - 1].id
			return {"pairs": pairs}
	return {}

func _submit() -> void:
	if busy:
		return
	if ready_for_next:
		question_index += 1
		_show_next_unsolved()
		return
	if pending_answer.is_empty():
		pending_answer = _answer()
		request_id = PlayerData.new_request_id()
	_set_busy(true)
	retry.hide()
	if not await _flush_learning():
		_set_busy(false)
		submit.text = "Retry saving this answer"
		submit.show()
		return
	var result := await PlayerData.api_request("/runs/%s/attempts" % run.id, HTTPClient.METHOD_POST, {
		"question_id": question.id, "request_id": request_id, "response": pending_answer,
		"elapsed_ms": Time.get_ticks_msec() - started_at
	})
	_set_busy(false)
	if not result.ok:
		feedback_tone = "bad"
		feedback.text = result.error
		# Retain the same request ID if the network outcome is unknown.
		if int(result.get("status", 0)) == 0 or int(result.get("status", 0)) >= 500:
			submit.text = "Retry saving this answer"
			submit.show()
			for button in choices:
				button.disabled = true
			for selector in selectors:
				selector.disabled = true
			if puzzle != null:
				puzzle.set_disabled(true)
			return
		pending_answer = {}
		if puzzle != null:
			puzzle.reset()
		return
	pending_answer = {}
	_learning_saved(str(run.id), str(question.id), result.data.get("question_stats", {}))
	var last: bool = question_index == run.questions.size() - 1
	if result.data.is_correct:
		solved.append(question.id)
		ready_for_next = true
		if not last:
			strikes.erase(str(run.questions[question_index + 1].id))
		var explanation := "" if result.data.get("explanation") == null else " " + str(result.data.explanation)
		if puzzle != null:
			var stars: int = int(result.data.get("stars", puzzle.stars()))
			puzzle.solved()
			corridor.open_gate(question_index, stars)
			PlayerData.note_guest_stars(level_id, str(question.id), stars)
			Audio.play("open")
			feedback_tone = "good"
			feedback.text = "%s %s%s" % ["★".repeat(stars), "Perfect!" if stars == 3 else "Gate open!", explanation]
			# Going back only helps when the star was lost to par (too many moves or instructions):
			# a mistake, a hint, or a shown answer counts against the gate for the rest of the run.
			var shown := bool(run.get("question_stats", {}).get(str(question.id), {}).get("answer_shown", false))
			if stars < 3 and puzzle.fails == 0 and not puzzle.hint_used and not shown:
				feedback.text += " (Click an open gate above to try it again for more stars.)"
			submit.text = "Finish level ▶" if last else "Next gate ▶"
			answer_box.hide()
			_sync_answer_button()
		else:
			feedback_tone = "good"
			feedback.text = ("Correct!" if PlayerData.guest else "Correct — answer saved.") + explanation
			submit.text = "Finish level" if last else "Next question"
		submit.show()
	elif puzzle != null and result.data.get("setback_question_id") != null:
		await _dragged_back(str(result.data.setback_question_id))
	elif puzzle != null:
		var count := int(result.data.get("strikes", 0))
		strikes[str(question.id)] = count
		corridor.chomp(count)
		Audio.play("strike", -4.0)
		_shake(4.0)
		puzzle.failed()
		var miss: String = puzzle.miss_text() if puzzle.has_method("miss_text") else "Out of moves!"
		var warning: String = puzzle.retry_tip() if puzzle.has_method("retry_tip") else "Try a different order."
		if count == PuzzleRoom.STRIKES - 1:
			warning = "One more and the Chip Chomper drags you back a gate." if question_index > 0 else "One more and the Chip Chomper makes you start over."
		feedback_tone = "bad"
		feedback.text = "%s Strike %d of %d. %s" % [miss, count, PuzzleRoom.STRIKES, warning]
	else:
		feedback_tone = "bad"
		feedback.text = "Not quite. Try again — retries are allowed."

## The last strike: the Chomper bites the robot and drags it back to the gate the server
## reopened (or, on a first gate, makes the player start that gate over).
func _dragged_back(target_id: String) -> void:
	var target := question_index
	for i in range(run.questions.size()):
		if str(run.questions[i].id) == target_id:
			target = i
	strikes.erase(str(question.id))
	strikes.erase(target_id)
	solved.erase(target_id)
	_set_busy(true)
	get_tree().create_timer(0.62, false).timeout.connect(Audio.play.bind("dragged"))
	feedback_tone = "bad"
	feedback.text = "CHOMP! The Chip Chomper caught you!"
	await corridor.bite(target)
	_set_busy(false)
	var dragged := target < question_index
	question_index = target
	_show_next_unsolved()
	feedback_tone = "bad"
	feedback.text = "The Chip Chomper dragged you back to gate %d. Open it again to move on." % (target + 1) if dragged \
		else "The Chip Chomper made you start this gate over."

func _finish() -> void:
	_set_busy(true)
	title.text = "Saving your badge…"
	if not await _flush_learning():
		_set_busy(false)
		return
	var result := await PlayerData.api_request("/runs/%s/finish" % run.id, HTTPClient.METHOD_POST)
	_set_busy(false)
	submit.hide()
	if not result.ok:
		feedback_tone = "bad"
		feedback.text = result.error
		retry.show()
		return
	PlayerData.apply_profile(result.data)
	finished = true
	_clear_options()
	puzzle = null
	guide.close()
	guide_button.hide()
	answer_button.hide()
	answer_box.hide()
	_sync_corridor()
	code_box.hide()
	corridor.finish()
	Audio.play("complete")
	_show_badge()
	_show_finish_actions()
	_show_prompt(finish_line)
	title.text = "Level complete — badge earned!" if PlayerData.guest else "Level complete — badge saved!"
	feedback_tone = "good"
	feedback.text = "Guest badges reset when you reload." if PlayerData.guest else "Your badge will be here when you sign in again."
	if not PlayerData.guest and result.data.get("leaderboard_eligible", false):
		feedback.text = "%d / %d stars · %d mistake%s. Your best run this week counts on the leaderboard." % [
			int(result.data.get("stars", 0)), int(result.data.get("max_stars", 0)), int(result.data.get("mistakes", 0)),
			"" if int(result.data.get("mistakes", 0)) == 1 else "s"]
	elif not PlayerData.guest:
		feedback.text += " Replay this level to enter the weekly leaderboard."
	retry.hide()

## What to do next, under the badge: back to the Control Center, or straight into another run.
func _show_finish_actions() -> void:
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	options_box.add_child(actions)
	var home := Button.new()
	home.text = "◀  Back to the Control Center"
	home.custom_minimum_size = Vector2(300, 48)
	home.focus_mode = Control.FOCUS_NONE
	for look in ["normal", "hover", "pressed", "disabled"]:
		home.add_theme_stylebox_override(look, Style.key_style(Style.GREEN, look))
	home.pressed.connect(_return_to_center)
	actions.add_child(home)
	var again := Button.new()
	again.text = "Play again  ▶"
	again.custom_minimum_size = Vector2(200, 48)
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func(): get_tree().reload_current_scene())
	actions.add_child(again)

func _show_badge() -> void:
	var badge := TextureRect.new()
	badge.texture = load(badge_icon)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.custom_minimum_size = Vector2(220, 220)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options_box.add_child(badge)
	badge.pivot_offset = Vector2(110, 110)
	badge.scale = Vector2.ZERO
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(badge, "scale", Vector2.ONE, 0.6)
	await get_tree().create_timer(0.45, false).timeout
	Style.burst(badge, Vector2(110, 110), [Style.GOLD, Style.CYAN, Style.GREEN, Color.WHITE], 40, 320.0, 180.0, 260.0, 6.0, 1.2)

## Jolts the whole screen, fading out over a third of a second.
func _shake(strength: float) -> void:
	if Settings.reduce_motion:
		return
	var tween := create_tween()
	tween.tween_method(func(fade: float):
		layout_root.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * fade, 1.0, 0.0, 0.35)
	tween.tween_callback(func(): layout_root.position = Vector2.ZERO)

func _retry() -> void:
	if learning_failed:
		_set_busy(true)
		var saved_ok := await _flush_learning()
		_set_busy(false)
		if not saved_ok:
			return
		if not pending_answer.is_empty():
			_submit()
		elif question.is_empty():
			_load_run()
		elif question_index >= run.questions.size():
			_finish()
	elif run.is_empty():
		_load_run()
	else:
		_finish()

func _record_learning(kind: String, detail: Dictionary) -> void:
	LearningLog.record(str(run.id), str(question.id), kind, detail)
	await _flush_learning()

func _flush_learning() -> bool:
	if run.is_empty():
		return true
	var saved_ok := await LearningLog.flush(str(run.id))
	var was_failed := learning_failed
	learning_failed = not saved_ok
	if saved_ok and was_failed:
		feedback.text = "Your latest move is saved."
		retry.hide()
	if not saved_ok:
		feedback_tone = "bad"
		feedback.text = LearningLog.last_error + " Retry to save your latest move."
		retry.show()
		if puzzle != null:
			puzzle.set_disabled(true)
	elif not busy:
		retry.hide()
		if puzzle != null:
			puzzle.set_disabled(ready_for_next or not pending_answer.is_empty())
	return saved_ok

func _learning_saved(run_id: String, question_id: String, stats: Dictionary) -> void:
	if str(run.get("id", "")) != run_id or stats.is_empty():
		return
	if not run.has("question_stats"):
		run.question_stats = {}
	run.question_stats[question_id] = stats

func _return_to_center() -> void:
	if busy:
		return
	_set_busy(true)
	var saved_ok := await _flush_learning()
	_set_busy(false)
	if saved_ok:
		get_tree().change_scene_to_file("res://control_center.tscn")

func _set_busy(value: bool) -> void:
	busy = value
	submit.disabled = value
	menu_button.disabled = value
	answer_button.disabled = value
	for button in choices:
		if is_instance_valid(button):
			button.disabled = value
	for selector in selectors:
		if is_instance_valid(selector):
			selector.disabled = value
	if puzzle != null:
		puzzle.set_disabled(value or ready_for_next or learning_failed)
