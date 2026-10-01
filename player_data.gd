extends Node

signal profile_changed

var earned_badges: Array[String] = []
var levels: Array = []
var progress_ratio: float = 0.0
var api_base: String = ""
var last_error: String = ""

func _ready() -> void:
	if OS.has_feature("web"):
		api_base = str(JavaScriptBridge.eval("window.location.origin"))

func api_request(path: String, method: int = HTTPClient.METHOD_GET, body: Dictionary = {}) -> Dictionary:
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
