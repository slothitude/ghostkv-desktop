extends Node

signal tools_discovered(tools: Array)
signal tool_result_ready(name: String, result: String)
signal connection_failed(msg: String)
signal connection_status_changed(status: String)  # "connecting", "connected", "failed"

var sse_url: String = ""
var _server_name: String = ""
var _base_url: String = ""
var _message_endpoint: String = ""
var _sse_client: HTTPClient  # Persistent SSE connection for reading responses
var _discovered_tools: Array = []
var _connected: bool = false
var _request_id: int = 0
var _pending_results: Dictionary = {}  # id -> {"completed": bool, "data":Variant}

# Reconnect state
var _retry_count: int = 0
var _max_retries: int = 3
var _retry_timer: Timer

# SSE read buffer
var _sse_buffer: String = ""

func _ready() -> void:
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
	_do_sse_handshake()

func _do_sse_handshake() -> void:
	var http := HTTPClient.new()
	var url_parts := _parse_url(sse_url)
	var host: String = url_parts["host"]
	var port: int = url_parts["port"]
	var path: String = url_parts["path"]
	var use_tls: bool = url_parts["tls"]

	var tls_options: TLSOptions = TLSOptions.client() if use_tls else null
	var err := http.connect_to_host(host, port, tls_options)
	if err != OK:
		_handle_connection_failure("Failed to connect to %s:%d" % [host, port])
		return

	# Wait for connection
	var timeout := Time.get_ticks_msec() + 5000
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if Time.get_ticks_msec() > timeout:
			_handle_connection_failure("Connection timeout")
			return
		await get_tree().process_frame

	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		_handle_connection_failure("Connect failed, status=%d" % http.get_status())
		return

	# Send GET for SSE
	var headers := ["Host: %s" % host, "Accept: text/event-stream", "Cache-Control: no-cache"]
	err = http.request(HTTPClient.METHOD_GET, path, headers)
	if err != OK:
		_handle_connection_failure("SSE request failed")
		return

	# Wait for response
	timeout = Time.get_ticks_msec() + 5000
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if Time.get_ticks_msec() > timeout:
			_handle_connection_failure("SSE request timeout")
			return
		await get_tree().process_frame

	if http.get_status() != HTTPClient.STATUS_BODY:
		_handle_connection_failure("SSE bad status: %d" % http.get_status())
		return

	# Read initial SSE data to get endpoint
	http.poll()
	var chunk := http.read_response_body_chunk()
	var text := chunk.get_string_from_utf8()
	print("MCPClient[%s]: SSE handshake got len=%d" % [_server_name, text.length()])

	# Parse endpoint from SSE
	var endpoint := _parse_sse_endpoint(text)
	if endpoint.is_empty():
		_message_endpoint = _base_url + "/messages/"
	else:
		if endpoint.begins_with("http"):
			_message_endpoint = endpoint
		else:
			_message_endpoint = _base_url + endpoint

	# Keep SSE client alive for reading responses
	_sse_client = http
	_sse_buffer = ""

	_connected = true
	_retry_count = 0
	connection_status_changed.emit("connected")

	# Start polling SSE for responses (runs in background via await loop)
	_poll_sse()

	# Discover tools (runs concurrently since _poll_sse yields via await)
	# Need to wait a frame for polling to start
	await get_tree().process_frame
	_discover_tools()

func _poll_sse() -> void:
	# Continuously read SSE events from the persistent connection
	while _sse_client and _sse_client.get_status() == HTTPClient.STATUS_BODY:
		_sse_client.poll()
		var chunk := _sse_client.read_response_body_chunk()
		if chunk.size() > 0:
			_sse_buffer += chunk.get_string_from_utf8()
			_process_sse_buffer()
		await get_tree().process_frame

func _process_sse_buffer() -> void:
	# Process complete SSE events (separated by blank lines)
	while true:
		var event_end := _sse_buffer.find("\n\n")
		if event_end < 0:
			break
		var event_text: String = _sse_buffer.substr(0, event_end)
		_sse_buffer = _sse_buffer.substr(event_end + 2)
		_handle_sse_event(event_text)

func _handle_sse_event(event_text: String) -> void:
	print("MCPClient[%s]: SSE event: %s" % [_server_name, event_text.left(200)])
	# Parse SSE event lines
	for line in event_text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("data:"):
			var data_str := stripped.substr(5).strip_edges()
			if data_str.is_empty():
				continue
			var json := JSON.new()
			if json.parse(data_str) != OK:
				continue
			var data = json.data
			if not data is Dictionary:
				continue
			# JSON-RPC response
			if data.has("id"):
				var id_val = data["id"]
				_pending_results[id_val] = {"completed": true, "data": data}
			# Check for tools in result
			if data.has("result") and data["result"] is Dictionary:
				var res: Dictionary = data["result"]
				if res.has("tools"):
					_discovered_tools = res["tools"]
					tools_discovered.emit(_discovered_tools)

func _parse_url(url: String) -> Dictionary:
	var tls: bool = false
	var host: String = ""
	var port: int = 80
	var path: String = "/"
	if url.begins_with("https://"):
		tls = true
		port = 443
		url = url.substr(8)
	elif url.begins_with("http://"):
		url = url.substr(7)
	var slash_pos := url.find("/")
	if slash_pos >= 0:
		path = url.substr(slash_pos)
		url = url.substr(0, slash_pos)
	var colon_pos := url.find(":")
	if colon_pos >= 0:
		port = int(url.substr(colon_pos + 1))
		host = url.substr(0, colon_pos)
	else:
		host = url
	return {"host": host, "port": port, "path": path, "tls": tls}

func _parse_sse_endpoint(text: String) -> String:
	var in_endpoint_event := false
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped == "event: endpoint":
			in_endpoint_event = true
			continue
		if stripped.begins_with("data:"):
			var data_str := stripped.substr(5).strip_edges()
			var json := JSON.new()
			if json.parse(data_str) == OK and json.data is Dictionary:
				if json.data.has("endpoint"):
					return json.data["endpoint"]
			if in_endpoint_event and not data_str.is_empty():
				return data_str
			in_endpoint_event = false
		if stripped == "":
			in_endpoint_event = false
	return ""

func _handle_connection_failure(msg: String) -> void:
	_connected = false
	if _retry_count < _max_retries:
		_retry_count += 1
		var delay := 2.0 * _retry_count
		connection_status_changed.emit("retrying (%d/%d in %.0fs)" % [_retry_count, _max_retries, delay])
		_retry_timer.start(delay)
	else:
		connection_status_changed.emit("failed")
		connection_failed.emit(msg)

func _on_retry() -> void:
	_do_connect()

func _discover_tools() -> void:
	print("MCPClient[%s]: _discover_tools endpoint=%s" % [_server_name, _message_endpoint])
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
	var req_id: int = _request_id
	var body := {
		"jsonrpc": "2.0",
		"id": req_id,
		"method": "tools/call",
		"params": {
			"name": name,
			"arguments": args
		}
	}
	_send_jsonrpc(body)

	# Wait for response via SSE (with timeout)
	var timeout := Time.get_ticks_msec() + 30000
	while not _pending_results.has(req_id):
		if Time.get_ticks_msec() > timeout:
			return "Error: Tool call timed out"
		await get_tree().process_frame

	var result_entry: Dictionary = _pending_results[req_id]
	_pending_results.erase(req_id)
	var data: Dictionary = result_entry["data"]

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
	print("MCPClient[%s]: _send_jsonrpc id=%d" % [_server_name, body.get("id", 0)])
	# Send via the SSE client's connection (it's still open)
	# We need a separate HTTPClient for POSTing since the SSE one is reading
	var url_parts := _parse_url(_message_endpoint)
	var host: String = url_parts["host"]
	var port: int = url_parts["port"]
	var path_and_query: String = url_parts["path"]
	var use_tls: bool = url_parts["tls"]

	var post_client := HTTPClient.new()
	var tls_options: TLSOptions = TLSOptions.client() if use_tls else null
	post_client.connect_to_host(host, port, tls_options)

	# Wait for connection
	var timeout := Time.get_ticks_msec() + 5000
	while post_client.get_status() == HTTPClient.STATUS_CONNECTING or post_client.get_status() == HTTPClient.STATUS_RESOLVING:
		post_client.poll()
		if Time.get_ticks_msec() > timeout:
			return
		await get_tree().process_frame

	if post_client.get_status() != HTTPClient.STATUS_CONNECTED:
		return

	var json_body := JSON.stringify(body)
	var headers := ["Host: %s" % host, "Content-Type: application/json", "Content-Length: %d" % json_body.length()]
	var err := post_client.request(HTTPClient.METHOD_POST, path_and_query, headers, json_body)
	if err != OK:
		return

	# Wait for response (just to complete the request — actual result comes via SSE)
	timeout = Time.get_ticks_msec() + 5000
	while post_client.get_status() == HTTPClient.STATUS_REQUESTING:
		post_client.poll()
		if Time.get_ticks_msec() > timeout:
			break
		await get_tree().process_frame

	# Read and discard the 202 response
	if post_client.get_status() == HTTPClient.STATUS_BODY:
		post_client.poll()
		post_client.read_response_body_chunk()

	post_client.close()

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
	_retry_count = _max_retries + 1
	_discovered_tools.clear()
	if _sse_client:
		_sse_client.close()
		_sse_client = null
