extends PanelContainer

signal retry_requested()
signal copy_requested(text: String)

var _role: String = ""
var _rich_label: RichTextLabel
var _role_label: Label
var _raw_buffer: String = ""
var _action_row: HBoxContainer
var _retry_btn: Button
var _copy_btn: Button

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Role label — small, muted
	_role_label = Label.new()
	_role_label.add_theme_font_size_override("font_size", 10)
	_role_label.add_theme_color_override("font_color", Color("#6b6b80"))
	vbox.add_child(_role_label)

	# RichTextLabel for BBCode content
	_rich_label = RichTextLabel.new()
	_rich_label.bbcode_enabled = true
	_rich_label.fit_content = true
	_rich_label.scroll_following = false
	_rich_label.custom_minimum_size = Vector2(0, 24)
	_rich_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rich_label.add_theme_font_size_override("normal_font_size", 13)
	_rich_label.add_theme_color_override("default_color", Color("#e8e8f0"))
	_rich_label.add_theme_constant_override("line_separation", 3)
	# Code block styling
	_rich_label.add_theme_color_override("code_color", Color("#c8d0e0"))
	vbox.add_child(_rich_label)

	# Action row (retry/copy — hidden by default)
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 6)
	_action_row.visible = false
	vbox.add_child(_action_row)

	# Retry button (errors only)
	_retry_btn = Button.new()
	_retry_btn.text = "Retry"
	_retry_btn.add_theme_font_size_override("font_size", 11)
	_retry_btn.custom_minimum_size = Vector2(64, 28)
	_retry_btn.tooltip_text = "Retry this request"
	var retry_bg := StyleBoxFlat.new()
	retry_bg.bg_color = Color("#3a2040")
	retry_bg.border_color = Color("#ff4466")
	retry_bg.border_width_bottom = 1
	retry_bg.corner_radius_top_left = 4
	retry_bg.corner_radius_bottom_left = 4
	retry_bg.corner_radius_top_right = 4
	retry_bg.corner_radius_bottom_right = 4
	_retry_btn.add_theme_stylebox_override("normal", retry_bg)
	_retry_btn.add_theme_color_override("font_color", Color("#ff8899"))
	_retry_btn.add_theme_color_override("font_hover_color", Color("#ffaabb"))
	_retry_btn.pressed.connect(_on_retry)
	_retry_btn.visible = false
	_action_row.add_child(_retry_btn)

	# Copy button (all assistant messages)
	_copy_btn = Button.new()
	_copy_btn.text = "Copy"
	_copy_btn.add_theme_font_size_override("font_size", 11)
	_copy_btn.custom_minimum_size = Vector2(64, 28)
	_copy_btn.tooltip_text = "Copy message text"
	var copy_bg := StyleBoxFlat.new()
	copy_bg.bg_color = Color("#1a1a30")
	copy_bg.border_color = Color("#3a3a55")
	copy_bg.border_width_bottom = 1
	copy_bg.corner_radius_top_left = 4
	copy_bg.corner_radius_bottom_left = 4
	copy_bg.corner_radius_top_right = 4
	copy_bg.corner_radius_bottom_right = 4
	_copy_btn.add_theme_stylebox_override("normal", copy_bg)
	_copy_btn.add_theme_color_override("font_color", Color("#8888aa"))
	_copy_btn.add_theme_color_override("font_hover_color", Color("#aaaacc"))
	_copy_btn.pressed.connect(_on_copy)
	_copy_btn.visible = false
	_action_row.add_child(_copy_btn)

	# Padding (compact)
	add_theme_constant_override("margin_top", 6)
	add_theme_constant_override("margin_bottom", 6)
	add_theme_constant_override("margin_left", 12)
	add_theme_constant_override("margin_right", 12)

func setup(role: String, text: String) -> void:
	_role = role
	_raw_buffer = text
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8

	match role:
		"user":
			style.bg_color = Color("#2a2a50")
			style.border_color = Color("#3a3a66")
			style.border_width_bottom = 1
			_role_label.text = "You"
			_role_label.add_theme_color_override("font_color", Color("#8888cc"))
			_rich_label.add_theme_color_override("default_color", Color("#ffffff"))
		"assistant":
			style.bg_color = Color("#16162a")
			style.border_color = Color("#2a2a44")
			style.border_width_left = 2
			_role_label.text = "GhostKV"
			_role_label.add_theme_color_override("font_color", Color("#6c63ff"))
			_rich_label.add_theme_color_override("default_color", Color("#d8d8f0"))
			_copy_btn.visible = true
			_action_row.visible = true
		"assistant_streaming":
			style.bg_color = Color("#12122a")
			style.border_color = Color("#222244")
			style.border_width_left = 2
			_role_label.text = "GhostKV"
			_role_label.add_theme_color_override("font_color", Color("#5050aa"))
			_rich_label.add_theme_color_override("default_color", Color("#9999bb"))
		"assistant_thinking":
			style.bg_color = Color("#12122a")
			style.border_color = Color("#222244")
			style.border_width_left = 2
			_role_label.text = "GhostKV (thinking...)"
			_role_label.add_theme_color_override("font_color", Color("#444466"))
			_rich_label.add_theme_color_override("default_color", Color("#777799"))
		"error":
			style.bg_color = Color("#2a1525")
			style.border_color = Color("#ff4466")
			style.border_width_left = 2
			var time_str := Time.get_datetime_string_from_system()
			_role_label.text = "Error — " + time_str
			_role_label.add_theme_color_override("font_color", Color("#ff4466"))
			_rich_label.add_theme_color_override("default_color", Color("#ff8899"))
			_retry_btn.visible = true
			_copy_btn.visible = true
			_action_row.visible = true
			# Parse error type for structured display
			_rich_label.clear()
			_rich_label.append_text(_format_error(text))
		_:
			style.bg_color = Color("#16162a")
			_role_label.text = role
			_rich_label.add_theme_color_override("default_color", Color("#e8e8f0"))

	_rich_label.clear()
	_rich_label.append_text(text)
	add_theme_stylebox_override("panel", style)

func update_text(bbcode: String) -> void:
	_role = "assistant"
	_raw_buffer = bbcode
	_role_label.text = "GhostKV"
	_role_label.add_theme_color_override("font_color", Color("#6c63ff"))
	_rich_label.add_theme_color_override("default_color", Color("#d8d8f0"))
	_rich_label.clear()
	_rich_label.append_text(bbcode)
	var style := get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.bg_color = Color("#16162a")
		style.border_color = Color("#2a2a44")
		style.border_width_left = 2

func append_token(token: String) -> void:
	_raw_buffer += token
	_rich_label.append_text(token)

func finalize_stream(full_text: String) -> void:
	_raw_buffer = full_text
	var md := Engine.get_singleton("Markdown") as Node
	var bbcode: String = md.to_bbcode(full_text)

	_role = "assistant"
	_role_label.text = "GhostKV"
	_role_label.add_theme_color_override("font_color", Color("#6c63ff"))
	_rich_label.add_theme_color_override("default_color", Color("#d8d8f0"))

	_rich_label.clear()
	_rich_label.append_text(bbcode)

	# Show copy button now that stream is done
	_copy_btn.visible = true
	_action_row.visible = true

	var style := get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.bg_color = Color("#16162a")
		style.border_color = Color("#2a2a44")
		style.border_width_left = 2

func _on_retry() -> void:
	retry_requested.emit()

func _on_copy() -> void:
	DisplayServer.clipboard_set(_raw_buffer)
	_copy_btn.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	_copy_btn.text = "Copy"

func _format_error(text: String) -> String:
	# Detect error type and build structured BBCode
	var error_type := "Unknown"
	var error_detail := text

	# API errors: "API error 429: ..." or "API error 401: ..."
	var api_regex := RegEx.new()
	api_regex.compile("API error (\\d+): (.*)")
	var api_match := api_regex.search(text)
	if api_match:
		var code: int = int(api_match.get_string(1))
		error_detail = api_match.get_string(2)
		match code:
			401: error_type = "Authentication Failed"
			403: error_type = "Access Denied"
			404: error_type = "Not Found"
			429: error_type = "Rate Limited"
			500: error_type = "Server Error"
			502: error_type = "Bad Gateway"
			503: error_type = "Service Unavailable"
			_: error_type = "API Error (%d)" % code
	elif text.begins_with("Request failed"):
		error_type = "Network Error"
	elif text.begins_with("Cannot connect"):
		error_type = "Connection Failed"
	elif text.begins_with("Stream"):
		error_type = "Stream Error"
	elif text.begins_with("HTTP request failed"):
		error_type = "Request Error"
	elif text.find("timeout") >= 0:
		error_type = "Timeout"

	var bbcode := "[b][color=#ff4466]%s[/color][/b]\n%s" % [error_type, error_detail]

	# Add actionable hint
	match error_type:
		"Authentication Failed":
			bbcode += "\n\n[color=#555570]Check your API key in Settings.[/color]"
		"Rate Limited":
			bbcode += "\n\n[color=#555570]Wait a moment and retry. The app will auto-retry on 429.[/color]"
		"Network Error", "Connection Failed":
			bbcode += "\n\n[color=#555570]Check your internet connection and API base URL.[/color]"
		"Server Error", "Bad Gateway", "Service Unavailable":
			bbcode += "\n\n[color=#555570]The API server may be down. Try again later.[/color]"

	return bbcode
