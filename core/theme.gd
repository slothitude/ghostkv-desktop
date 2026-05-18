extends Node

const BG := Color("#0a0a0f")
const SIDEBAR := Color("#12121a")
const CARD := Color("#1a1a2e")
const ACCENT := Color("#6c63ff")
const ACCENT_HOVER := Color("#7b73ff")
const TEXT := Color("#e0e0e0")
const TEXT_DIM := Color("#888899")
const USER_BUBBLE := Color("#2a2a4a")
const TOOL_BORDER := Color("#6c63ff")
const ERROR_COLOR := Color("#ff5555")
const SUCCESS := Color("#55ff88")

func build_theme() -> Theme:
	var t := Theme.new()

	t.set_color("background", "PanelContainer", BG)
	t.set_color("background", " VBoxContainer", Color.TRANSPARENT)

	# Base font color
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_color", "TextEdit", TEXT)
	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("font_placeholder_color", "TextEdit", TEXT_DIM)

	# Buttons
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = ACCENT
	btn_normal.corner_radius_top_left = 6
	btn_normal.corner_radius_top_right = 6
	btn_normal.corner_radius_bottom_left = 6
	btn_normal.corner_radius_bottom_right = 6
	t.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = ACCENT_HOVER
	t.set_stylebox("hover", "Button", btn_hover)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = ACCENT.darkened(0.2)
	t.set_stylebox("pressed", "Button", btn_pressed)

	var btn_disabled := btn_normal.duplicate()
	btn_disabled.bg_color = Color("#444466")
	t.set_stylebox("disabled", "Button", btn_disabled)

	t.set_color("font_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 14)

	# Panels
	var panel := StyleBoxFlat.new()
	panel.bg_color = SIDEBAR
	panel.corner_radius_top_left = 0
	panel.corner_radius_top_right = 0
	panel.corner_radius_bottom_left = 0
	panel.corner_radius_bottom_right = 0
	t.set_stylebox("panel", "PanelContainer", panel)

	# LineEdit
	var le_normal := StyleBoxFlat.new()
	le_normal.bg_color = CARD
	le_normal.border_color = Color("#333355")
	le_normal.border_width_bottom = 1
	le_normal.corner_radius_top_left = 4
	le_normal.corner_radius_top_right = 4
	le_normal.corner_radius_bottom_left = 4
	le_normal.corner_radius_bottom_right = 4
	t.set_stylebox("normal", "LineEdit", le_normal)

	var le_focus := le_normal.duplicate()
	le_focus.border_color = ACCENT
	le_focus.border_width_bottom = 2
	t.set_stylebox("focused", "LineEdit", le_focus)

	# TextEdit
	var te := le_normal.duplicate()
	t.set_stylebox("normal", "TextEdit", te)
	var te_focus := le_focus.duplicate()
	t.set_stylebox("focused", "TextEdit", te_focus)

	# ScrollContainer
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color.TRANSPARENT
	t.set_stylebox("panel", "ScrollContainer", sc)

	# VScrollBar / HScrollBar
	var sb_grabber := StyleBoxFlat.new()
	sb_grabber.bg_color = Color("#444466")
	sb_grabber.corner_radius_top_left = 4
	sb_grabber.corner_radius_top_right = 4
	sb_grabber.corner_radius_bottom_left = 4
	sb_grabber.corner_radius_bottom_right = 4
	t.set_stylebox("grabber", "VScrollBar", sb_grabber)
	t.set_stylebox("grabber", "HScrollBar", sb_grabber)

	# TabBar /ItemList
	var item_panel := StyleBoxFlat.new()
	item_panel.bg_color = Color.TRANSPARENT
	t.set_stylebox("panel", "ItemList", item_panel)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_hovered_color", "ItemList", ACCENT)
	t.set_color("font_selected_color", "ItemList", ACCENT)

	# SpinBox
	t.set_stylebox("normal", "SpinBox", le_normal)
	t.set_stylebox("up_background", "SpinBox", btn_normal)
	t.set_stylebox("down_background", "SpinBox", btn_normal)

	return t
