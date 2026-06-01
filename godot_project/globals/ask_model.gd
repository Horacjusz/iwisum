extends Node

const PYTHON_EXECUTABLE := "res://../python/.venv/bin/python"
const SERVICE_SCRIPT := "res://../python/ask_model_service.py"
const HOST := "127.0.0.1"
const FIRST_PORT := 8000
const LAST_PORT := 8099
const REQUEST_TIMEOUT_MS := 200
const STARTUP_TIMEOUT_MS := 3000
const FALLBACK_ACTION := 4

var port := -1
var process_id := -1
var service_ready := false

func _ready() -> void:
	port = _find_free_port()
	if port == -1:
		push_error("AskModel: could not find a free localhost port")
		return

	var python_path = ProjectSettings.globalize_path(PYTHON_EXECUTABLE)
	var script_path = ProjectSettings.globalize_path(SERVICE_SCRIPT)
	var args = [script_path, "--host", HOST, "--port", str(port)]
	process_id = OS.create_process(python_path, args)
	if process_id == -1:
		push_error("AskModel: failed to start Python model service")
		return

	service_ready = _wait_until_service_ready()
	if not service_ready:
		push_warning("AskModel: Python model service did not become ready, using fallback action")

func _exit_tree() -> void:
	if process_id > 0:
		OS.kill(process_id)

func ask_model(passenger) -> int:
	var observation = _create_observation(passenger)
	if observation.is_empty():
		return FALLBACK_ACTION

	var response = _post_json("/ask_model", observation)
	var action = int(response.get("action", -1))
	if action < 0 or action > 4:
		return FALLBACK_ACTION
	return action

func _create_observation(passenger) -> Dictionary:
	if passenger == null or passenger.city_map == null:
		return {}

	var nodes = passenger.city_map.nodes
	var current_node = passenger.current_node
	var target_node = passenger.end_node
	var current_id = nodes.find(current_node)
	var target_id = nodes.find(target_node)

	if current_id == -1 or target_id == -1:
		return {}

	return {
		"position": current_id,
		"target": target_id,
		"time": Globals.TICK,
	}

func _find_free_port() -> int:
	for candidate_port in range(FIRST_PORT, LAST_PORT + 1):
		var server = TCPServer.new()
		var err = server.listen(candidate_port, HOST)
		server.stop()
		if err == OK:
			return candidate_port
	return -1

func _wait_until_service_ready() -> bool:
	var started_at = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at < STARTUP_TIMEOUT_MS:
		if _health_check():
			return true
		OS.delay_msec(50)
	return false

func _health_check() -> bool:
	var response = _request_json(HTTPClient.METHOD_GET, "/health", {})
	return response.get("status", "") == "ok"

func _post_json(path: String, payload: Dictionary) -> Dictionary:
	return _request_json(HTTPClient.METHOD_POST, path, payload)

func _request_json(method: int, path: String, payload: Dictionary) -> Dictionary:
	var http = HTTPClient.new()
	var err = http.connect_to_host("http://" + HOST, port)
	if err != OK:
		return {}

	if not _wait_for_status(http, [HTTPClient.STATUS_CONNECTED], REQUEST_TIMEOUT_MS):
		return {}

	var headers = ["Content-Type: application/json"]
	var body = ""
	if method == HTTPClient.METHOD_POST:
		body = JSON.stringify(payload)

	err = http.request(method, path, headers, body)
	if err != OK:
		return {}

	if not _wait_for_response(http, REQUEST_TIMEOUT_MS):
		return {}

	if http.get_response_code() != 200:
		return {}

	var response_body := PackedByteArray()
	var started_at = Time.get_ticks_msec()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk = http.read_response_body_chunk()
		if chunk.size() == 0:
			OS.delay_msec(1)
		else:
			response_body.append_array(chunk)

		if Time.get_ticks_msec() - started_at > REQUEST_TIMEOUT_MS:
			return {}

	var text = response_body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(text) != OK:
		return {}
	if not (json.data is Dictionary):
		return {}
	return json.data

func _wait_for_status(http: HTTPClient, expected_statuses: Array, timeout_ms: int) -> bool:
	var started_at = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at <= timeout_ms:
		http.poll()
		if http.get_status() in expected_statuses:
			return true
		if http.get_status() == HTTPClient.STATUS_CANT_CONNECT or http.get_status() == HTTPClient.STATUS_CANT_RESOLVE:
			return false
		OS.delay_msec(1)
	return false

func _wait_for_response(http: HTTPClient, timeout_ms: int) -> bool:
	var started_at = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at <= timeout_ms:
		http.poll()
		var status = http.get_status()
		if status == HTTPClient.STATUS_BODY:
			return true
		if status == HTTPClient.STATUS_CANT_CONNECT or status == HTTPClient.STATUS_CANT_RESOLVE or status == HTTPClient.STATUS_DISCONNECTED:
			return false
		OS.delay_msec(1)
	return false
