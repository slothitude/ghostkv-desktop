extends HBoxContainer

signal message_sent(text: String)

var _input: LineEdit
var _send_btn: Button
var _state: Node

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	# Input field
	_input = LineEdit.new()
	_input.placeholder_text = "Ask GhostKV anything..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.clear_button_enabled = true
	_input.text_submitted.connect(_on_submit)
	_input.custom_minimum_size.y = 44
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
	_send_btn.custom_minimum_size = Vector2(44, 44)
	_send_btn.tooltip_text = "Send message"
	_send_btn.pressed.connect(_on_send_pressed)
	add_child(_send_btn)

	# Spacing
	add_theme_constant_override("separation", 8)

	# Connect busy state
	_state.agent_busy.connect(_on_busy_changed)

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

func _on_busy_changed(busy: bool) -> void:
	_input.editable = not busy
	_send_btn.disabled = busy
	if busy:
		_input.placeholder_text = "GhostKV is thinking..."
	else:
		_input.placeholder_text = "Ask GhostKV anything..."
