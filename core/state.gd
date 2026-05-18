extends Node

signal session_changed(session_name: String)
signal tool_list_updated(tools: Array)
signal agent_busy(busy: bool)
signal token_count_updated(total: int)

var current_session: String = "default"
var available_tools: Array = []
var _busy: bool = false
var _total_tokens: int = 0
var _step: int = 0

var api_client: Node = null
var react_loop: Node = null

func set_busy(val: bool) -> void:
	_busy = val
	agent_busy.emit(val)

func is_busy() -> bool:
	return _busy

func add_tokens(n: int) -> void:
	_total_tokens += n
	token_count_updated.emit(_total_tokens)

func reset_tokens() -> void:
	_total_tokens = 0
	token_count_updated.emit(0)

func set_step(s: int) -> void:
	_step = s

func get_step() -> int:
	return _step
