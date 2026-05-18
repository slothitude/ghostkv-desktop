extends Node

signal response_received(text: String, usage: Dictionary)
signal error_occurred(msg: String)
signal stream_token(token: String)

var _http: HTTPRequest
var _base_url: String = ""
var _api_key: String = ""
var _model: String = "glm-5.1"

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func configure(base_url: String, api_key: String, model: String) -> void:
	_base_url = base_url
	_api_key = api_key
	_model = model

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
	var err := _http.request(_base_url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		error_occurred.emit("HTTP request failed: " + error_string(err))

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		error_occurred.emit("Request failed (result=%d)" % result)
		return

	if code == 429:
		# Retry with backoff
		var wait := randf_range(2.0, 5.0)
		get_tree().create_timer(wait).timeout.connect(func(): _retry_last())
		return

	if code < 200 or code >= 300:
		var body_text := body.get_string_from_utf8()
		error_occurred.emit("API error %d: %s" % [code, body_text.left(200)])
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
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
