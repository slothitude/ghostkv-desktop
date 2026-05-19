extends PanelContainer

var _header: HBoxContainer
var _body: VBoxContainer
var _result_label: RichTextLabel
var _expanded: bool = false
var _step: int = 0
var _tool_name: String = ""
var _args: String = ""
var _expand_btn: Button
var _desc_label: Label
var _schema_label: RichTextLabel

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Header row
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 8)
	vbox.add_child(_header)

	# Tool icon indicator
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
	step_label.name = "StepLabel"
	_header.add_child(step_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)

	# Expand toggle button
	_expand_btn = Button.new()
	_expand_btn.text = "+"
	_expand_btn.custom_minimum_size = Vector2(36, 36)
	_expand_btn.add_theme_font_size_override("font_size", 14)
	_expand_btn.pressed.connect(_toggle_expand)
	_header.add_child(_expand_btn)

	# Body (collapsible)
	_body = VBoxContainer.new()
	_body.visible = false
	_body.add_theme_constant_override("separation", 4)
	vbox.add_child(_body)

	# Description (shown if available)
	_desc_label = Label.new()
	_desc_label.text = ""
	_desc_label.add_theme_font_size_override("font_size", 11)
	_desc_label.add_theme_color_override("font_color", Color("#8888aa"))
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.name = "DescLabel"
	_desc_label.visible = false
	_body.add_child(_desc_label)

	# Schema section
	var schema_header := Label.new()
	schema_header.text = "Parameters"
	schema_header.add_theme_font_size_override("font_size", 10)
	schema_header.add_theme_color_override("font_color", Color("#555570"))
	schema_header.name = "SchemaHeader"
	schema_header.visible = false
	_body.add_child(schema_header)

	_schema_label = RichTextLabel.new()
	_schema_label.bbcode_enabled = true
	_schema_label.fit_content = true
	_schema_label.custom_minimum_size = Vector2(0, 0)
	_schema_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_schema_label.add_theme_font_size_override("normal_font_size", 11)
	_schema_label.add_theme_color_override("default_color", Color("#9999bb"))
	_schema_label.name = "SchemaLabel"
	_schema_label.visible = false
	_body.add_child(_schema_label)

	# Arguments section
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

	# Result section
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

	# Styling
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

	# Look up tool schema and description from tool_dispatch
	var tool_dispatch := Engine.get_singleton("ToolDispatch") as Node
	if tool_dispatch:
		var desc: String = tool_dispatch.get_tool_description(tool_name)
		if not desc.is_empty():
			var desc_node := _body.get_node("DescLabel") as Label
			if desc_node:
				desc_node.text = desc
				desc_node.visible = true

		var schema: Dictionary = tool_dispatch.get_tool_schema(tool_name)
		if schema.has("properties"):
			_show_schema(schema)

func _show_schema(schema: Dictionary) -> void:
	var schema_header := _body.get_node("SchemaHeader") as Label
	var schema_label := _body.get_node("SchemaLabel") as RichTextLabel
	if not schema_header or not schema_label:
		return

	var required: Array = schema.get("required", [])
	var props: Dictionary = schema.get("properties", {})
	if props.is_empty():
		return

	schema_header.visible = true
	schema_label.visible = true

	var lines: PackedStringArray = []
	for param_name in props:
		var prop: Dictionary = props[param_name]
		var type_str: String = prop.get("type", "any")
		var desc_str: String = prop.get("description", "")
		var req := " [color=#ff8899]*[/color]" if required.has(param_name) else ""
		var line := "[color=#6c63ff]%s[/color]: [color=#56b6c2]%s[/color]%s" % [param_name, type_str, req]
		if not desc_str.is_empty():
			line += " — %s" % desc_str
		lines.append(line)

	schema_label.clear()
	schema_label.append_text("\n".join(lines))

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
