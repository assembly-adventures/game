extends "res://levels/level_3/tower_room.gd"
## A Code Lawyer room: the player clicks the line that breaks the calling convention, picks the
## rule it breaks, and objects; the objection is the attempt. Watching the Chomper's audit first is
## free: it plays a call on the tower and shows what the crime did (a changed s register, a wrong
## value, a call that never returns) without saying where it happened.

const RULES := {
	"caller-save": "Caller: save any t or a register you still need after a call.",
	"callee-save": "Callee: save and restore every s register you use.",
	"save-ra": "Save ra before making a call of your own.",
	"restore-sp": "Put sp back where it was before returning.",
}

var line := -1
var clause := ""
var rule_buttons: Array = []
var watch_button: Button

func _run_color() -> Color:
	return Style.RED

func _run_text() -> String:
	if line < 0:
		return "Click a line in the code"
	return "Now pick a rule" if clause.is_empty() else "Object! ▶"

## Step 1 watches a call (beside the audit), step 2 is on the listing (click a line), and step 3
## picks the rule.
func _build_controls() -> void:
	listing.selectable = true
	listing.step = 2
	listing.note = "Click the line that breaks a rule"
	listing.line_clicked.connect(_on_line)
	watch_button = _tool("Watch ▶", watch, "")
	watch_button.tooltip_text = "Play the Chomper's call on the tower (free: it isn't an attempt)"
	watch_button.custom_minimum_size = Vector2(84, 0)
	watch_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_compact(watch_button)
	var first := _step(1, "Watch a call to see what breaks")
	first.add_child(watch_button)
	_add_audit(first)
	side.add_child(_step(3, "Pick the rule that line breaks"))
	var rules := VBoxContainer.new()
	rules.add_theme_constant_override("separation", 4)
	side.add_child(rules)
	var clauses: Array = payload.clauses
	for i in range(clauses.size()):
		var id := str(clauses[i])
		var button := Button.new()
		button.text = "%d  %s" % [i + 1, RULES.get(id, id)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 13)
		_compact(button)
		button.pressed.connect(press.bind(i))
		rules.add_child(button)
		rule_buttons.append(button)

func _can_run() -> bool:
	return line >= 0 and not clause.is_empty()

func answer() -> Dictionary:
	return {"line": line, "clause": clause}

func miss_text() -> String:
	return "Objection overruled!"

func retry_tip() -> String:
	return "Read the code against each rule and object again."

## Number keys pick a rule.
func press(index: int) -> void:
	if _busy() or index >= rule_buttons.size():
		return
	clause = str(payload.clauses[index])
	Audio.play("press", -6.0, 0.1)
	_sync()

## Up and Down move the accusation from line to line.
func handle_key(key: int) -> bool:
	if not _busy() and key in [KEY_UP, KEY_DOWN]:
		var addresses: Array = []
		for row in listing.rows:
			if row.kind == "line":
				addresses.append(int(row.address))
		var at := addresses.find(line)
		at = clampi(at + (1 if key == KEY_DOWN else -1), 0, addresses.size() - 1) if at >= 0 else 0
		_on_line(int(addresses[at]))
		return true
	return super.handle_key(key)

func undo() -> void:
	if not _busy():
		line = -1
		clause = ""
		_sync()

func restart() -> void:
	undo()

func _on_line(address: int) -> void:
	if _busy():
		return
	line = address
	listing.marks.clear()
	Audio.play("press", -8.0, 0.1)
	_sync()

func _show_start() -> void:
	tower.idle = "Press Watch to see what goes wrong.\nWatching is free."
	listing.show_program(CallMachine.assemble(payload))
	_show_model({"memory": CallMachine.setup(payload, 0).memory, "labels": {}, "open": [], "sp": STACK_TOP,
		"heap": CallMachine.heap_line(payload, 0)})

func _sync_controls() -> void:
	listing.selected = line
	listing.queue_redraw()
	for i in range(rule_buttons.size()):
		rule_buttons[i].button_pressed = str(payload.clauses[i]) == clause
		rule_buttons[i].disabled = _busy()
	if watch_button:
		watch_button.disabled = _busy()

## Plays the Chomper's first call and fills in the audit. Free: it isn't an attempt.
func watch() -> void:
	if _busy():
		return
	playing = true
	cards.clear()
	_sync()
	var rows: Array = CallMachine.audit(payload)
	cards.running = 0
	await _play(rows[0].state, 0)
	if not is_instance_valid(tower):
		return
	cards.running = -1
	_show_rows(rows)
	playing = false
	_sync()

func _on_run() -> void:
	locked = true
	_sync()
	attempt.emit()

## The objection stands: the accused line turns green, and the audit shows the crime.
func solved() -> void:
	super.solved()
	listing.marks[line] = Style.GREEN
	listing.queue_redraw()
	if cards.results.has(""):
		_show_rows(CallMachine.audit(payload))
