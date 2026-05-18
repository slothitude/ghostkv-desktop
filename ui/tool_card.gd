extends PanelContainer

var _header: HBoxContainer
var _body: VBoxContainer
var _result_label: RichTextLabel
var _expanded: bool = false
var _step: int = 0
var _tool_name: String = ""
var _args: String = ""
var _expand_btn: Button

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Header row
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	vbox.add_child(_header)

	# Tool icon indicator (colored dot using a Label)
	var dot := Label.new()
	dot.text = ">"
	dot.add_theme_color_override("font_color", Color("#6c63ff"))
	dot.add_theme_font_size_override("font_size", 16)
	dot.custom_minimum_size.x = 16
	_header.add_child(dot)

	var name_label := Label.new()
	name_label.text = "Tool"
	name_label.add_theme_color_override("font_color", Color("#6c63ff"))
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.name = "ToolNameLabel"
	_header.add_child(name_label)

	var step_label := Label.new()
	step_label.text = "Step 0"
	step_label.add_theme_color_override("font_color", Color("#555570"))
	step_label.add_theme_font_size_override("font_size", 11)
	_header.add_child(step_label)
	step_label.name = "StepLabel"

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)

	# Expand toggle button
	_expand_btn = Button.new()
	_expand_btn.text = "+"
	_expand_btn.custom_minimum_size = Vector2(28, 28)
	_expand_btn.add_theme_font_size_override("font_size", 14)
	_expand_btn.pressed.connect(_toggle_expand)
	_header.add_child(_expand_btn)

	# Body (collapsible)
	_body = VBoxContainer.new()
	_body.visible = false
	_body.add_theme_constant_override("separation", 4)
	vbox.add_child(_body)

	var args_header := Label.new()
	args_header.text = "Arguments"
	args_header.add_theme_font_size_override("font_size", 10)
	args_header.add_theme_color_override("font_color", Color("#555570"))
	_body.add_child(args_header)

	var args_label := Label.new()
	args_label.text = ""
	args_label.add_theme_font_size_override("font_size", 12)
	args_label.add_theme_color_override("font_color", Color("#9999bb"))
	args_label.name = "ArgsLabel"
	_body.add_child(args_label)

	var result_header := Label.new()
	result_header.text = "Result"
	result_header.add_theme_font_size_override("font_size", 10)
	result_header.add_theme_color_override("font_color", Color("#555570"))
	_body.add_child(result_header)

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.custom_minimum_size = Vector2(0, 24)
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.add_theme_font_size_override("normal_font_size", 12)
	_result_label.add_theme_color_override("default_color", Color("#aaaacc"))
	_result_label.text = "Waiting..."
	_body.add_child(_result_label)

	# Styling — accent left border, subtle shadow
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#141428")
	style.border_color = Color("#6c63ff")
	style.border_width_left = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.shadow_color = Color(0, 0, 0, 0.2)
	style.shadow_size = 3
	style.shadow_offset = Vector2(1, 2)
	add_theme_stylebox_override("panel", style)

func setup(step: int, tool_name: String, args: String) -> void:
	_step = step
	_tool_name = tool_name
	_args = args

	var name_node := _header.get_node("ToolNameLabel") as Label
	if name_node:
		name_node.text = tool_name

	var step_node := _header.get_node("StepLabel") as Label
	if step_node:
		step_node.text = "Step %d" % step

	var args_node := _body.get_node("ArgsLabel") as Label
	if args_node:
		args_node.text = args

func set_result(result: String) -> void:
	if _result_label:
		_result_label.clear()
		_result_label.append_text(result)
	# Auto-expand on result
	if not _expanded:
		_toggle_expand()

func _toggle_expand() -> void:
	_expanded = not _expanded
	_body.visible = _expanded
	_expand_btn.text = "-" if _expanded else "+"
