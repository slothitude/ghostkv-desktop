extends ScrollContainer

var _vbox: VBoxContainer
var _state: Node
var _streaming_bubble: Control = null
var _thinking_bubble: Control = null
var _thinking_timer: Timer
var _thinking_dots: int = 0
var _last_user_text: String = ""

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 12)
	add_child(_vbox)

	# Thinking animation timer
	_thinking_timer = Timer.new()
	_thinking_timer.wait_time = 0.5
	_thinking_timer.one_shot = false
	_thinking_timer.timeout.connect(_animate_thinking)
	add_child(_thinking_timer)

	# Connect react loop signals
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop:
		react_loop.thought_generated.connect(_on_thought)
		react_loop.tool_called.connect(_on_tool_called)
		react_loop.tool_result.connect(_on_tool_result)
		react_loop.answer_ready.connect(_on_answer)
		react_loop.answer_streaming.connect(_on_answer_streaming)
		react_loop.loop_error.connect(_on_error)

	# Connect busy state for spinner lifecycle
	_state.agent_busy.connect(_on_busy_changed)

func add_message(role: String, text: String) -> Control:
	var bubble: Control = load("res://ui/message_bubble.tscn").instantiate()
	_vbox.add_child(bubble)
	bubble.setup(role, text)
	# Connect retry signal for error bubbles
	if role == "error" and bubble.has_signal("retry_requested"):
		bubble.retry_requested.connect(_on_retry)
	await get_tree().process_frame
	scroll_vertical = get_v_scroll_bar().max_value
	return bubble

func add_tool_card(step: int, tool_name: String, args: String) -> Node:
	var card: Control = load("res://ui/tool_card.tscn").instantiate()
	_vbox.add_child(card)
	card.setup(step, tool_name, args)
	await get_tree().process_frame
	scroll_vertical = get_v_scroll_bar().max_value
	return card

func clear() -> void:
	_streaming_bubble = null
	_thinking_bubble = null
	_thinking_timer.stop()
	for child in _vbox.get_children():
		child.queue_free()

func clear_chat() -> void:
	clear()
	_last_user_text = ""

func _on_busy_changed(busy: bool) -> void:
	if busy:
		_show_thinking()
	else:
		_hide_thinking()

func _show_thinking() -> void:
	if _thinking_bubble != null:
		return
	_thinking_bubble = load("res://ui/message_bubble.tscn").instantiate()
	_vbox.add_child(_thinking_bubble)
	_thinking_bubble.setup("assistant_thinking", "")
	_thinking_dots = 0
	_thinking_timer.start()

func _hide_thinking() -> void:
	_thinking_timer.stop()
	if _thinking_bubble != null:
		_thinking_bubble.queue_free()
		_thinking_bubble = null

func _animate_thinking() -> void:
	if _thinking_bubble == null or not _thinking_bubble.is_inside_tree():
		_thinking_timer.stop()
		return
	_thinking_dots = (_thinking_dots + 1) % 4
	var dots := ".".repeat(_thinking_dots + 1)
	_thinking_bubble.call("update_text", "GhostKV is thinking" + dots)

func _on_thought(text: String) -> void:
	# Remove thinking bubble, show the actual thought
	_hide_thinking()
	add_message("assistant_thinking", text)

func _on_tool_called(name: String, args: String) -> void:
	_hide_thinking()
	var state := Engine.get_singleton("AppState") as Node
	add_tool_card(state.get_step(), name, args)

func _on_tool_result(name: String, result: String) -> void:
	var children := _vbox.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child := children[i]
		if child.has_method("set_result"):
			child.set_result(result)
			break

func _on_answer_streaming(token: String) -> void:
	# First token arrives — hide thinking spinner, show streaming bubble
	_hide_thinking()

	if _streaming_bubble == null:
		_streaming_bubble = load("res://ui/message_bubble.tscn").instantiate()
		_vbox.add_child(_streaming_bubble)
		_streaming_bubble.setup("assistant_streaming", "")

	_streaming_bubble.append_token(token)

	await get_tree().process_frame
	scroll_vertical = get_v_scroll_bar().max_value

func _on_answer(text: String) -> void:
	_hide_thinking()

	if _streaming_bubble != null:
		_streaming_bubble.finalize_stream(text)
		_streaming_bubble = null
	else:
		var md := Engine.get_singleton("Markdown") as Node
		var bbcode: String = md.to_bbcode(text)
		var children := _vbox.get_children()
		if children.size() > 0:
			var last := children[children.size() - 1]
			if last.has_method("update_text"):
				last.update_text(bbcode)
			else:
				add_message("assistant", text)
		else:
			add_message("assistant", text)

	await get_tree().process_frame
	scroll_vertical = get_v_scroll_bar().max_value

func _on_error(msg: String) -> void:
	_hide_thinking()
	_streaming_bubble = null
	add_message("error", msg)

func set_last_user_text(text: String) -> void:
	_last_user_text = text

func _on_retry() -> void:
	if _last_user_text.is_empty():
		return
	# Re-emit through app — find the App node
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	var state := Engine.get_singleton("AppState") as Node
	if react_loop and state:
		state.set_busy(true)
		state.reset_tokens()
		react_loop.run(_last_user_text)
