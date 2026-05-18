extends Control

var _sidebar: Control
var _chat_view: Control
var _input_bar: Control
var _status_bar: Control
var _state: Node
var _session_mgr: Node
var _react_loop: Node
var _current_messages: Array = []

func _ready() -> void:
	_state = Engine.get_singleton("AppState")
	_session_mgr = Engine.get_singleton("SessionManager")
	_react_loop = Engine.get_singleton("ReactLoop")

	# Root layout
	var h_box := HBoxContainer.new()
	h_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(h_box)

	# Sidebar
	_sidebar = load("res://ui/sidebar.tscn").instantiate()
	_sidebar.custom_minimum_size.x = 280
	_sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_box.add_child(_sidebar)

	# Separator
	var sep := VSeparator.new()
	sep.custom_minimum_size.x = 1
	h_box.add_child(sep)

	# Main area
	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_box.add_child(main_vbox)

	# Chat view
	_chat_view = load("res://ui/chat_view.tscn").instantiate()
	_chat_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_chat_view)

	# Status bar
	_status_bar = load("res://ui/status_bar.tscn").instantiate()
	_status_bar.custom_minimum_size.y = 32
	main_vbox.add_child(_status_bar)

	# Input bar
	_input_bar = load("res://ui/input_bar.tscn").instantiate()
	_input_bar.custom_minimum_size.y = 48
	main_vbox.add_child(_input_bar)

	# Connect signals
	_input_bar.message_sent.connect(_on_message_sent)
	_state.agent_busy.connect(_on_agent_busy)
	_state.session_changed.connect(_on_session_changed)

	# Connect react loop answer to save session
	_react_loop.answer_ready.connect(_on_answer_ready)

	# Load current session
	_load_session(_state.current_session)

func _on_message_sent(text: String) -> void:
	# Add user message to chat
	_chat_view.add_message("user", text)
	_current_messages.append({"role": "user", "content": text})

	_state.set_busy(true)
	_state.reset_tokens()

	# Run react loop
	_react_loop.run(text, _current_messages)

func _on_agent_busy(busy: bool) -> void:
	if not busy:
		# Agent finished — save session
		_save_session()

func _on_answer_ready(_text: String) -> void:
	# Update messages from react loop
	_current_messages = _react_loop.get_messages()
	_state.set_busy(false)

func _on_session_changed(session_name: String) -> void:
	_save_session()
	_load_session(session_name)

func _load_session(name: String) -> void:
	var data: Dictionary = _session_mgr.load_session(name)
	_current_messages = data.get("messages", [])
	_chat_view.clear()

	for msg in _current_messages:
		var role: String = msg.get("role", "")
		var content: String = msg.get("content", "")
		if role == "user":
			_chat_view.add_message("user", content)
		elif role == "assistant":
			_chat_view.add_message("assistant", content)

func _save_session() -> void:
	var data := {
		"name": _state.current_session,
		"messages": _current_messages,
		"steps": _state.get_step(),
		"total_tokens": 0,
		"tool_history": []
	}
	_session_mgr.save_session(_state.current_session, data)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed:
			if key_event.keycode == KEY_N and key_event.ctrl_pressed:
				_state.current_session = "session-%d" % Time.get_ticks_msec()
				_state.session_changed.emit(_state.current_session)
			elif key_event.keycode == KEY_S and key_event.ctrl_pressed:
				_save_session()
