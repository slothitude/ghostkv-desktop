extends HBoxContainer

var _model_label: Label
var _step_label: Label
var _token_label: Label
var _state: Node

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	_model_label = Label.new()
	_model_label.add_theme_font_size_override("font_size", 11)
	_model_label.add_theme_color_override("font_color", Color("#888899"))
	add_child(_model_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 11)
	_step_label.add_theme_color_override("font_color", Color("#888899"))
	_step_label.text = "Step: 0"
	add_child(_step_label)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer2)

	_token_label = Label.new()
	_token_label.add_theme_font_size_override("font_size", 11)
	_token_label.add_theme_color_override("font_color", Color("#888899"))
	_token_label.text = "Tokens: 0"
	add_child(_token_label)

	# Top separator
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 1
	add_child(sep)

	# Connect signals
	_state.token_count_updated.connect(_on_tokens)
	var session_mgr := Engine.get_singleton("SessionManager") as Node
	if session_mgr:
		session_mgr.settings_loaded.connect(_on_settings)

func _on_tokens(total: int) -> void:
	_token_label.text = "Tokens: %d" % total
	_step_label.text = "Step: %d" % _state.get_step()

func _on_settings(settings: Dictionary) -> void:
	_model_label.text = settings.get("model", "glm-5.1")
