extends HBoxContainer

signal message_sent(text: String)

var _input: LineEdit
var _send_btn: Button
var _state: Node

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	_input = LineEdit.new()
	_input.placeholder_text = "Ask GhostKV..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.clear_button_enabled = true
	_input.text_submitted.connect(_on_submit)
	add_child(_input)

	_send_btn = Button.new()
	_send_btn.text = "Send"
	_send_btn.custom_minimum_size = Vector2(80, 36)
	_send_btn.pressed.connect(_on_send_pressed)
	add_child(_send_btn)

	# Top separator
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
