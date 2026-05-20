extends Node

signal thought_generated(text: String)
signal tool_called(name: String, args: String)
signal tool_result(name: String, result: String)
signal answer_ready(text: String)
signal answer_streaming(token: String)
signal step_completed(step: int, tokens: int)
signal loop_error(msg: String)

const MAX_RETRIES := 3

var _api_client: Node = null
var _tool_dispatch: Node = null
var _max_steps: int = 10
var _step: int = 0
var _messages: Array = []
var _temperature: float = 0.8
var _max_tokens: int = 2048
var _system_prompt: String = ""
var _running: bool = false

var _action_regex: RegEx
var _tool_call_regex: RegEx
var _reasoning_tool_regex: RegEx

# Streaming accumulation
var _stream_text_buffer: String = ""
var _stream_connected: bool = false

func _ready() -> void:
	_action_regex = RegEx.new()
	_action_regex.compile("Action:\\s*(\\w+)\\((.*)\\)")
	_tool_call_regex = RegEx.new()
	_tool_call_regex.compile("<tool_call[^>]*>\\s*(\\w+)\\((.*?)\\)\\s*</tool_call\\s*>")
	# Fallback: catch "use the get_battery tool" or "I'll use get_location" from reasoning
	_reasoning_tool_regex = RegEx.new()
	_reasoning_tool_regex.compile("(?:use|using|call|invoke)\\s+(?:the\\s+)?(\\w+)\\s+tool")

func configure(api_client: Node, tool_dispatch: Node, max_steps: int, temperature: float, max_tokens: int, system_prompt: String) -> void:
	_api_client = api_client
	_tool_dispatch = tool_dispatch
	_max_steps = max_steps
	_temperature = temperature
	_max_tokens = max_tokens
	_system_prompt = system_prompt

func run(question: String, history: Array = []) -> void:
	if _running:
		return
	_running = true
	_step = 0

	_messages = history.duplicate(true)
	_messages.append({"role": "user", "content": question})

	# Build system prompt with tool descriptions
	var full_prompt := _system_prompt
	if _tool_dispatch and _tool_dispatch.has_method("build_tool_descriptions"):
		var tool_desc: String = _tool_dispatch.build_tool_descriptions()
		if not tool_desc.is_empty():
			full_prompt += "\n\nAvailable tools:\n" + tool_desc
			print("ReactLoop: injected %d tool descriptions into system prompt" % tool_desc.split("\n").size())

	# Inject memory context (auto-recall)
	var memory_store := Engine.get_singleton("MemoryStore") as Node
	if memory_store and memory_store.has_method("auto_recall"):
		var mem_ctx: String = memory_store.auto_recall(question)
		if not mem_ctx.is_empty():
			full_prompt += "\n\n" + mem_ctx

	# Remove any existing system message and insert fresh one
	for i in range(_messages.size() - 1, -1, -1):
		if _messages[i].get("role", "") == "system":
			_messages.remove_at(i)
	if full_prompt != "":
		_messages.insert(0, {"role": "system", "content": full_prompt})

	_do_step()

func _do_step() -> void:
	_step += 1
	print("ReactLoop: _do_step #%d, api_client=%s" % [_step, _api_client])
	if _step > _max_steps:
		answer_ready.emit("Reached maximum steps (%d) without a final answer." % _max_steps)
		_running = false
		return

	# Reset stream buffer for this step
	_stream_text_buffer = ""
	_stream_connected = false

	# Pass tool definitions for structured function calling
	if _tool_dispatch and _tool_dispatch.has_method("build_openai_tools"):
		var tools: Array = _tool_dispatch.build_openai_tools()
		if tools.size() > 0:
			_api_client.set_tool_definitions(tools)

	# Connect signals
	_api_client.response_received.connect(_on_response)
	_api_client.error_occurred.connect(_on_error)
	_api_client.stream_token.connect(_on_stream_token)
	_api_client.stream_started.connect(_on_stream_started)

	# Use non-streaming path (streaming has body truncation bug on Android)
	_api_client.generate_with_retry(_messages, _temperature, _max_tokens)

func _on_stream_started() -> void:
	_stream_connected = true

func _on_stream_token(token: String) -> void:
	_stream_text_buffer += token
	answer_streaming.emit(token)

func _on_response(text: String, usage: Dictionary) -> void:
	print("ReactLoop: _on_response text_len=%d" % text.length())
	_disconnect_signals()

	var total_tokens: int = usage.get("total_tokens", 0)
	var state := Engine.get_singleton("AppState") as Node
	if state:
		state.add_tokens(total_tokens)
		state.set_step(_step)
	step_completed.emit(_step, total_tokens)

	# Use the accumulated stream buffer (or fallback to text if non-streaming somehow)
	var response_text := text
	if _stream_text_buffer.length() > 0:
		response_text = _stream_text_buffer

	# Check for Action: format or GLM <tool_call/> format
	var action_match := _action_regex.search(response_text)
	var tool_name: String = ""
	var args_str: String = ""

	if action_match:
		tool_name = action_match.get_string(1)
		args_str = action_match.get_string(2)
	else:
		# Try GLM-5.1 native tool call format
		action_match = _tool_call_regex.search(response_text)
		if action_match:
			tool_name = action_match.get_string(1)
			args_str = action_match.get_string(2)
		else:
			# Fallback: extract tool name from reasoning ("I'll use the get_battery tool")
			var reasoning_match := _reasoning_tool_regex.search(response_text)
			if reasoning_match:
				tool_name = reasoning_match.get_string(1)
				args_str = ""
				print("ReactLoop: extracted tool '%s' from reasoning" % tool_name)

	if tool_name != "":

		thought_generated.emit(response_text)
		tool_called.emit(tool_name, args_str)

		# Dispatch tool
		var result := ""
		if _tool_dispatch:
			result = await _tool_dispatch.dispatch(tool_name, args_str)
		else:
			result = "Error: No tool dispatcher configured"

		tool_result.emit(tool_name, result)

		# Add assistant thought and observation to messages
		_messages.append({"role": "assistant", "content": response_text})
		_messages.append({"role": "user", "content": "Observation: " + result})

		# Continue loop
		_do_step()
	else:
		# No action — this is the final answer
		_messages.append({"role": "assistant", "content": response_text})
		answer_ready.emit(response_text)
		_running = false

func _on_error(msg: String) -> void:
	print("ReactLoop: ERROR - %s" % msg)
	_disconnect_signals()

	# If we got partial stream, show it
	if _stream_text_buffer.length() > 0:
		answer_ready.emit(_stream_text_buffer + "\n\n[Stream interrupted: %s]" % msg)
	else:
		loop_error.emit(msg)
	_running = false

func _disconnect_signals() -> void:
	if _api_client.response_received.is_connected(_on_response):
		_api_client.response_received.disconnect(_on_response)
	if _api_client.error_occurred.is_connected(_on_error):
		_api_client.error_occurred.disconnect(_on_error)
	if _api_client.stream_token.is_connected(_on_stream_token):
		_api_client.stream_token.disconnect(_on_stream_token)
	if _api_client.stream_started.is_connected(_on_stream_started):
		_api_client.stream_started.disconnect(_on_stream_started)

func is_running() -> bool:
	return _running

func get_messages() -> Array:
	return _messages

func stop() -> void:
	if _api_client and _api_client.has_method("cancel_stream"):
		_api_client.cancel_stream()
	_disconnect_signals()
	_running = false
