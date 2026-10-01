extends Control

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const Visuals := preload("res://levels/level_1/visuals.gd")
const Style := preload("res://ui/style.gd")

var run: Dictionary = {}
var question: Dictionary = {}
var question_index: int = 0
var solved: Array = []
var strikes: Dictionary = {}
var choices: Array = []
var tiles: Array = []
var selectors: Array = []
var puzzle: PuzzleRoom = null
var request_id: String = ""
var pending_answer: Dictionary = {}
var busy: bool = false
var ready_for_next: bool = false
var started_at: int = 0
var title: Label
var prompt_label: Label
var options_box: VBoxContainer
var feedback: Label
var submit: Button
var retry: Button
var corridor
var sound_button: Button
var layout_root: MarginContainer

func _ready() -> void:
	_build_ui()
	_load_run()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Visuals.CircuitBackdrop.new()
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
	# Top bar: back to the Control Center, the gate count, and whether progress is kept.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	layout.add_child(bar)
	var menu := Button.new()
	menu.text = "◀ Control Center"
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://control_center.tscn"))
	bar.add_child(menu)
	title = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	bar.add_child(title)
	var saving := Label.new()
	saving.text = "Guest: progress is not saved" if PlayerData.guest else "Progress saves automatically"
	saving.add_theme_font_size_override("font_size", 13)
	saving.add_theme_color_override("font_color", Color(Visuals.TEXT, 0.55))
	bar.add_child(saving)
	sound_button = Button.new()
	sound_button.focus_mode = Control.FOCUS_NONE
	sound_button.pressed.connect(_toggle_sound)
	bar.add_child(sound_button)
	_update_sound_label()
	corridor = Visuals.Corridor.new()
	corridor.bitten.connect(func():
		Audio.play("chomp")
		_shake(12.0))
	layout.add_child(corridor)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", Style.panel_style())
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(frame)
	var scroll := ScrollContainer.new()
	frame.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.add_theme_font_size_override("font_size", 20)
	content.add_child(prompt_label)
	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 14)
	content.add_child(options_box)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 18)
	layout.add_child(feedback)
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

## Number keys press instruction keys; Backspace undoes, R restarts, Enter continues.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	if key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and submit.visible and not submit.disabled:
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

func _toggle_sound() -> void:
	Audio.set_enabled(not Audio.enabled)
	_update_sound_label()

func _update_sound_label() -> void:
	sound_button.text = "Sound: on" if Audio.enabled else "Sound: off"

func _load_run() -> void:
	_set_busy(true)
	retry.hide()
	title.text = "Loading level 1…"
	var result := await PlayerData.api_request("/runs", HTTPClient.METHOD_POST, {"level_id": 1})
	_set_busy(false)
	if not result.ok:
		feedback.text = result.error
		submit.disabled = true
		retry.show()
		return
	run = result.data
	solved = run.solved_question_ids
	strikes = run.get("strikes", {}).duplicate()
	question_index = 0
	var flags: Array = []
	for item in run.questions:
		flags.append(item.id in solved)
	corridor.setup(run.questions.size(), flags)
	corridor.max_strikes = PuzzleRoom.STRIKES
	_show_next_unsolved()

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
	title.text = "Level 1 · %s %d of %d" % ["Gate" if is_puzzle else "Question", question_index + 1, run.questions.size()]
	prompt_label.text = question.prompt
	corridor.walk_to(question_index)
	corridor.set_strikes(int(strikes.get(str(question.id), 0)))
	if question.get("code_snippet") != null:
		prompt_label.text += "\n\n" + str(question.code_snippet)
	choices.clear()
	selectors.clear()
	puzzle = null
	tiles = question.payload.get("tiles", []).duplicate(true)
	_render_options()
	started_at = Time.get_ticks_msec()

func _clear_options() -> void:
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()

func _render_options() -> void:
	_clear_options()
	match question.type:
		"puzzle":
			puzzle = PuzzleRoom.new(question.payload, options_box, question.get("hint"))
			puzzle.attempt.connect(_submit)
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
	var result := await PlayerData.api_request("/runs/%s/attempts" % run.id, HTTPClient.METHOD_POST, {
		"question_id": question.id, "request_id": request_id, "response": pending_answer,
		"elapsed_ms": Time.get_ticks_msec() - started_at
	})
	_set_busy(false)
	if not result.ok:
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
	var last: bool = question_index == run.questions.size() - 1
	if result.data.is_correct:
		solved.append(question.id)
		ready_for_next = true
		if not last:
			strikes.erase(str(run.questions[question_index + 1].id))
		var explanation := "" if result.data.get("explanation") == null else " " + str(result.data.explanation)
		if puzzle != null:
			var stars := puzzle.stars()
			puzzle.solved()
			corridor.open_gate(question_index, stars)
			Audio.play("open")
			feedback.text = "%s %s%s" % ["★".repeat(stars), "Perfect!" if stars == 3 else "Gate open!", explanation]
			submit.text = "Finish level ▶" if last else "Next gate ▶"
		else:
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
		var warning := "Try a different order."
		if count == PuzzleRoom.STRIKES - 1:
			warning = "One more and the Chip Chomper drags you back a gate." if question_index > 0 else "One more and the Chip Chomper makes you start over."
		feedback.text = "Out of moves! Strike %d of %d. %s" % [count, PuzzleRoom.STRIKES, warning]
	else:
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
	get_tree().create_timer(0.62).timeout.connect(Audio.play.bind("dragged"))
	feedback.text = "CHOMP! The Chip Chomper caught you!"
	await corridor.bite(target)
	_set_busy(false)
	var dragged := target < question_index
	question_index = target
	_show_next_unsolved()
	feedback.text = "The Chip Chomper dragged you back to gate %d. Open it again to move on." % (target + 1) if dragged \
		else "The Chip Chomper made you start this gate over."

func _finish() -> void:
	_set_busy(true)
	title.text = "Saving your badge…"
	var result := await PlayerData.api_request("/runs/%s/finish" % run.id, HTTPClient.METHOD_POST)
	_set_busy(false)
	submit.hide()
	if not result.ok:
		feedback.text = result.error
		retry.show()
		return
	PlayerData.apply_profile(result.data)
	_clear_options()
	puzzle = null
	corridor.finish()
	Audio.play("complete")
	_show_badge()
	prompt_label.text = "The robot reached the CPU and the Chip Chomper ran off. Basic Instructions Master!"
	title.text = "Level complete — badge earned!" if PlayerData.guest else "Level complete — badge saved!"
	feedback.text = "Guest badges reset when you reload." if PlayerData.guest else "Your badge will be here when you sign in again."
	retry.hide()

func _show_badge() -> void:
	var badge := TextureRect.new()
	badge.texture = load("res://images/1.svg")
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.custom_minimum_size = Vector2(220, 220)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options_box.add_child(badge)
	badge.pivot_offset = Vector2(110, 110)
	badge.scale = Vector2.ZERO
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(badge, "scale", Vector2.ONE, 0.6)
	await get_tree().create_timer(0.45).timeout
	Style.burst(badge, Vector2(110, 110), [Style.GOLD, Style.CYAN, Style.GREEN, Color.WHITE], 40, 320.0, 180.0, 260.0, 6.0, 1.2)

## Jolts the whole screen, fading out over a third of a second.
func _shake(strength: float) -> void:
	var tween := create_tween()
	tween.tween_method(func(fade: float):
		layout_root.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * fade, 1.0, 0.0, 0.35)
	tween.tween_callback(func(): layout_root.position = Vector2.ZERO)

func _retry() -> void:
	if run.is_empty():
		_load_run()
	else:
		_finish()

func _set_busy(value: bool) -> void:
	busy = value
	submit.disabled = value
	for button in choices:
		if is_instance_valid(button):
			button.disabled = value
	for selector in selectors:
		if is_instance_valid(selector):
			selector.disabled = value
	if puzzle != null:
		puzzle.set_disabled(value or ready_for_next)
