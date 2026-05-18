extends VBoxContainer

var _base_url_input: LineEdit
var _api_key_input: LineEdit
var _model_input: LineEdit
var _temp_spin: SpinBox
var _max_tokens_spin: SpinBox
var _max_steps_spin: SpinBox
var _system_prompt_edit: TextEdit
var _session_mgr: Node

func _ready() -> void:
	_session_mgr = Engine.get_singleton("SessionManager")

	add_theme_constant_override("separation", 6)

	# API Base URL
	_add_label("API Base URL")
	_base_url_input = _add_line_edit("https://api.z.ai/api/coding/paas/v4/chat/completions")

	# API Key
	_add_label("API Key")
	_api_key_input = _add_line_edit("")
	_api_key_input.secret = true

	# Model
	_add_label("Model")
	_model_input = _add_line_edit("glm-5.1")

	# Temperature
	_add_label("Temperature")
	_temp_spin = SpinBox.new()
	_temp_spin.min_value = 0.0
	_temp_spin.max_value = 2.0
	_temp_spin.step = 0.1
	_temp_spin.value = 0.8
	_temp_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_temp_spin)

	# Max Tokens
	_add_label("Max Tokens")
	_max_tokens_spin = SpinBox.new()
	_max_tokens_spin.min_value = 256
	_max_tokens_spin.max_value = 32768
	_max_tokens_spin.step = 256
	_max_tokens_spin.value = 2048
	_max_tokens_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_max_tokens_spin)

	# Max Steps
	_add_label("Max Steps")
	_max_steps_spin = SpinBox.new()
	_max_steps_spin.min_value = 1
	_max_steps_spin.max_value = 50
	_max_steps_spin.step = 1
	_max_steps_spin.value = 10
	_max_steps_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_max_steps_spin)

	# System Prompt
	_add_label("System Prompt")
	_system_prompt_edit = TextEdit.new()
	_system_prompt_edit.custom_minimum_size = Vector2(0, 100)
	_system_prompt_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_system_prompt_edit)

	# Save button
	var save_btn := Button.new()
	save_btn.text = "Save Settings"
	save_btn.pressed.connect(_on_save)
	add_child(save_btn)

	# Load existing settings
	_session_mgr.settings_loaded.connect(_on_settings_loaded)

func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("#888899"))
	add_child(label)

func _add_line_edit(placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(le)
	return le

func _on_settings_loaded(settings: Dictionary) -> void:
	_base_url_input.text = settings.get("api_base_url", "")
	_api_key_input.text = settings.get("api_key", "")
	_model_input.text = settings.get("model", "glm-5.1")
	_temp_spin.value = settings.get("temperature", 0.8)
	_max_tokens_spin.value = settings.get("max_tokens", 2048)
	_max_steps_spin.value = settings.get("max_steps", 10)
	_system_prompt_edit.text = settings.get("system_prompt", "")

func _on_save() -> void:
	var settings := {
		"api_base_url": _base_url_input.text,
		"api_key": _api_key_input.text,
		"model": _model_input.text,
		"temperature": _temp_spin.value,
		"max_tokens": int(_max_tokens_spin.value),
		"max_steps": int(_max_steps_spin.value),
		"system_prompt": _system_prompt_edit.text,
		"mcp_servers": []
	}

	# Preserve existing MCP servers
	if _session_mgr:
		var existing: Dictionary = _session_mgr.load_settings()
		if existing.has("mcp_servers"):
			settings["mcp_servers"] = existing["mcp_servers"]

	_session_mgr.save_settings(settings)

	# Reconfigure API client and react loop
	var api_client := Engine.get_singleton("ApiClient") as Node
	if api_client:
		api_client.configure(
			settings["api_base_url"],
			settings["api_key"],
			settings["model"]
		)

	var react_loop := Engine.get_singleton("ReactLoop") as Node
	var tool_dispatch := Engine.get_singleton("ToolDispatch") as Node
	if react_loop:
		react_loop.configure(
			api_client,
			tool_dispatch,
			int(_max_steps_spin.value),
			_temp_spin.value,
			int(_max_tokens_spin.value),
			_system_prompt_edit.text
		)
