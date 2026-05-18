extends PanelContainer

var _header: HBoxContainer
var _body: VBoxContainer
var _result_label: RichTextLabel
var _expanded: bool = false
var _step: int = 0
var _tool_name: String = ""
var _args: String = ""

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Header row
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	vbox.add_child(_header)

	var icon_label := Label.new()
	icon_label.text = ">"
	icon_label.add_theme_color_override("font_color", Color("#6c63ff"))
	icon_label.add_theme_font_size_override("font_size", 14)
	_header.add_child(icon_label)

	var name_label := Label.new()
	name_label.text = "Tool"
	name_label.add_theme_color_override("font_color", Color("#6c63ff"))
	name_label.add_theme_font_size_override("font_size", 13)
	_header.add_child(name_label)
	name_label.name = "ToolNameLabel"

	var step_label := Label.new()
	step_label.text = "Step 0"
	step_label.add_theme_color_override("font_color", Color("#888899"))
	step_label.add_theme_font_size_override("font_size", 11)
	_header.add_child(step_label)
	step_label.name = "StepLabel"

	# Expand button
	var expand_btn := Button.new()
	expand_btn.text = "+"
	expand_btn.custom_minimum_size = Vector2(24, 24)
	expand_btn.pressed.connect(_toggle_expand)
	_header.add_child(expand_btn)

	# Body (collapsible)
	_body = VBoxContainer.new()
	_body.visible = false
	_body.add_theme_constant_override("separation", 4)
	vbox.add_child(_body)

	var args_header := Label.new()
	args_header.text = "Arguments:"
	args_header.add_theme_font_size_override("font_size", 11)
	args_header.add_theme_color_override("font_color", Color("#888899"))
	_body.add_child(args_header)

	var args_label := Label.new()
	args_label.text = ""
	args_label.add_theme_font_size_override("font_size", 12)
	args_label.name = "ArgsLabel"
	_body.add_child(args_label)

	var result_header := Label.new()
	result_header.text = "Result:"
	result_header.add_theme_font_size_override("font_size", 11)
	result_header.add_theme_color_override("font_color", Color("#888899"))
	_body.add_child(result_header)

	_result_label = RichTextLabel.new()
	_result_label.bbcode_enabled = true
	_result_label.fit_content = true
	_result_label.custom_minimum_size.y = 20
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.add_theme_font_size_override("normal_font_size", 12)
	_result_label.text = "Waiting..."
	_body.add_child(_result_label)

	# Styling — accent left border
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#12121a")
	style.border_color = Color("#6c63ff")
	style.border_width_left = 3
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
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
		_result_label.text = result

func _toggle_expand() -> void:
	_expanded = not _expanded
	_body.visible = _expanded
