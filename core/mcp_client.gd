extends Node

signal tools_discovered(tools: Array)
signal tool_result_ready(name: String, result: String)
signal connection_failed(msg: String)
signal connection_status_changed(status: String)  # "connecting", "connected", "failed"

var sse_url: String = ""
var _server_name: String = ""
var _base_url: String = ""
var _message_endpoint: String = ""
var _http_get: HTTPRequest
var _http_post: HTTPRequest
var _discovered_tools: Array = []
var _connected: bool = false
var _request_id: int = 0

# Reconnect state
var _retry_count: int = 0
var _max_retries: int = 3
var _retry_timer: Timer

func _ready() -> void:
	_http_get = HTTPRequest.new()
	_http_post = HTTPRequest.new()
	add_child(_http_get)
	add_child(_http_post)
	_http_get.request_completed.connect(_on_sse_connected)
	_http_post.request_completed.connect(_on_post_response)

	# Retry timer
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_on_retry)
	add_child(_retry_timer)

func connect_server(server_name: String, url: String) -> void:
	_server_name = server_name
	sse_url = url
	_base_url = url.replace("/sse", "")
	_retry_count = 0
	_do_connect()

func _do_connect() -> void:
	connection_status_changed.emit("connecting")
	var headers := [
		"Accept: text/event-stream",
		"Cache-Control: no-cache"
	]
	_http_get.request(sse_url, headers, HTTPClient.METHOD_GET)

func _on_sse_connected(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_handle_connection_failure("SSE connection failed: %d" % code)
		return

	# Parse SSE response to find the message endpoint
	var text := body.get_string_from_utf8()
	var endpoint := ""
	for line in text.split("\n"):
		if line.begins_with("data:"):
			var data_str := line.substr(5).strip_edges()
			var json := JSON.new()
			if json.parse(data_str) == OK:
				var data: Dictionary = json.data
				if data.has("endpoint"):
					endpoint = data["endpoint"]
					break

	if endpoint.is_empty():
		_message_endpoint = _base_url + "/message"
	else:
		if endpoint.begins_with("http"):
			_message_endpoint = endpoint
		else:
			_message_endpoint = _base_url + endpoint

	_connected = true
	_retry_count = 0
	connection_status_changed.emit("connected")
	_discover_tools()

func _handle_connection_failure(msg: String) -> void:
	_connected = false
	if _retry_count < _max_retries:
		_retry_count += 1
		var delay := 2.0 * _retry_count  # 2s, 4s, 6s backoff
		connection_status_changed.emit("retrying (%d/%d in %.0fs)" % [_retry_count, _max_retries, delay])
		_retry_timer.start(delay)
	else:
		connection_status_changed.emit("failed")
		connection_failed.emit(msg)

func _on_retry() -> void:
	_do_connect()

func _discover_tools() -> void:
	_request_id += 1
	var body := {
		"jsonrpc": "2.0",
		"id": _request_id,
		"method": "tools/list",
		"params": {}
	}
	_send_jsonrpc(body)

func call_tool(name: String, args: Dictionary) -> String:
	if not _connected:
		return "Error: Not connected to MCP server"

	_request_id += 1
	var body := {
		"jsonrpc": "2.0",
		"id": _request_id,
		"method": "tools/call",
		"params": {
			"name": name,
			"arguments": args
		}
	}
	var headers := ["Content-Type: application/json"]
	var json_body := JSON.stringify(body)
	var err := _http_post.request(_message_endpoint, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		return "Error: Failed to send tool call"

	var response: Array = await _http_post.request_completed
	var result: int = response[0]
	var code: int = response[1]
	var resp_body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return "Error: Tool call failed (%d)" % code

	var json := JSON.new()
	if json.parse(resp_body.get_string_from_utf8()) != OK:
		return "Error: Invalid JSON response"

	var data: Dictionary = json.data
	if data.has("error"):
		return "Error: %s" % str(data["error"])

	if data.has("result"):
		var res = data["result"]
		if res is Dictionary:
			if res.has("content"):
				var content = res["content"]
				if content is Array and content.size() > 0:
					return str(content[0].get("text", str(content[0])))
				return str(content)
			return JSON.stringify(res, "\t")
		return str(res)

	return "No result"

func _send_jsonrpc(body: Dictionary) -> void:
	var headers := ["Content-Type: application/json"]
	var json_body := JSON.stringify(body)
	_http_post.request(_message_endpoint, headers, HTTPClient.METHOD_POST, json_body)

func _on_post_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return

	var data: Dictionary = json.data
	if data.has("result") and data["result"] is Dictionary:
		var res: Dictionary = data["result"]
		if res.has("tools"):
			_discovered_tools = res["tools"]
			tools_discovered.emit(_discovered_tools)

func get_discovered_tools() -> Array:
	return _discovered_tools

func get_tool_description(tool_name: String) -> String:
	for tool in _discovered_tools:
		if tool.get("name", "") == tool_name:
			return tool.get("description", "")
	return ""

func get_tool_schema(tool_name: String) -> Dictionary:
	for tool in _discovered_tools:
		if tool.get("name", "") == tool_name:
			return tool.get("inputSchema", {})
	return {}

func is_server_connected() -> bool:
	return _connected

func get_server_name() -> String:
	return _server_name

func disconnect_server() -> void:
	_connected = false
	_retry_timer.stop()
	_retry_count = _max_retries + 1  # Prevent further retries
	_discovered_tools.clear()
