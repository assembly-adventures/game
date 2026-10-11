extends "res://levels/level_3/tower_room.gd"
## A Frame Builder room: the player lays out the function's stack frame by clicking blocks (each
## goes in at sp+0, pushing the others up a word) and moving or removing them on the tower. The
## listing shows the prologue and epilogue the layout writes. Run plays the Chomper's first call on
## the tower and checks every call against the contract; the run is the attempt. In the finale the
## heap climbs from the bottom of the stack while the calls run.

var frame: Array = []  # The layout: block names, sp+0 first.
var blocks: Array = []
var palette: Array = []

func _build_controls() -> void:
	blocks = payload.blocks
	listing.note = "the lines your frame writes show in blue"
	side.add_child(_step(1, "Click each register %s must save" % str(payload.entry)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	side.add_child(row)
	for i in range(blocks.size()):
		var name := str(blocks[i])
		var back := not CallMachine.restored(name)
		if back:
			tower.read_back[name] = true
		var key := Button.new()
		key.text = name
		key.tooltip_text = ("%s · saved; the code reads it back" if back else "%s · saved, then restored on the way out") % name \
			+ " (key %d)" % (i + 1)
		key.custom_minimum_size = Vector2(62, 38)
		key.focus_mode = Control.FOCUS_NONE
		key.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		key.add_theme_font_override("font", Style.MONO)
		key.add_theme_font_size_override("font_size", 16)
		var color := Style.PURPLE if back else Style.CYAN
		for look in ["normal", "hover", "pressed", "disabled"]:
			var style := Style.key_style(color, look)
			style.set_content_margin_all(4)
			style.border_width_bottom = 2 if look == "pressed" else 4
			key.add_theme_stylebox_override(look, style)
		key.pressed.connect(press.bind(i))
		row.add_child(key)
		palette.append(key)
	tower.slot_action.connect(_on_slot_action)
	_add_audit(_step(2, "Run the Chomper's calls", "each must return its answer, with s0–s11 and sp as they were"))

func _add_tools() -> void:
	tools.add_child(_tool("Clear", restart, "R"))

func _run_text() -> String:
	return "Run the calls ▶"

func answer() -> Dictionary:
	return {"frame": frame.duplicate()}

func miss_text() -> String:
	return "The contract broke!" if headline.is_empty() else headline

func retry_tip() -> String:
	return "Change the frame and run it again."

func _star_penalty() -> int:
	return int(frame.size() > int(payload.par))

## Number keys add blocks.
func press(index: int) -> void:
	if _busy() or index >= blocks.size():
		return
	var name := str(blocks[index])
	if name in frame or frame.size() >= int(payload.max_slots):
		Audio.play("undo", -10.0)
		return
	Audio.play("press", -4.0, 0.1)
	frame.push_front(name)
	_changed()

## Backspace takes out the block at sp+0, the last one added.
func undo() -> void:
	if _busy() or frame.is_empty():
		return
	Audio.play("undo")
	frame.pop_front()
	_changed()

func restart() -> void:
	if _busy() or frame.is_empty():
		return
	Audio.play("undo")
	frame.clear()
	_changed()

func _on_slot_action(k: int, action: String) -> void:
	if _busy() or k >= frame.size():
		return
	match action:
		"remove":
			frame.remove_at(k)
			Audio.play("undo", -6.0)
		"up":
			if k + 1 < frame.size():
				var name = frame[k]
				frame[k] = frame[k + 1]
				frame[k + 1] = name
				Audio.play("press", -8.0, 0.1)
		"down":
			if k > 0:
				var name = frame[k]
				frame[k] = frame[k - 1]
				frame[k - 1] = name
				Audio.play("press", -8.0, 0.1)
	_changed()

func _changed() -> void:
	cards.clear()
	_show_start()
	_sync()

func _show_start() -> void:
	listing.running = -1
	listing.show_program(CallMachine.assemble(payload, frame))
	var title := "%s's frame" % str(payload.entry)
	tower.show_design(frame.duplicate(), title, int(payload.max_slots))

func _sync_controls() -> void:
	var off := _busy()
	for i in range(palette.size()):
		var used: bool = str(blocks[i]) in frame
		palette[i].disabled = off or used or frame.size() >= int(payload.max_slots)
		palette[i].modulate.a = 0.45 if palette[i].disabled else 1.0

func _on_run() -> void:
	playing = true
	headline = ""
	cards.clear()
	_sync()
	var rows: Array = CallMachine.audit(payload, frame)
	listing.show_program(CallMachine.assemble(payload, frame))
	var shown := _call_to_show(rows)
	cards.running = shown
	await _play(rows[shown].state, shown)
	if not is_instance_valid(tower):
		return
	cards.running = -1
	var passed := 0
	for k in range(rows.size()):
		cards.mark(k, rows[k].passed, _detail(rows[k]))
		passed += int(rows[k].passed)
		if not rows[k].passed and headline.is_empty():
			headline = "Call %d crashed!" % (k + 1) if not rows[k].state.fault.is_empty() else "Call %d broke the contract!" % (k + 1)
		await tower.get_tree().create_timer(0.35).timeout
		if not is_instance_valid(tower):
			return
	if passed == rows.size():
		tower.flash_message("EVERY CALL KEPT THE CONTRACT", Style.GREEN)
	playing = false
	locked = true
	_sync()
	attempt.emit()

## The call the tower plays: the first that broke the contract, or in the finale the longest (the
## race), or else the first.
func _call_to_show(rows: Array) -> int:
	for k in range(rows.size()):
		if not rows[k].passed:
			return k
	if not payload.has("chomper"):
		return 0
	var longest := 0
	for k in range(rows.size()):
		if int(rows[k].state.steps) > int(rows[longest].state.steps):
			longest = k
	return longest

## After a miss the tower goes back to the frame, so it can be changed; the cards keep the details.
func failed() -> void:
	super.failed()
	await tower.get_tree().create_timer(1.0).timeout
	if is_instance_valid(tower) and not _busy():
		tower.show_design(frame.duplicate(), "%s's frame" % str(payload.entry), int(payload.max_slots))
