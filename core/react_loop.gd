extends Node

signal thought_generated(text: String)
signal tool_called(name: String, args: String)
signal tool_result(name: String, result: String)
signal answer_ready(text: String)
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

func _ready() -> void:
	_action_regex = RegEx.new()
	_action_regex.compile("Action:\\s*(\\w+)\\((.*)\\)")

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

	# Add system prompt if not already present
	var has_system := false
	for msg in _messages:
		if msg.get("role", "") == "system":
			has_system = true
			break
	if not has_system and _system_prompt != "":
		_messages.insert(0, {"role": "system", "content": _system_prompt})

	_do_step()

func _do_step() -> void:
	_step += 1
	if _step > _max_steps:
		answer_ready.emit("Reached maximum steps (%d) without a final answer." % _max_steps)
		_running = false
		return

	_api_client.response_received.disconnect(_on_response)
	_api_client.response_received.connect(_on_response)
	_api_client.error_occurred.disconnect(_on_error)
	_api_client.error_occurred.connect(_on_error)
	_api_client.generate_with_retry(_messages, _temperature, _max_tokens)

func _on_response(text: String, usage: Dictionary) -> void:
	_api_client.response_received.disconnect(_on_response)
	_api_client.error_occurred.disconnect(_on_error)

	var total_tokens: int = usage.get("total_tokens", 0)
	var state := Engine.get_singleton("AppState") as Node
	if state:
		state.add_tokens(total_tokens)
		state.set_step(_step)
	step_completed.emit(_step, total_tokens)

	# Check for Action: in response
	var action_match := _action_regex.search(text)
	if action_match:
		var tool_name: String = action_match.get_string(1)
		var args_str: String = action_match.get_string(2)

		thought_generated.emit(text)
		tool_called.emit(tool_name, args_str)

		# Dispatch tool
		var result := ""
		if _tool_dispatch:
			result = await _tool_dispatch.dispatch(tool_name, args_str)
		else:
			result = "Error: No tool dispatcher configured"

		tool_result.emit(tool_name, result)

		# Add assistant thought and observation to messages
		_messages.append({"role": "assistant", "content": text})
		_messages.append({"role": "user", "content": "Observation: " + result})

		# Continue loop
		_do_step()
	else:
		# No action — this is the final answer
		_messages.append({"role": "assistant", "content": text})
		answer_ready.emit(text)
		_running = false

func _on_error(msg: String) -> void:
	_api_client.response_received.disconnect(_on_response)
	_api_client.error_occurred.disconnect(_on_error)
	loop_error.emit(msg)
	_running = false

func is_running() -> bool:
	return _running

func get_messages() -> Array:
	return _messages

func stop() -> void:
	_running = false
