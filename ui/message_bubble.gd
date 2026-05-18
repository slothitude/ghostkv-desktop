extends PanelContainer

var _role: String = ""
var _rich_label: RichTextLabel
var _role_label: Label

func _ready() -> void:
	# Container layout
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Role label
	_role_label = Label.new()
	_role_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_role_label)

	# RichTextLabel for BBCode content
	_rich_label = RichTextLabel.new()
	_rich_label.bbcode_enabled = true
	_rich_label.fit_content = true
	_rich_label.scroll_following = true
	_rich_label.custom_minimum_size.y = 20
	_rich_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rich_label.add_theme_font_size_override("normal_font_size", 14)
	_rich_label.add_theme_color_override("default_color", Color("#e0e0e0"))
	vbox.add_child(_rich_label)

	# Padding
	add_theme_constant_override("margin_top", 8)
	add_theme_constant_override("margin_bottom", 8)
	add_theme_constant_override("margin_left", 12)
	add_theme_constant_override("margin_right", 12)

func setup(role: String, text: String) -> void:
	_role = role
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8

	match role:
		"user":
			style.bg_color = Color("#2a2a4a")
			_role_label.text = "You"
			_role_label.add_theme_color_override("font_color", Color("#8888cc"))
			var md := Engine.get_singleton("Markdown") as Node
			_rich_label.text = md.to_bbcode(text) if md else text
		"assistant":
			style.bg_color = Color("#1a1a2e")
			_role_label.text = "GhostKV"
			_role_label.add_theme_color_override("font_color", Color("#6c63ff"))
			_rich_label.text = text
		"assistant_thinking":
			style.bg_color = Color("#151525")
			_role_label.text = "GhostKV (thinking...)"
			_role_label.add_theme_color_override("font_color", Color("#555577"))
			_rich_label.text = text
		"error":
			style.bg_color = Color("#2a1520")
			_role_label.text = "Error"
			_role_label.add_theme_color_override("font_color", Color("#ff5555"))
			_rich_label.text = text
		_:
			style.bg_color = Color("#1a1a2e")
			_role_label.text = role
			_rich_label.text = text

	add_theme_stylebox_override("panel", style)

func update_text(bbcode: String) -> void:
	_role = "assistant"
	_role_label.text = "GhostKV"
	_role_label.add_theme_color_override("font_color", Color("#6c63ff"))
	_rich_label.text = bbcode
	var style := get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		style.bg_color = Color("#1a1a2e")
