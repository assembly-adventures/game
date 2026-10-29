extends Node
## Keep learning events until the server acknowledges them. Request IDs survive a reload,
## so a lost response cannot count a mistake twice. Queues belong to the signed-in account.

signal saved(run_id: String, question_id: String, stats: Dictionary)

const PATH := "user://learning_events.json"
var queues: Dictionary = {}
var sending: Dictionary = {}
var results: Dictionary = {}
var last_error := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Dictionary:
			queues = data

func _key(run_id: String) -> String:
	return PlayerData.onyen.to_lower() + ":" + run_id

func record(run_id: String, question_id: String, kind: String, detail: Dictionary) -> void:
	if PlayerData.guest:
		return
	var key := _key(run_id)
	if not queues.has(key):
		queues[key] = []
	var event := detail.duplicate(true)
	event.merge({"question_id": question_id, "request_id": PlayerData.new_request_id(), "kind": kind}, true)
	queues[key].append(event)
	_persist()

func flush(run_id: String) -> bool:
	if PlayerData.guest:
		return true
	var key := _key(run_id)
	if sending.get(key, false):
		while sending.get(key, false):
			await get_tree().process_frame
		return bool(results.get(key, false))
	sending[key] = true
	results[key] = false
	while not queues.get(key, []).is_empty():
		var event: Dictionary = queues[key][0]
		var result := await PlayerData.api_request("/runs/%s/events" % run_id, HTTPClient.METHOD_POST, event)
		if not result.ok:
			last_error = str(result.error)
			sending[key] = false
			return false
		queues[key].pop_front()
		_persist()
		saved.emit(run_id, str(event.question_id), result.data.get("question_stats", {}))
	queues.erase(key)
	_persist()
	last_error = ""
	results[key] = true
	sending[key] = false
	return true

func _persist() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(queues))
