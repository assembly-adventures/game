extends Control

var run: Dictionary = {}
var question: Dictionary = {}
var question_index: int = 0
var solved: Array = []
var choices: Array = []
var tiles: Array = []
var selectors: Array = []
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

func _ready() -> void:
	_build_ui()
	_load_run()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("171b25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 32)
	add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margins.add_child(layout)
	var menu := Button.new()
	menu.text = "Control Center — answers are saved"
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://control_center.tscn"))
	layout.add_child(menu)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 26)
	layout.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)
	prompt_label = Label.new()
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.add_theme_font_size_override("font_size", 22)
	content.add_child(prompt_label)
	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 10)
	content.add_child(options_box)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(feedback)
	submit = Button.new()
	submit.text = "Check answer"
	submit.pressed.connect(_submit)
	layout.add_child(submit)
	retry = Button.new()
	retry.text = "Retry connection"
	retry.pressed.connect(_retry)
	layout.add_child(retry)

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
	question_index = 0
	_show_next_unsolved()

func _show_next_unsolved() -> void:
	while question_index < run.questions.size() and run.questions[question_index].id in solved:
		question_index += 1
	if question_index >= run.questions.size():
		_finish()
		return
	question = run.questions[question_index]
	ready_for_next = false
	pending_answer = {}
	request_id = ""
	feedback.text = ""
	submit.text = "Check answer"
	submit.disabled = false
	retry.hide()
	title.text = "Level 1 · Question %d of %d" % [question_index + 1, run.questions.size()]
	prompt_label.text = question.prompt
	if question.get("code_snippet") != null:
		prompt_label.text += "\n\n" + str(question.code_snippet)
	choices.clear()
	selectors.clear()
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
			for button in choices:
				button.disabled = true
			for selector in selectors:
				selector.disabled = true
			return
		pending_answer = {}
		return
	pending_answer = {}
	if result.data.is_correct:
		solved.append(question.id)
		ready_for_next = true
		feedback.text = "Correct — answer saved."
		if result.data.get("explanation") != null:
			feedback.text += " " + str(result.data.explanation)
		submit.text = "Finish level" if question_index == run.questions.size() - 1 else "Next question"
	else:
		feedback.text = "Not quite. Try again — retries are allowed."

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
	prompt_label.text = "Basic Instructions Master"
	title.text = "Level complete — badge saved!"
	feedback.text = "Your badge will be here when you sign in again."
	retry.hide()

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
