extends Node

signal profile_changed

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const GUEST_ROOMS := "res://levels/level_1/guest_rooms.json"

var earned_badges: Array[String] = []
var levels: Array = []
var progress_ratio: float = 0.0
var api_base: String = ""
var last_error: String = ""
# Guest mode answers API calls in memory: nothing reaches the server and a reload starts over.
var guest: bool = false
var guest_rooms: Array = []
var guest_solved: Array = []
var guest_strikes: Dictionary = {}
var guest_badge: bool = false
var guest_run_done: bool = false

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
	guest_rooms = JSON.parse_string(FileAccess.get_file_as_string(GUEST_ROOMS))
	guest_solved.clear()
	guest_strikes.clear()
	guest_badge = false
	guest_run_done = false

# Mirrors the responses of server/gameplay.py for Level 1, graded by the client interpreter.
func _guest_request(path: String, body: Dictionary) -> Dictionary:
	match path:
		"/me":
			return {"ok": true, "data": _guest_profile()}
		"/levels":
			return {"ok": true, "data": [{"id": 1, "is_active": true}]}
		"/runs":
			if int(body.get("level_id", 0)) != 1:
				return {"ok": false, "error": "Guest mode only includes Level 1.", "status": 404}
			if guest_run_done:
				guest_solved.clear()
				guest_strikes.clear()
				guest_run_done = false
			var questions: Array = []
			for room in guest_rooms:
				questions.append({"id": "guest-%d" % int(room.ordinal), "type": "puzzle", "prompt": room.prompt,
					"code_snippet": null, "hint": room.hint, "payload": room.payload})
			return {"ok": true, "data": {"id": "guest", "level_id": 1, "outcome": "in_progress",
				"questions": questions, "solved_question_ids": guest_solved.duplicate(),
				"strikes": guest_strikes.duplicate()}}
		"/runs/guest/attempts":
			for i in range(guest_rooms.size()):
				var id := _guest_id(i)
				if id == body.question_id:
					return {"ok": true, "data": _guest_attempt(i, body.response)}
			return {"ok": false, "error": "Question does not belong to this run.", "status": 404}
		"/runs/guest/finish":
			if not guest_run_done and guest_solved.size() < guest_rooms.size():
				return {"ok": false, "error": "Answer every question correctly before finishing.", "status": 409}
			guest_badge = true
			guest_run_done = true
			return {"ok": true, "data": _guest_profile()}
	return {"ok": false, "error": "Guest mode cannot reach the server.", "status": 404}

func _guest_id(index: int) -> String:
	return "guest-%d" % int(guest_rooms[index].ordinal)

# Mirrors attempt() and strike() in server/gameplay.py: a gate's third strike reopens the gate before it.
func _guest_attempt(index: int, response: Dictionary) -> Dictionary:
	var id := _guest_id(index)
	var room: Dictionary = guest_rooms[index]
	if id in guest_solved:
		return {"is_correct": true, "explanation": room.explanation}
	var result := {"is_correct": PuzzleRoom.grade(room.payload, response), "explanation": room.explanation,
		"strikes": 0, "setback_question_id": null}
	if result.is_correct:
		guest_solved.append(id)
		if index + 1 < guest_rooms.size():
			guest_strikes.erase(_guest_id(index + 1))
		return result
	result.strikes = int(guest_strikes.get(id, 0)) + 1
	guest_strikes[id] = result.strikes
	if result.strikes >= PuzzleRoom.STRIKES:
		var target := _guest_id(index - 1) if index > 0 and _guest_id(index - 1) in guest_solved else id
		guest_solved.erase(target)
		guest_strikes.erase(target)
		guest_strikes.erase(id)
		result.setback_question_id = target
	return result

func _guest_profile() -> Dictionary:
	var badges := [{"slug": "badge_1", "name": "Basic Instructions Master"}] if guest_badge else []
	return {"badges": badges, "progress_ratio": 1.0 if guest_badge else 0.0}
