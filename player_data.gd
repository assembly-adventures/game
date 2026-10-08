extends Node

signal profile_changed

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const MazeRoom := preload("res://levels/level_2/maze_room.gd")
const CodeRoom := preload("res://levels/level_2/code_room.gd")
const CallMachine := preload("res://levels/level_3/call_machine.gd")
## The levels guest mode can play, each from a copy of its gates kept in sync with the database. A
## level's copy is a list of rooms, or its whole bank and draw rule when its runs draw their rooms.
const GUEST_LEVELS := {
	1: {"rooms": "res://levels/level_1/guest_rooms.json", "badge": {"slug": "badge_1", "name": "Basic Instructions Master"}},
	2: {"rooms": "res://levels/level_2/guest_rooms.json", "badge": {"slug": "badge_2", "name": "Memory Master"}},
	3: {"rooms": "res://levels/level_3/guest_rooms.json", "badge": {"slug": "badge_3", "name": "Stack Master"}},
}

var earned_badges: Array[String] = []
var levels: Array = []
var progress_ratio: float = 0.0
var api_base: String = ""
var last_error: String = ""
# Guest mode answers API calls in memory: nothing reaches the server and a reload starts over.
var guest: bool = false
# Per level ID: every room it can draw from (with its draw rule, if any), the rooms of its current
# run, the gates solved, strikes by gate, and whether its run finished.
var guest_banks: Dictionary = {}
var guest_rooms: Dictionary = {}
var guest_solved: Dictionary = {}
var guest_strikes: Dictionary = {}
var guest_run_done: Dictionary = {}
var guest_badges: Array = []

func _ready() -> void:
	if OS.has_feature("web"):
		api_base = str(JavaScriptBridge.eval("window.location.origin"))

# F11 toggles fullscreen from any scene.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()

func toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)

func api_request(path: String, method: int = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
	if guest:
		return _guest_request(path, body)
	if api_base.is_empty():
		return {"ok": false, "error": "Open the hosted browser game to sign in and save progress."}
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "X-AA-Request: 1"])
	var payload := "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var error := http.request(api_base + "/api" + path, headers, method, payload)
	if error != OK:
		http.queue_free()
		return {"ok": false, "error": "Could not connect. Please retry."}
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Connection interrupted. Your saved answers are safe; please retry."}
	var parsed = JSON.parse_string(result[3].get_string_from_utf8())
	if int(result[1]) < 200 or int(result[1]) >= 300:
		var message := "Could not save progress. Please retry."
		if parsed is Dictionary:
			message = str(parsed.get("detail", message))
		if int(result[1]) == 401:
			message = "Your login expired. Reload this page to sign in and resume."
		return {"ok": false, "error": message, "status": int(result[1])}
	return {"ok": true, "data": parsed}

func refresh_profile() -> bool:
	var result := await api_request("/me")
	if not result.ok:
		last_error = result.error
		return false
	apply_profile(result.data)
	result = await api_request("/levels")
	if not result.ok:
		last_error = result.error
		return false
	levels = result.data
	last_error = ""
	return true

func apply_profile(profile: Dictionary) -> void:
	earned_badges.clear()
	for badge in profile.get("badges", []):
		earned_badges.append(str(badge.slug))
	progress_ratio = float(profile.get("progress_ratio", 0.0))
	profile_changed.emit()

func get_progress_ratio() -> float:
	return progress_ratio

func new_request_id() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

func start_guest() -> void:
	guest = true
	guest_badges.clear()
	for level in GUEST_LEVELS:
		var bank = JSON.parse_string(FileAccess.get_file_as_string(GUEST_LEVELS[level].rooms))
		guest_banks[level] = bank if bank is Dictionary else {"rooms": bank}
		guest_rooms[level] = _guest_draw(guest_banks[level])
		guest_solved[level] = []
		guest_strikes[level] = {}
		guest_run_done[level] = false

# Mirrors the responses of server/gameplay.py for the guest levels, graded by the client interpreters.
# A guest run's ID is "guest-<level>", so its attempts post to /runs/guest-<level>/attempts.
func _guest_request(path: String, body: Dictionary) -> Dictionary:
	if path == "/me":
		return {"ok": true, "data": _guest_profile()}
	if path == "/levels":
		var listed: Array = []
		for level in GUEST_LEVELS:
			listed.append({"id": level, "is_active": true, "completed": level in guest_badges})
		return {"ok": true, "data": listed}
	if path == "/runs":
		var level := int(body.get("level_id", 0))
		if not GUEST_LEVELS.has(level):
			return {"ok": false, "error": "Guest mode only includes Levels 1 to 3.", "status": 404}
		if guest_run_done[level]:
			guest_rooms[level] = _guest_draw(guest_banks[level])
			guest_solved[level] = []
			guest_strikes[level] = {}
			guest_run_done[level] = false
		var questions: Array = []
		for room in guest_rooms[level]:
			questions.append({"id": _guest_id(level, room), "type": "puzzle", "prompt": room.prompt,
				"code_snippet": room.get("code_snippet"), "hint": room.hint, "payload": room.payload})
		return {"ok": true, "data": {"id": "guest-%d" % level, "level_id": level, "outcome": "in_progress",
			"questions": questions, "solved_question_ids": guest_solved[level].duplicate(),
			"strikes": guest_strikes[level].duplicate()}}
	var parts := path.split("/")  # "", "runs", "guest-<level>", "attempts" or "finish"
	var level := int(parts[2].trim_prefix("guest-")) if parts.size() == 4 and parts[2].begins_with("guest-") else 0
	if not GUEST_LEVELS.has(level):
		return {"ok": false, "error": "Guest mode cannot reach the server.", "status": 404}
	if parts[3] == "attempts":
		var rooms: Array = guest_rooms[level]
		for i in range(rooms.size()):
			if _guest_id(level, rooms[i]) == body.question_id:
				return {"ok": true, "data": _guest_attempt(level, i, body.response)}
		return {"ok": false, "error": "Question does not belong to this run.", "status": 404}
	if parts[3] == "finish":
		if not guest_run_done[level] and guest_solved[level].size() < guest_rooms[level].size():
			return {"ok": false, "error": "Answer every question correctly before finishing.", "status": 409}
		if level not in guest_badges:
			guest_badges.append(level)
		guest_run_done[level] = true
		return {"ok": true, "data": _guest_profile()}
	return {"ok": false, "error": "Guest mode cannot reach the server.", "status": 404}

# Mirrors draw() in server/gameplay.py: without a draw rule a run plays every room; with one, each
# pool in the rule gives all its rooms, or `take` of them at random, kept in ordinal order.
func _guest_draw(bank: Dictionary) -> Array:
	var rooms: Array = bank.rooms
	if not bank.has("draw"):
		return rooms.duplicate()
	var picked: Array = []
	for slot in bank.draw:
		var pool := rooms.filter(func(room): return room.get("pool") == slot.pool)
		var shuffled := pool.duplicate()
		shuffled.shuffle()
		var chosen: Array = shuffled.slice(0, mini(int(slot.get("take", pool.size())), pool.size())).map(
			func(room): return int(room.ordinal))
		picked.append_array(pool.filter(func(room): return int(room.ordinal) in chosen))
	return picked

func _guest_id(level: int, room: Dictionary) -> String:
	return "guest-%d-%d" % [level, int(room.ordinal)]

# Mirrors attempt() and strike() in server/gameplay.py: a gate's third strike reopens the gate before it.
func _guest_attempt(level: int, index: int, response: Dictionary) -> Dictionary:
	var rooms: Array = guest_rooms[level]
	var solved: Array = guest_solved[level]
	var strikes: Dictionary = guest_strikes[level]
	var room: Dictionary = rooms[index]
	var id := _guest_id(level, room)
	if id in solved:
		return {"is_correct": true, "explanation": room.explanation}
	var payload: Dictionary = room.payload
	var correct: bool
	match str(payload.kind):
		"maze":
			correct = MazeRoom.grade(payload, response)
		"code":
			correct = CodeRoom.grade(payload, response)
		"frame", "elevator", "lawyer":
			correct = CallMachine.grade(payload, response)
		_:
			correct = PuzzleRoom.grade(payload, response)
	var result := {"is_correct": correct, "explanation": room.explanation, "strikes": 0, "setback_question_id": null}
	if correct:
		solved.append(id)
		if index + 1 < rooms.size():
			strikes.erase(_guest_id(level, rooms[index + 1]))
		return result
	result.strikes = int(strikes.get(id, 0)) + 1
	strikes[id] = result.strikes
	if result.strikes >= PuzzleRoom.STRIKES:
		var before := _guest_id(level, rooms[index - 1]) if index > 0 else ""
		var target := before if before in solved else id
		solved.erase(target)
		strikes.erase(target)
		strikes.erase(id)
		result.setback_question_id = target
	return result

func _guest_profile() -> Dictionary:
	var badges: Array = []
	for level in GUEST_LEVELS:
		if level in guest_badges:
			badges.append(GUEST_LEVELS[level].badge)
	return {"badges": badges, "progress_ratio": float(badges.size()) / GUEST_LEVELS.size()}
