extends ScrollContainer

var _vbox: VBoxContainer
var _state: Node

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 12)
	add_child(_vbox)

	# Connect react loop signals
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop:
		react_loop.thought_generated.connect(_on_thought)
		react_loop.tool_called.connect(_on_tool_called)
		react_loop.tool_result.connect(_on_tool_result)
		react_loop.answer_ready.connect(_on_answer)
		react_loop.loop_error.connect(_on_error)

func add_message(role: String, text: String) -> void:
	var bubble: Control = load("res://ui/message_bubble.tscn").instantiate()
	bubble.setup(role, text)
	_vbox.add_child(bubble)
	await get_tree().process_frame
	scroll_vertical = get_v_scroll_bar().max_value

func add_tool_card(step: int, tool_name: String, args: String) -> Node:
	var card: Control = load("res://ui/tool_card.tscn").instantiate()
	card.setup(step, tool_name, args)
	_vbox.add_child(card)
	await get_tree().process_frame
	scroll_vertical = get_v_scroll_bar().max_value
	return card

func clear() -> void:
	for child in _vbox.get_children():
		child.queue_free()

func _on_thought(text: String) -> void:
	# Show thinking indicator
	add_message("assistant_thinking", text)

func _on_tool_called(name: String, args: String) -> void:
	var state := Engine.get_singleton("AppState") as Node
	add_tool_card(state.get_step(), name, args)

func _on_tool_result(name: String, result: String) -> void:
	# Update last tool card with result
	var children := _vbox.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child := children[i]
		if child.has_method("set_result"):
			child.set_result(result)
			break

func _on_answer(text: String) -> void:
	var md := Engine.get_singleton("Markdown") as Node
	var bbcode: String = md.to_bbcode(text)
	# Replace last thinking bubble with final answer
	var children := _vbox.get_children()
	if children.size() > 0:
		var last := children[children.size() - 1]
		if last.has_method("update_text"):
			last.update_text(bbcode)
		else:
			add_message("assistant", text)
	else:
		add_message("assistant", text)

func _on_error(msg: String) -> void:
	add_message("error", msg)
