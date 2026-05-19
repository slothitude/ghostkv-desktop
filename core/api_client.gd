extends Node

signal response_received(text: String, usage: Dictionary)
signal error_occurred(msg: String)
signal stream_token(token: String)
signal stream_started()
signal stream_finished(text: String, usage: Dictionary)

var _http: HTTPRequest
var _base_url: String = ""
var _api_key: String = ""
var _model: String = "glm-5.1"

# Streaming state
var _stream_client: HTTPClient
var _streaming: bool = false
var _stream_buffer: String = ""
var _stream_usage: Dictionary = {}
var _stream_response_buffer: PackedByteArray = PackedByteArray()

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func configure(base_url: String, api_key: String, model: String) -> void:
	_base_url = base_url
	_api_key = api_key
	_model = model

# --- Non-streaming path (fallback) ---

func generate(messages: Array, temperature: float = 0.8, max_tokens: int = 2048) -> void:
	if _base_url.is_empty():
		error_occurred.emit("API base URL not configured")
		return

	var body := {
		"model": _model,
		"messages": messages,
		"temperature": temperature,
		"max_tokens": max_tokens
	}

	var headers := [
		"Content-Type: application/json",
		"Authorization: Bearer " + _api_key
	]

	var json_body := JSON.stringify(body)
	print("ApiClient: generate url=%s body_len=%d" % [_base_url, json_body.length()])
	var err := _http.request(_base_url, headers, HTTPClient.METHOD_POST, json_body)
	print("ApiClient: request err=%d" % err)
	if err != OK:
		error_occurred.emit("HTTP request failed: " + error_string(err))

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("ApiClient: completed result=%d code=%d body_len=%d" % [result, code, body.size()])
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit("Request failed (result=%d)" % result)
		return

	if code == 429:
		var wait := randf_range(2.0, 5.0)
		get_tree().create_timer(wait).timeout.connect(func(): _retry_last())
		return

	if code < 200 or code >= 300:
		var body_text := body.get_string_from_utf8()
		error_occurred.emit("API error %d: %s" % [code, body_text.left(200)])
		return

	var json := JSON.new()
	var body_text := body.get_string_from_utf8()
	print("ApiClient: response body: %s" % body_text.left(500))
	if json.parse(body_text) != OK:
		print("ApiClient: JSON parse failed!")
		error_occurred.emit("Invalid JSON response")
		return

	var data: Dictionary = json.data
	var text := ""
	var usage := {}

	if data.has("choices") and data["choices"].size() > 0:
		var choice: Dictionary = data["choices"][0]
		if choice.has("message") and choice["message"].has("content"):
			text = choice["message"]["content"]

	if data.has("usage"):
		usage = data["usage"]

	print("ApiClient: emitting response_received text_len=%d" % text.length())
	response_received.emit(text, usage)

var _last_messages: Array = []
var _last_temp: float = 0.8
var _last_max_tokens: int = 2048

func generate_with_retry(messages: Array, temperature: float, max_tokens: int) -> void:
	_last_messages = messages
	_last_temp = temperature
	_last_max_tokens = max_tokens
	generate(messages, temperature, max_tokens)

func _retry_last() -> void:
	generate(_last_messages, _last_temp, _last_max_tokens)

# --- Streaming path ---

func generate_stream(messages: Array, temperature: float = 0.8, max_tokens: int = 2048) -> void:
	print("ApiClient: generate_stream base_url=%s model=%s" % [_base_url, _model])
	if _base_url.is_empty():
		print("ApiClient: ERROR - base URL is empty!")
		error_occurred.emit("API base URL not configured")
		return

	if _streaming:
		error_occurred.emit("Stream already in progress")
		return

	# Reset streaming state
	_stream_buffer = ""
	_stream_usage = {}
	_stream_response_buffer = PackedByteArray()
	_last_messages = messages
	_last_temp = temperature
	_last_max_tokens = max_tokens

	# Parse the base URL to extract host, port, path
	var url := _base_url
	var host: String = ""
	var port: int = 443
	var use_tls: bool = true
	var request_path: String = "/v1/chat/completions"

	# Strip scheme
	if url.begins_with("https://"):
		url = url.substr(8)
		use_tls = true
		port = 443
	elif url.begins_with("http://"):
		url = url.substr(7)
		use_tls = false
		port = 80

	# Split host from path
	var slash_pos := url.find("/")
	if slash_pos >= 0:
		host = url.substr(0, slash_pos)
		request_path = url.substr(slash_pos)
	else:
		host = url

	# Handle host:port
	var colon_pos := host.rfind(":")
	if colon_pos >= 0:
		port = host.substr(colon_pos + 1).to_int()
		host = host.substr(0, colon_pos)

	# Create and connect HTTPClient
	_stream_client = HTTPClient.new()
	var tls_options: TLSOptions = TLSOptions.client() if use_tls else null
	print("ApiClient: connecting to %s:%d tls=%s path=%s" % [host, port, use_tls, request_path])
	var err := _stream_client.connect_to_host(host, port, tls_options)
	if err != OK:
		print("ApiClient: connect failed error=%d" % err)
		error_occurred.emit("Failed to connect to %s:%d" % [host, port])
		_stream_client = null
		return

	_streaming = true

	# Build request body
	var body := {
		"model": _model,
		"messages": messages,
		"temperature": temperature,
		"max_tokens": max_tokens,
		"stream": true
	}
	var json_body := JSON.stringify(body)

	# Store request details for sending after connection established
	@warning_ignore("incompatible_ternary")
	var request_headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _api_key,
		"Content-Length: %d" % json_body.length()
	])
	# Store for deferred send
	_stream_request_path = request_path
	_stream_request_headers = request_headers
	_stream_request_body = json_body

# Deferred request state
var _stream_request_path: String = ""
var _stream_request_headers: PackedStringArray = PackedStringArray()
var _stream_request_body: String = ""
var _stream_request_sent: bool = false
var _last_stream_status: int = -1

func _process(_delta: float) -> void:
	if not _streaming or _stream_client == null:
		return

	_stream_client.poll()

	var status := _stream_client.get_status()

	if status != _last_stream_status:
		print("ApiClient: stream status changed to %d" % status)
		_last_stream_status = status

	match status:
		HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
			return  # Still connecting, wait

		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE:
			_end_stream()
			error_occurred.emit("Cannot connect to API server")
			return

		HTTPClient.STATUS_CONNECTED:
			if not _stream_request_sent:
				print("ApiClient: sending request, body length=%d" % _stream_request_body.length())
				var err := _stream_client.request(
					HTTPClient.METHOD_POST,
					_stream_request_path,
					_stream_request_headers,
					_stream_request_body
				)
				if err != OK:
					_end_stream()
					error_occurred.emit("Stream request failed: " + error_string(err))
					return
				_stream_request_sent = true

		HTTPClient.STATUS_REQUESTING:
			return  # Still sending request

		HTTPClient.STATUS_BODY:
			_read_stream_chunk()

		HTTPClient.STATUS_DISCONNECTED:
			_finalize_stream()
			return

		HTTPClient.STATUS_CONNECTION_ERROR:
			_end_stream()
			error_occurred.emit("Stream connection error")
			return

func _read_stream_chunk() -> void:
	var chunk := _stream_client.read_response_body_chunk()
	if chunk.size() > 0:
		_stream_response_buffer.append_array(chunk)
		_parse_sse_buffer()
		print("ApiClient: read chunk %d bytes, buffer %d bytes" % [chunk.size(), _stream_response_buffer.size()])

	if _stream_client.get_status() != HTTPClient.STATUS_BODY:
		# Stream ended
		print("ApiClient: stream ended, finalizing")
		_finalize_stream()

func _parse_sse_buffer() -> void:
	var text := _stream_response_buffer.get_string_from_utf8()

	# Process complete lines
	while true:
		var newline_pos := text.find("\n")
		if newline_pos < 0:
			break

		var line := text.substr(0, newline_pos).strip_edges()
		text = text.substr(newline_pos + 1)

		if line.is_empty():
			continue

		if line.begins_with("data: "):
			var data_str := line.substr(6).strip_edges()

			if data_str == "[DONE]":
				# Stream complete — signal will be emitted in _finalize_stream
				_stream_response_buffer = text.to_utf8_buffer()
				return

			var json := JSON.new()
			if json.parse(data_str) == OK:
				var data: Dictionary = json.data

				# Extract usage if present
				if data.has("usage"):
					_stream_usage = data["usage"]

				# Extract delta content
				if data.has("choices") and data["choices"].size() > 0:
					var choice: Dictionary = data["choices"][0]
					if choice.has("delta"):
						var delta: Dictionary = choice["delta"]
						if delta.has("content") and delta["content"] != null:
							var token: String = delta["content"]
							_stream_buffer += token
							stream_token.emit(token)

	# Store remaining incomplete data
	_stream_response_buffer = text.to_utf8_buffer()

func _finalize_stream() -> void:
	# Emit remaining tokens if any unprocessed data
	if _stream_response_buffer.size() > 0:
		var remaining := _stream_response_buffer.get_string_from_utf8()
		print("ApiClient: finalize, remaining buffer: %s" % remaining.left(500))
		_parse_sse_buffer()

	var full_text := _stream_buffer
	print("ApiClient: finalize, full_text length=%d" % full_text.length())
	var usage := _stream_usage
	stream_finished.emit(full_text, usage)
	response_received.emit(full_text, usage)
	_end_stream()

func _end_stream() -> void:
	_streaming = false
	_stream_client = null
	_stream_request_sent = false
	_stream_request_path = ""
	_stream_request_headers = PackedStringArray()
	_stream_request_body = ""

func cancel_stream() -> void:
	if _streaming and _stream_client:
		_stream_client.close()
	_end_stream()

func is_streaming() -> bool:
	return _streaming
