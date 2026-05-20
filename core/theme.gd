extends Node

const BG := Color("#0d0d14")
const SIDEBAR := Color("#111118")
const CARD := Color("#1a1a28")
const ACCENT := Color("#6c63ff")
const ACCENT_HOVER := Color("#8b83ff")
const ACCENT_DIM := Color("#4a44aa")
const TEXT := Color("#e8e8f0")
const TEXT_DIM := Color("#6b6b80")
const TEXT_BRIGHT := Color("#ffffff")
const USER_BUBBLE := Color("#2a2a50")
const ASSISTANT_BUBBLE := Color("#16162a")
const TOOL_BG := Color("#141428")
const TOOL_BORDER := Color("#6c63ff")
const ERROR_COLOR := Color("#ff4466")
const SUCCESS := Color("#44ff88")
const BORDER := Color("#2a2a40")

func build_theme() -> Theme:
	var t := Theme.new()

	# Load Kenney font
	var title_font := load("res://assets/fonts/kenney_future.ttf") as FontFile
	var body_font := load("res://assets/fonts/kenney_future_narrow.ttf") as FontFile

	if title_font:
		t.set_font("font", "Label", title_font)
		t.set_font("font", "Button", title_font)
	if body_font:
		t.set_font("font", "LineEdit", body_font)
		t.set_font("font", "TextEdit", body_font)
		t.set_font("font", "RichTextLabel", body_font)
		t.set_font("font", "ItemList", body_font)
		t.set_font("font", "SpinBox", body_font)

	t.set_color("background", "PanelContainer", BG)
	t.set_constant("separation", "HBoxContainer", 0)
	t.set_constant("separation", "VBoxContainer", 0)

	# Base font colors
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "LineEdit", TEXT_BRIGHT)
	t.set_color("font_color", "TextEdit", TEXT)
	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("font_placeholder_color", "TextEdit", TEXT_DIM)
	t.set_font_size("font_size", "Label", 13)
	t.set_font_size("font_size", "Button", 13)
	t.set_font_size("font_size", "LineEdit", 14)
	t.set_font_size("font_size", "TextEdit", 13)
	t.set_font_size("font_size", "RichTextLabel", 14)
	t.set_font_size("font_size", "ItemList", 12)
	t.set_font_size("font_size", "SpinBox", 13)

	# === Buttons — rounded, accent gradient feel ===
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = ACCENT
	btn_normal.border_color = ACCENT.lightened(0.15)
	btn_normal.border_width_top = 1
	btn_normal.border_width_bottom = 2
	btn_normal.corner_radius_top_left = 6
	btn_normal.corner_radius_top_right = 6
	btn_normal.corner_radius_bottom_left = 6
	btn_normal.corner_radius_bottom_right = 6
	btn_normal.content_margin_top = 6
	btn_normal.content_margin_bottom = 6
	btn_normal.content_margin_left = 14
	btn_normal.content_margin_right = 14
	btn_normal.shadow_color = Color(0, 0, 0, 0.3)
	btn_normal.shadow_size = 3
	btn_normal.shadow_offset = Vector2(0, 2)
	t.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = ACCENT_HOVER
	btn_hover.border_color = ACCENT_HOVER.lightened(0.2)
	t.set_stylebox("hover", "Button", btn_hover)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = ACCENT.darkened(0.15)
	btn_pressed.shadow_size = 1
	btn_pressed.shadow_offset = Vector2(0, 0)
	t.set_stylebox("pressed", "Button", btn_pressed)

	var btn_disabled := btn_normal.duplicate()
	btn_disabled.bg_color = Color("#2a2a44")
	btn_disabled.border_color = Color("#3a3a55")
	btn_disabled.shadow_size = 0
	t.set_stylebox("disabled", "Button", btn_disabled)

	t.set_color("font_color", "Button", TEXT_BRIGHT)
	t.set_color("font_hover_color", "Button", TEXT_BRIGHT)
	t.set_color("font_pressed_color", "Button", Color("#ccccff"))
	t.set_color("font_disabled_color", "Button", TEXT_DIM)

	# === Panels — sidebar dark ===
	var panel := StyleBoxFlat.new()
	panel.bg_color = SIDEBAR
	panel.border_color = BORDER
	panel.border_width_right = 1
	t.set_stylebox("panel", "PanelContainer", panel)

	# === LineEdit — clean dark input ===
	var le_normal := StyleBoxFlat.new()
	le_normal.bg_color = CARD
	le_normal.border_color = BORDER
	le_normal.border_width_bottom = 1
	le_normal.corner_radius_top_left = 6
	le_normal.corner_radius_top_right = 6
	le_normal.corner_radius_bottom_left = 6
	le_normal.corner_radius_bottom_right = 6
	le_normal.content_margin_left = 12
	le_normal.content_margin_top = 6
	le_normal.content_margin_bottom = 6
	t.set_stylebox("normal", "LineEdit", le_normal)

	var le_focus := le_normal.duplicate()
	le_focus.border_color = ACCENT
	le_focus.border_width_bottom = 2
	le_focus.bg_color = Color("#1e1e36")
	t.set_stylebox("focused", "LineEdit", le_focus)

	# === TextEdit ===
	t.set_stylebox("normal", "TextEdit", le_normal)
	t.set_stylebox("focused", "TextEdit", le_focus)

	# === ScrollContainer ===
	var sc := StyleBoxFlat.new()
	sc.bg_color = Color.TRANSPARENT
	t.set_stylebox("panel", "ScrollContainer", sc)

	# === ScrollBars — subtle rounded ===
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color.TRANSPARENT
	t.set_stylebox("scroll", "VScrollBar", sb_bg)
	t.set_stylebox("scroll", "HScrollBar", sb_bg)

	var sb_grabber := StyleBoxFlat.new()
	sb_grabber.bg_color = Color("#3a3a55")
	sb_grabber.corner_radius_top_left = 4
	sb_grabber.corner_radius_top_right = 4
	sb_grabber.corner_radius_bottom_left = 4
	sb_grabber.corner_radius_bottom_right = 4
	t.set_stylebox("grabber", "VScrollBar", sb_grabber)
	t.set_stylebox("grabber", "HScrollBar", sb_grabber)

	var sb_hover := sb_grabber.duplicate()
	sb_hover.bg_color = Color("#5a5a77")
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_hover)
	t.set_stylebox("grabber_highlight", "HScrollBar", sb_hover)

	# === ItemList — clean transparent ===
	var item_panel := StyleBoxFlat.new()
	item_panel.bg_color = Color.TRANSPARENT
	t.set_stylebox("panel", "ItemList", item_panel)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_hovered_color", "ItemList", ACCENT_HOVER)
	t.set_color("font_selected_color", "ItemList", ACCENT)

	var item_selected := StyleBoxFlat.new()
	item_selected.bg_color = Color("#2a2a4a")
	item_selected.corner_radius_top_left = 4
	item_selected.corner_radius_top_right = 4
	item_selected.corner_radius_bottom_left = 4
	item_selected.corner_radius_bottom_right = 4
	t.set_stylebox("selected", "ItemList", item_selected)

	var item_hover := StyleBoxFlat.new()
	item_hover.bg_color = Color("#1e1e3a")
	item_hover.corner_radius_top_left = 4
	item_hover.corner_radius_top_right = 4
	item_hover.corner_radius_bottom_left = 4
	item_hover.corner_radius_bottom_right = 4
	t.set_stylebox("hovered", "ItemList", item_hover)

	# === SpinBox ===
	var spin_bg := StyleBoxFlat.new()
	spin_bg.bg_color = CARD
	spin_bg.border_color = BORDER
	spin_bg.border_width_bottom = 1
	spin_bg.corner_radius_top_left = 4
	spin_bg.corner_radius_top_right = 4
	spin_bg.corner_radius_bottom_left = 4
	spin_bg.corner_radius_bottom_right = 4
	t.set_stylebox("normal", "SpinBox", spin_bg)

	# === HSeparator ===
	var sep := StyleBoxFlat.new()
	sep.bg_color = BORDER
	sep.content_margin_top = 1
	sep.content_margin_bottom = 1
	t.set_stylebox("separator", "HSeparator", sep)

	return t
