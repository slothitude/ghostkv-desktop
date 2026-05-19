extends Node

## Lightweight HTTP API server for remote control.
## POST /send  {"message": "..."}  — inject a user message into the chat
## GET  /ping                    — health check
## Listens on port 9797 (configurable).

var _server: TCPServer
var _chat_view: Node = null
var _port: int = 9797

func _ready() -> void:
	_server = TCPServer.new()
	var err := _server.listen(_port)
	if err == OK:
		print("GhostKV Remote API listening on port ", _port)
	else:
		push_warning("Remote API: could not listen on port %d (error %d)" % [_port, err])

func _process(_delta: float) -> void:
	if not _server or not _server.is_connection_available():
		return

	var peer: StreamPeerTCP = _server.take_connection()
	if not peer:
		return

	# Read the request (non-blocking, small payload expected)
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	var data: PackedByteArray
	while true:
		var chunk: PackedByteArray = peer.get_partial_data(4096)[1]
		if chunk.is_empty():
			break
		data.append_array(chunk)
		# Check if we have the full request (ends with \r\n\r\n or body received)
		var header_str := data.get_string_from_ascii()
		var headers_end: int = header_str.find("\r\n\r\n")
		if headers_end >= 0:
			var cl: int = _get_content_length(header_str.left(headers_end))
			var body_start: int = headers_end + 4
			if header_str.length() >= body_start + cl:
				break

	var request: String = data.get_string_from_ascii()
	if request.is_empty():
		return

	var lines: PackedStringArray = request.split("\r\n")
	if lines.is_empty():
		return

	var first_line: PackedStringArray = lines[0].split(" ")
	if first_line.size() < 2:
		return

	var method: String = first_line[0]
	var path: String = first_line[1]

	# Extract body
	var body: String = ""
	var body_start: int = request.find("\r\n\r\n")
	if body_start >= 0:
		body = request.substr(body_start + 4)

	var response: String = ""

	if path == "/ping":
		response = _json_response(200, {"status": "ok", "app": "GhostKV"})

	elif path == "/send" and method == "POST":
		var json := JSON.new()
		if json.parse(body) == OK and json.data is Dictionary:
			var msg: String = json.data.get("message", "")
			if not msg.is_empty():
				_inject_message(msg)
				response = _json_response(200, {"status": "sent", "message": msg})
			else:
				response = _json_response(400, {"error": "empty message"})
		else:
			response = _json_response(400, {"error": "invalid JSON"})

	else:
		response = _json_response(404, {"error": "not found"})

	peer.put_data(response.to_utf8_buffer())
	peer.disconnect_from_host()

func _get_content_length(headers: String) -> int:
	for line in headers.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return int(line.split(":")[1].strip_edges())
	return 0

func _json_response(code: int, data: Dictionary) -> String:
	var status: String = "OK" if code == 200 else "Error"
	var body: String = JSON.stringify(data)
	return "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [code, status, body.length(), body]

func _inject_message(text: String) -> void:
	# Call _on_message_sent on the App node (same as typing in the input bar)
	var app := _find_node(get_tree().root, "App")
	print("RemoteAPI: inject_message '%s' app=%s" % [text, app])
	if app and app.has_method("_on_message_sent"):
		print("RemoteAPI: calling _on_message_sent on App node")
		app.call("_on_message_sent", text)
		return
	# Fallback: run react loop directly (won't show in UI but will process)
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	print("RemoteAPI: fallback react_loop=%s" % react_loop)
	if react_loop and not react_loop.is_running():
		react_loop.run(text)

func _find_node(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var found := _find_node(child, name)
		if found:
			return found
	return null
