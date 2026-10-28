class_name UI
extends RefCounted
## Theme + small widget kit. Minimal black/white with a single orange accent.

const BG := Color(0.043, 0.043, 0.043, 0.94)
const BG_SOLID := Color(0.043, 0.043, 0.043, 1.0)
const BG2 := Color(0.085, 0.085, 0.085, 1.0)
const BG3 := Color(0.13, 0.13, 0.13, 1.0)
const LINE := Color(0.20, 0.20, 0.20, 1.0)
const TEXT := Color(0.95, 0.95, 0.94)
const MUTED := Color(0.58, 0.58, 0.57)
const DIM := Color(0.38, 0.38, 0.37)
const ACCENT := Color(1.0, 0.416, 0.075)
const ACCENT_DARK := Color(0.55, 0.22, 0.03)
const ERROR := Color(0.92, 0.30, 0.25)

static var _theme: Theme
static var _fonts := {}
static var _icons := {}


static func font(weight: int = 400) -> FontFile:
	if _fonts.has(weight):
		return _fonts[weight]
	var f: FontFile = load("res://assets/fonts/inter-latin-%d-normal.woff2" % weight)
	_fonts[weight] = f
	return f


static func icon(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var path := "res://assets/icons/%s.svg" % name
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icons[name] = t
	return t


static func flat(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 2, pad: Vector4 = Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = 15
	# Label
	t.set_color("font_color", "Label", TEXT)
	# Panel
	t.set_stylebox("panel", "Panel", flat(BG, LINE, 1, 2, Vector4(0, 0, 0, 0)))
	t.set_stylebox("panel", "PanelContainer", flat(BG, LINE, 1, 2, Vector4(14, 12, 14, 12)))
	# Button
	t.set_stylebox("normal", "Button", flat(BG2, LINE, 1))
	t.set_stylebox("hover", "Button", flat(BG3, Color(0.35, 0.35, 0.35), 1))
	t.set_stylebox("pressed", "Button", flat(ACCENT, ACCENT, 1))
	t.set_stylebox("hover_pressed", "Button", flat(ACCENT, ACCENT, 1))
	t.set_stylebox("disabled", "Button", flat(Color(0.06, 0.06, 0.06), Color(0.14, 0.14, 0.14), 1))
	t.set_stylebox("focus", "Button", flat(Color(0, 0, 0, 0), ACCENT, 1))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.04, 0.04, 0.04))
	t.set_color("font_hover_pressed_color", "Button", Color(0.04, 0.04, 0.04))
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("icon_normal_color", "Button", TEXT)
	t.set_color("icon_pressed_color", "Button", Color(0.04, 0.04, 0.04))
	t.set_color("icon_hover_pressed_color", "Button", Color(0.04, 0.04, 0.04))
	t.set_color("icon_disabled_color", "Button", DIM)
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 18)
	# LineEdit
	t.set_stylebox("normal", "LineEdit", flat(BG2, LINE, 1, 2, Vector4(10, 8, 10, 8)))
	t.set_stylebox("focus", "LineEdit", flat(BG2, ACCENT, 1, 2, Vector4(10, 8, 10, 8)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", ACCENT_DARK)
	# ProgressBar
	t.set_stylebox("background", "ProgressBar", flat(BG3, Color(0, 0, 0, 0), 0, 1, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", flat(ACCENT, Color(0, 0, 0, 0), 0, 1, Vector4(0, 0, 0, 0)))
	t.set_color("font_color", "ProgressBar", TEXT)
	# ItemList
	t.set_stylebox("panel", "ItemList", flat(BG2, LINE, 1, 2, Vector4(4, 4, 4, 4)))
	t.set_stylebox("hovered", "ItemList", flat(BG3))
	t.set_stylebox("selected", "ItemList", flat(ACCENT_DARK))
	t.set_stylebox("selected_focus", "ItemList", flat(ACCENT_DARK))
	t.set_stylebox("focus", "ItemList", flat(Color(0, 0, 0, 0)))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	# Tooltip
	t.set_stylebox("panel", "TooltipPanel", flat(BG_SOLID, LINE, 1, 2, Vector4(8, 6, 8, 6)))
	t.set_color("font_color", "TooltipLabel", TEXT)
	# Separator
	t.set_stylebox("separator", "HSeparator", flat(LINE, Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	t.set_constant("separation", "HSeparator", 1)
	# Scrollbars
	t.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector4(4, 0, 4, 0)))
	t.set_stylebox("grabber", "VScrollBar", flat(Color(0.3, 0.3, 0.3), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(Color(0.45, 0.45, 0.45), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(ACCENT, Color(0, 0, 0, 0), 0, 3))
	# OptionButton / PopupMenu
	t.set_stylebox("normal", "OptionButton", flat(BG2, LINE, 1))
	t.set_stylebox("hover", "OptionButton", flat(BG3, Color(0.35, 0.35, 0.35), 1))
	t.set_stylebox("pressed", "OptionButton", flat(BG3, ACCENT, 1))
	t.set_stylebox("focus", "OptionButton", flat(Color(0, 0, 0, 0), ACCENT, 1))
	t.set_stylebox("panel", "PopupMenu", flat(BG_SOLID, LINE, 1, 2, Vector4(4, 4, 4, 4)))
	t.set_stylebox("hover", "PopupMenu", flat(ACCENT_DARK))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	# CheckButton / CheckBox
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_stylebox("normal", "CheckButton", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, Vector4(2, 2, 2, 2)))
	t.set_stylebox("pressed", "CheckButton", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, Vector4(2, 2, 2, 2)))
	t.set_stylebox("hover", "CheckButton", flat(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 2, Vector4(2, 2, 2, 2)))
	t.set_stylebox("hover_pressed", "CheckButton", flat(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 2, Vector4(2, 2, 2, 2)))
	# RichTextLabel
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("normal_font", "RichTextLabel", font(400))
	t.set_font("bold_font", "RichTextLabel", font(600))
	_theme = t
	return t


# --- widget helpers -------------------------------------------------------------------------

static func label(text: String, size := 15, color := TEXT, weight := 400) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if weight != 400:
		l.add_theme_font_override("font", font(weight))
	return l


static func caps(text: String, color := MUTED) -> Label:
	var l := label(text.to_upper(), 11, color, 600)
	l.add_theme_constant_override("line_spacing", 0)
	return l


static func button(text: String, icon_name := "", accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = false
	if accent:
		b.add_theme_stylebox_override("normal", flat(ACCENT, ACCENT, 1))
		b.add_theme_stylebox_override("hover", flat(ACCENT.lightened(0.12), ACCENT.lightened(0.12), 1))
		b.add_theme_color_override("font_color", Color(0.04, 0.04, 0.04))
		b.add_theme_color_override("font_hover_color", Color(0.04, 0.04, 0.04))
		b.add_theme_color_override("icon_normal_color", Color(0.04, 0.04, 0.04))
		b.add_theme_color_override("icon_hover_color", Color(0.04, 0.04, 0.04))
		b.add_theme_font_override("font", font(600))
	return b


static func icon_button(icon_name: String, tooltip: String, toggle := false) -> Button:
	var b := Button.new()
	b.icon = icon(icon_name)
	b.tooltip_text = tooltip
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(38, 38)
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2, Vector4(6, 6, 6, 6)))
	b.add_theme_stylebox_override("hover", flat(BG3, Color(0, 0, 0, 0), 0, 2, Vector4(6, 6, 6, 6)))
	b.add_theme_stylebox_override("pressed", flat(ACCENT, Color(0, 0, 0, 0), 0, 2, Vector4(6, 6, 6, 6)))
	b.add_theme_stylebox_override("hover_pressed", flat(ACCENT, Color(0, 0, 0, 0), 0, 2, Vector4(6, 6, 6, 6)))
	return b


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func panel(pad := Vector4(16, 14, 16, 14), bg := BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(bg, LINE, 1, 2, pad))
	return p


static func sep() -> HSeparator:
	return HSeparator.new()


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Key/value row: muted key left, value right.
static func kv(key: String, value: String) -> HBoxContainer:
	var h := hbox(10)
	var k := label(key, 13, MUTED)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(k)
	var v := label(value, 13, TEXT, 500)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.name = "Value"
	h.add_child(v)
	return h


static func tex_icon(name: String, size := 18, color := TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(name)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.modulate = color
	return r
