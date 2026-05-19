extends HBoxContainer

signal message_sent(text: String)

var _input: LineEdit
var _send_btn: Button
var _stop_btn: Button
var _state: Node
var _is_streaming: bool = false

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	# Input field
	_input = LineEdit.new()
	_input.placeholder_text = "Ask GhostKV anything..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.clear_button_enabled = true
	_input.text_submitted.connect(_on_submit)
	_input.custom_minimum_size.y = 48
	_input.add_theme_color_override("font_color", Color("#ffffff"))
	_input.add_theme_color_override("font_placeholder_color", Color("#555570"))
	_input.add_theme_color_override("caret_color", Color("#6c63ff"))
	_input.add_theme_color_override("selection_color", Color("#6c63ff44"))
	var input_bg := StyleBoxFlat.new()
	input_bg.bg_color = Color("#1a1a28")
	input_bg.border_color = Color("#2a2a40")
	input_bg.border_width_bottom = 2
	input_bg.corner_radius_top_left = 10
	input_bg.corner_radius_top_right = 10
	input_bg.corner_radius_bottom_left = 10
	input_bg.corner_radius_bottom_right = 10
	input_bg.content_margin_left = 14
	input_bg.content_margin_top = 8
	input_bg.content_margin_bottom = 8
	_input.add_theme_stylebox_override("normal", input_bg)
	var input_focus := input_bg.duplicate()
	input_focus.border_color = Color("#6c63ff")
	input_focus.bg_color = Color("#1e1e36")
	_input.add_theme_stylebox_override("focused", input_focus)
	add_child(_input)

	# Send button
	_send_btn = Button.new()
	var send_icon := load("res://assets/icons/send.svg")
	if send_icon:
		_send_btn.icon = send_icon
	else:
		_send_btn.text = "Send"
	_send_btn.custom_minimum_size = Vector2(48, 48)
	_send_btn.tooltip_text = "Send message (Enter)"
	_send_btn.pressed.connect(_on_send_pressed)
	add_child(_send_btn)

	# Stop button (hidden by default)
	_stop_btn = Button.new()
	_stop_btn.text = "■"
	_stop_btn.tooltip_text = "Stop generation (Esc)"
	_stop_btn.custom_minimum_size = Vector2(48, 48)
	_stop_btn.add_theme_font_size_override("font_size", 16)
	_stop_btn.add_theme_color_override("font_color", Color("#ff5566"))
	_stop_btn.add_theme_color_override("font_hover_color", Color("#ff7788"))
	_stop_btn.visible = false
	var stop_bg := StyleBoxFlat.new()
	stop_bg.bg_color = Color("#2a1525")
	stop_bg.border_color = Color("#ff4466")
	stop_bg.border_width_bottom = 2
	stop_bg.corner_radius_top_left = 10
	stop_bg.corner_radius_top_right = 10
	stop_bg.corner_radius_bottom_left = 10
	stop_bg.corner_radius_bottom_right = 10
	_stop_btn.add_theme_stylebox_override("normal", stop_bg)
	_stop_btn.pressed.connect(_on_stop_pressed)
	add_child(_stop_btn)

	# Spacing
	add_theme_constant_override("separation", 8)

	# Connect busy state
	_state.agent_busy.connect(_on_busy_changed)

	# Connect streaming state from react loop
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop:
		react_loop.answer_streaming.connect(_on_streaming_token)
		react_loop.answer_ready.connect(_on_streaming_done)
		react_loop.loop_error.connect(_on_streaming_done)

func _on_submit(_text: String) -> void:
	_send()

func _on_send_pressed() -> void:
	_send()

func _send() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""
	message_sent.emit(text)

func _on_stop_pressed() -> void:
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop and react_loop.is_running():
		react_loop.stop()
	_state.set_busy(false)

func _on_busy_changed(busy: bool) -> void:
	_input.editable = not busy
	_send_btn.visible = not busy
	_stop_btn.visible = busy
	_stop_btn.disabled = false
	if busy:
		_input.placeholder_text = "GhostKV is thinking..."
		_is_streaming = false
	else:
		_input.placeholder_text = "Ask GhostKV anything..."
		_is_streaming = false

func _on_streaming_token(_token: String) -> void:
	if not _is_streaming:
		_is_streaming = true
		_input.placeholder_text = "GhostKV is responding..."

func _on_streaming_done(_text: String = "") -> void:
	_is_streaming = false
	if _state and _state.is_busy():
		_input.placeholder_text = "GhostKV is thinking..."
	else:
		_input.placeholder_text = "Ask GhostKV anything..."

func focus_input() -> void:
	_input.grab_focus()
