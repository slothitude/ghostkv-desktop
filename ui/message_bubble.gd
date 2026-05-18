extends PanelContainer

var _role: String = ""
var _rich_label: RichTextLabel
var _role_label: Label

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Role label — small, muted
	_role_label = Label.new()
	_role_label.add_theme_font_size_override("font_size", 11)
	_role_label.add_theme_color_override("font_color", Color("#6b6b80"))
	vbox.add_child(_role_label)

	# RichTextLabel for BBCode content
	_rich_label = RichTextLabel.new()
	_rich_label.bbcode_enabled = true
	_rich_label.fit_content = true
	_rich_label.scroll_following = false
	_rich_label.custom_minimum_size = Vector2(0, 24)
	_rich_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rich_label.add_theme_font_size_override("normal_font_size", 14)
	_rich_label.add_theme_color_override("default_color", Color("#e8e8f0"))
	_rich_label.add_theme_constant_override("line_separation", 3)
	vbox.add_child(_rich_label)

	# Padding
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)
	add_theme_constant_override("margin_left", 16)
	add_theme_constant_override("margin_right", 16)

func setup(role: String, text: String) -> void:
	_role = role
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)

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
			_role_label.text = "Error"
			_role_label.add_theme_color_override("font_color", Color("#ff4466"))
			_rich_label.add_theme_color_override("default_color", Color("#ff8899"))
		_:
			style.bg_color = Color("#16162a")
			_role_label.text = role
			_rich_label.add_theme_color_override("default_color", Color("#e8e8f0"))

	# Render text via BBCode
	_rich_label.clear()
	_rich_label.append_text(text)
	add_theme_stylebox_override("panel", style)

func update_text(bbcode: String) -> void:
	_role = "assistant"
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
