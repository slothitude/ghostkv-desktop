extends PanelContainer

signal confirmed()
signal cancelled()

var _action_label: Label
var _msg_label: RichTextLabel
var _confirm_btn: Button
var _cancel_btn: Button

func _ready() -> void:
	# Full-screen backdrop
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Semi-transparent background
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.7)
	bg.corner_radius_top_left = 12
	bg.corner_radius_top_right = 12
	bg.corner_radius_bottom_left = 12
	bg.corner_radius_bottom_right = 12
	add_theme_stylebox_override("panel", bg)

	# Centered content
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(360, 0)
	center.add_child(vbox)

	# Title / Action type
	_action_label = Label.new()
	_action_label.add_theme_font_size_override("font_size", 20)
	_action_label.add_theme_color_override("font_color", Color("#ff7788"))
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_action_label)

	# Message details
	_msg_label = RichTextLabel.new()
	_msg_label.bbcode_enabled = true
	_msg_label.fit_content = true
	_msg_label.custom_minimum_size = Vector2(340, 0)
	_msg_label.add_theme_color_override("default_color", Color("#ccccdd"))
	_msg_label.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(_msg_label)

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(120, 44)
	_cancel_btn.add_theme_font_size_override("font_size", 15)
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = Color("#2a2a40")
	cancel_style.corner_radius_top_left = 8
	cancel_style.corner_radius_top_right = 8
	cancel_style.corner_radius_bottom_left = 8
	cancel_style.corner_radius_bottom_right = 8
	_cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	_cancel_btn.add_theme_color_override("font_color", Color("#888899"))
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.custom_minimum_size = Vector2(120, 44)
	_confirm_btn.add_theme_font_size_override("font_size", 15)
	var confirm_style := StyleBoxFlat.new()
	confirm_style.bg_color = Color("#6c63ff")
	confirm_style.corner_radius_top_left = 8
	confirm_style.corner_radius_top_right = 8
	confirm_style.corner_radius_bottom_left = 8
	confirm_style.corner_radius_bottom_right = 8
	_confirm_btn.add_theme_stylebox_override("normal", confirm_style)
	_confirm_btn.add_theme_color_override("font_color", Color("#ffffff"))
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	visible = false

func show_confirm(action: String, phone: String, contact_name: String, message: String = "") -> void:
	_action_label.text = action
	var details := "[b]To:[/b] "
	if contact_name != "":
		details += "%s (%s)" % [contact_name, phone]
	else:
		details += phone
	if message != "":
		details += "\n[b]Message:[/b] %s" % message
	_msg_label.parse_bbcode(details)
	visible = true

	# Grab focus for quick confirm
	_confirm_btn.grab_focus()

func _on_confirm() -> void:
	visible = false
	confirmed.emit()

func _on_cancel() -> void:
	visible = false
	cancelled.emit()
