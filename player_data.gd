extends Node

signal profile_changed

const PuzzleRoom := preload("res://levels/level_1/puzzle_room.gd")
const MazeRoom := preload("res://levels/level_2/maze_room.gd")
const CodeRoom := preload("res://levels/level_2/code_room.gd")
const CallMachine := preload("res://levels/level_3/call_machine.gd")
const WaveRoom := preload("res://levels/level_4/wave_room.gd")
const TableRoom := preload("res://levels/level_4/table_room.gd")
## The levels guest mode can play, each from a copy of its gates kept in sync with the database. A
## level's copy is a list of rooms, or its whole bank and draw rule when its runs draw their rooms.
const GUEST_LEVELS := {
	1: {"rooms": "res://levels/level_1/guest_rooms.json", "badge": {"slug": "badge_1", "name": "Basic Instructions Master"}},
	2: {"rooms": "res://levels/level_2/guest_rooms.json", "badge": {"slug": "badge_2", "name": "Memory Master"}},
	3: {"rooms": "res://levels/level_3/guest_rooms.json", "badge": {"slug": "badge_3", "name": "Stack Master"}},
	4: {"rooms": "res://levels/level_4/guest_rooms.json", "badge": {"slug": "badge_4", "name": "Timing Master"}},
}

var earned_badges: Array[String] = []
var levels: Array = []
var progress_ratio: float = 0.0
var api_base: String = ""
var last_error: String = ""
var onyen := ""
var is_staff := false
var leaderboard_visible := true
# The nickname the player picked ("" for none) and the name the leaderboard shows: it, or "Player <number>".
var nickname := ""
var leaderboard_name := ""
var profile_loaded := false
# Guest mode answers API calls in memory: nothing reaches the server and a reload starts over.
var guest: bool = false
# Per level ID: every room it can draw from (with its draw rule, if any), the rooms of its current
# run, the gates solved, strikes by gate, and whether its run finished.
var guest_banks: Dictionary = {}
var guest_rooms: Dictionary = {}
var guest_solved: Dictionary = {}
var guest_strikes: Dictionary = {}
var guest_shown: Dictionary = {}  # Per level: the gates whose answer was shown, which earn one star.
var guest_run_done: Dictionary = {}
# Per level: how many runs each room (by ordinal) has been drawn into since guest mode started, and
# the rooms of the latest run. A guest's draw uses them as the server uses a player's session.
var guest_played: Dictionary = {}
var guest_gate_stars: Dictionary = {}  # Per level: the stars of each gate opened in the current run.
var guest_best: Dictionary = {}  # Per level: [best stars, out of], over the finished runs.
var guest_started: Array = []  # The levels whose current run has been opened, as a server run starts.
var guest_last: Dictionary = {}
var guest_badges: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	onyen = str(profile.get("onyen", onyen))
	is_staff = bool(profile.get("is_staff", is_staff)) and not guest
	leaderboard_visible = bool(profile.get("leaderboard_visible", leaderboard_visible))
	if profile.has("nickname"):
		nickname = str(profile.nickname) if profile.nickname is String else ""
	leaderboard_name = str(profile.get("leaderboard_name", leaderboard_name))
	profile_loaded = true
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
	onyen = ""
	is_staff = false
	leaderboard_visible = false
	nickname = ""
	leaderboard_name = ""
	profile_loaded = false
	guest_badges.clear()
	guest_started.clear()
	for level in GUEST_LEVELS:
		var bank = JSON.parse_string(FileAccess.get_file_as_string(GUEST_LEVELS[level].rooms))
		guest_banks[level] = bank if bank is Dictionary else {"rooms": bank}
		guest_played[level] = {}
		guest_last[level] = []
		guest_gate_stars[level] = {}
		guest_rooms[level] = _guest_draw(level)
		guest_solved[level] = []
		guest_strikes[level] = {}
		guest_shown[level] = []
		guest_run_done[level] = false

# Mirrors the responses of server/gameplay.py for the guest levels, graded by the client interpreters.
# A guest run's ID is "guest-<level>", so its attempts post to /runs/guest-<level>/attempts.
func _guest_request(path: String, body: Dictionary) -> Dictionary:
	if path == "/me":
		return {"ok": true, "data": _guest_profile()}
	if path == "/levels":
		var listed: Array = []
		for level in GUEST_LEVELS:
			var going = null
			if level in guest_started and not guest_run_done[level]:
				going = {"solved": guest_solved[level].size(), "total": guest_rooms[level].size()}
			var best: Array = guest_best.get(level, [null, null])
			listed.append({"id": level, "is_active": true, "completed": level in guest_badges,
				"best_stars": best[0], "max_stars": best[1], "in_progress": going})
		return {"ok": true, "data": listed}
	if path == "/runs":
		var level := int(body.get("level_id", 0))
		if not GUEST_LEVELS.has(level):
			return {"ok": false, "error": "Guest mode only includes Levels 1 to 4.", "status": 404}
		if guest_run_done[level]:
			guest_rooms[level] = _guest_draw(level)
			guest_gate_stars[level] = {}
			guest_solved[level] = []
			guest_strikes[level] = {}
			guest_shown[level] = []
			guest_run_done[level] = false
		if level not in guest_started:
			guest_started.append(level)
		return {"ok": true, "data": _guest_run(level)}
	var parts := path.split("/")  # "", "runs", "guest-<level>", then "attempts", "events", "reopen", or "finish"
	var level := int(parts[2].trim_prefix("guest-")) if parts.size() == 4 and parts[2].begins_with("guest-") else 0
	if not GUEST_LEVELS.has(level):
		return {"ok": false, "error": "Guest mode cannot reach the server.", "status": 404}
	if parts[3] == "reopen":
		# Mirrors reopen() in server/gameplay.py: a gate the player goes back to closes again.
		guest_solved[level].erase(body.question_id)
		guest_strikes[level].erase(body.question_id)
		return {"ok": true, "data": _guest_run(level)}
	if parts[3] == "events":
		# The only event guest mode answers is Show answer, which caps the gate at one star.
		for room in guest_rooms[level]:
			if _guest_id(level, room) == body.question_id and body.get("kind") == "answer" and room.has("answer"):
				if body.question_id not in guest_shown[level]:
					guest_shown[level].append(body.question_id)
				return {"ok": true, "data": {"is_correct": null, "answer": room.answer, "question_stats": {}}}
		return {"ok": false, "error": "This question has no answer to show.", "status": 422}
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
		if not guest_run_done[level]:
			var total := 0
			for stars in guest_gate_stars[level].values():
				total += int(stars)
			if not guest_best.has(level) or total > int(guest_best[level][0]):
				guest_best[level] = [total, 3 * guest_rooms[level].size()]
		guest_run_done[level] = true
		return {"ok": true, "data": _guest_profile()}
	return {"ok": false, "error": "Guest mode cannot reach the server.", "status": 404}

# A guest run as server/gameplay.py's run_view gives it: its rooms without their answers, the gates
# open now, and the strikes on the others.
func _guest_run(level: int) -> Dictionary:
	var questions: Array = []
	for room in guest_rooms[level]:
		questions.append({"id": _guest_id(level, room), "type": "puzzle", "prompt": room.prompt,
			"code_snippet": room.get("code_snippet"), "hint": room.hint, "payload": room.payload})
	return {"id": "guest-%d" % level, "level_id": level, "outcome": "in_progress", "questions": questions,
		"solved_question_ids": guest_solved[level].duplicate(), "strikes": guest_strikes[level].duplicate()}

# Mirrors draw() in server/gameplay.py: without a draw rule a run plays every room; with one, each
# pool in the rule gives all its rooms, or `take` of them, kept in ordinal order. A pool that takes
# some picks the rooms drawn least since guest mode started (so none comes back until the whole
# pool has been played), then avoids the latest run's, then picks at random.
func _guest_draw(level: int) -> Array:
	var bank: Dictionary = guest_banks[level]
	var rooms: Array = bank.rooms
	if not bank.has("draw"):
		return rooms.duplicate()
	var played: Dictionary = guest_played[level]
	var last: Array = guest_last[level]
	var picked: Array = []
	for slot in bank.draw:
		var pool := rooms.filter(func(room): return room.get("pool") == slot.pool)
		var keys := {}  # Ordinal: [times drawn, 1 if in the latest run, a random tiebreak].
		for room in pool:
			var ordinal := int(room.ordinal)
			keys[ordinal] = [int(played.get(ordinal, 0)), int(ordinal in last), randf()]
		var ranked := pool.duplicate()
		ranked.sort_custom(func(a, b): return _ranks_before(keys[int(a.ordinal)], keys[int(b.ordinal)]))
		var chosen: Array = ranked.slice(0, mini(int(slot.get("take", pool.size())), pool.size())).map(
			func(room): return int(room.ordinal))
		picked.append_array(pool.filter(func(room): return int(room.ordinal) in chosen))
	guest_last[level] = picked.map(func(room): return int(room.ordinal))
	for ordinal in guest_last[level]:
		played[ordinal] = int(played.get(ordinal, 0)) + 1
	return picked

# Whether one room's draw key comes before another's: fewer plays first, then not in the latest
# run, then the random tiebreak.
static func _ranks_before(a: Array, b: Array) -> bool:
	for k in range(a.size()):
		if a[k] != b[k]:
			return a[k] < b[k]
	return false

## Remembers the stars a guest's gate opened with, for the Control Center's best-stars line. Like the
## server, a gate the guest went back to keeps the best stars it has opened with.
func note_guest_stars(level: int, question_id: String, stars: int) -> void:
	if guest and guest_gate_stars.has(level):
		guest_gate_stars[level][question_id] = maxi(stars, int(guest_gate_stars[level].get(question_id, 0)))

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
		"walk":
			correct = CallMachine.grade(payload, response)
		"wave":
			correct = WaveRoom.grade(payload, response)
		"table":
			correct = TableRoom.grade(payload, response)
		_:
			correct = PuzzleRoom.grade(payload, response)
	var result := {"is_correct": correct, "explanation": room.explanation, "strikes": 0, "setback_question_id": null}
	if correct:
		solved.append(id)
		if id in guest_shown[level]:
			result.stars = 1
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
